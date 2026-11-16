#!/usr/bin/env python3
"""Independent reference and measuring instrument, never an AIEN runtime.

The recursive oracle evaluates labeled occurrence graphs independently from the
worker. Eight little-endian uint64 request words are echoed followed by result.
All arithmetic is exact modulo 65521. Time and placement are realization data.
"""
import argparse
import concurrent.futures
import hashlib
import itertools
import json
import os
from pathlib import Path
import random
import selectors
import struct
import subprocess
import tempfile
import time
import traceback

MOD = 65521
REQUEST = struct.Struct("<8Q")
RESPONSE = struct.Struct("<9Q")
SEED = 23547813


class Refusal(Exception):
    def __init__(self, reason, detail):
        self.reason, self.detail = reason, detail
        super().__init__(reason + ": " + str(detail))


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def node(op, parents=(), left=None, right=None, x=0, y=0):
    return dict(op=op, parents=list(parents), left=left, right=right, x=x, y=y)


def paper_graph(a=3, b=1, c=2, d=5):
    return [node(1, x=a, y=b), node(2, x=c, y=d),
            node(1, (0, 1), 0, 1), node(2, (2,), 2, 2)]


def reference(graph):
    """Recursive memoized evaluation by occurrence and ordered port role."""
    memo, active = {}, set()

    def visit(i):
        if i in active:
            raise Refusal("GRAPH_CYCLE", i)
        if i not in memo:
            active.add(i)
            n = graph[i]
            x = visit(n["left"]) if n["left"] is not None else n["x"]
            y = visit(n["right"]) if n["right"] is not None else n["y"]
            operations = {1: lambda: x + y, 2: lambda: x * y,
                          3: lambda: x - y, 4: lambda: x}
            if n["op"] not in operations:
                raise Refusal("UNKNOWN_OPERATION", n["op"])
            memo[i] = operations[n["op"]]() % MOD
            active.remove(i)
        return memo[i]
    return [visit(i) for i in range(len(graph))]


def orderings(graph):
    """All linear extensions by recursive enabled-set search."""
    def expand(prefix, remaining):
        if not remaining:
            yield prefix
        for i in sorted(remaining):
            if set(graph[i]["parents"]).issubset(prefix):
                yield from expand(prefix + [i], remaining - {i})
    yield from expand([], set(range(len(graph))))


def random_order(graph, rng):
    result, remaining = [], set(range(len(graph)))
    while remaining:
        ready = sorted(i for i in remaining
                       if set(graph[i]["parents"]).issubset(result))
        if not ready:
            raise Refusal("GRAPH_CYCLE", sorted(remaining))
        chosen = rng.choice(ready)
        result.append(chosen)
        remaining.remove(chosen)
    return result


def small_graphs(rng):
    for n in range(1, 5):
        possible = list(itertools.combinations(range(n), 2))
        for mask in range(1 << len(possible)):
            edges = [e for k, e in enumerate(possible) if mask & (1 << k)]
            parent_sets = [[a for a, b in edges if b == i] for i in range(n)]
            if any(len(parents) > 2 for parents in parent_sets):
                continue
            graph = []
            for parents in parent_sets:
                graph.append(node(rng.choice((1, 2, 3)), parents,
                                  parents[0] if parents else None,
                                  parents[1] if len(parents) > 1 else None,
                                  rng.randrange(MOD), rng.randrange(MOD)))
            yield f"small-{n}-{mask}", graph


def large_graph(n, rng, additive=False):
    graph = []
    for i in range(n):
        parents = sorted(rng.sample(range(i), min(i, rng.randrange(3))))
        graph.append(node(1 if additive else rng.choice((1, 2, 3)), parents,
                          parents[0] if parents else None,
                          parents[1] if len(parents) > 1 else None,
                          rng.randrange(MOD), rng.randrange(MOD)))
    return graph


def verify_response(request, response, expected=None):
    if tuple(response[:8]) != tuple(request):
        raise Refusal("PROJECTION_SOUNDNESS", {"requested": request,
                                                "returned": response[:8]})
    if expected is not None and response[8] != expected:
        raise Refusal("VALUE_MISMATCH", {"expected": expected,
                                         "observed": response[8]})


def read_exact(pipe, amount, timeout=30):
    result = bytearray()
    deadline = time.monotonic() + timeout
    with selectors.DefaultSelector() as selector:
        selector.register(pipe, selectors.EVENT_READ)
        while len(result) < amount:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                raise Refusal("WORKER_TIMEOUT", {"bytes": len(result)})
            part = os.read(pipe.fileno(), amount - len(result))
            if not part:
                raise Refusal("WORKER_SHORT_RESPONSE", {"bytes": len(result)})
            result.extend(part)
    return bytes(result)


def request_for(i, n, values, delay, nonce):
    x = values[n["left"]] if n["left"] is not None else n["x"]
    y = values[n["right"]] if n["right"] is not None else n["y"]
    return (i, n["op"], 0 if n["left"] is None else n["left"] + 1,
            0 if n["right"] is None else n["right"] + 1, x, y, delay, nonce)


def execute(worker, graph, order, nonce, delays, record, gpu=None,
            placements=None, check_values=True, effects=False, trace=None,
            issue_hook=None):
    for i, n in enumerate(graph):
        bindings = {p for p in (n["left"], n["right"]) if p is not None}
        if bindings != set(n["parents"]) or any(p < 0 or p >= len(graph) for p in bindings):
            raise Refusal("GRAPH_PORT_DEPENDENCY", i)
    expected = reference(graph)
    values, seen, streams = {}, set(), {}
    record.update(graph=graph, graph_sha256=hashlib.sha256(canonical(graph)).hexdigest(),
                  order=order, expected=expected, nonce=nonce, events=[])
    record["program_preimage"] = program_preimage(graph)
    record["program_id"] = hashlib.sha256(canonical(record["program_preimage"])).hexdigest()
    record["start_monotonic_ns"] = time.monotonic_ns()
    failure = None
    try:
        for i in order:
            if i in seen or i < 0 or i >= len(graph):
                raise Refusal("SCHEDULE_OCCURRENCE", i)
            n = graph[i]
            if not set(n["parents"]).issubset(seen):
                raise Refusal("SCHEDULE_DEPENDENCY", i)
            device = placements[i] if placements else "cpu"
            if device == "gpu" and n["op"] != 1:
                raise Refusal("UNSUPPORTED_GPU_OPERATION", n["op"])
            selected = gpu if device == "gpu" else worker
            if selected is None:
                raise Refusal("MISSING_WORKER", device)
            if device not in streams:
                errfile = tempfile.TemporaryFile()
                command = [str(selected)]
                if trace is not None:
                    command = ["strace", "-qq", "-o", str(trace), "-e",
                               "trace=clock_gettime,getrandom", "--"] + command
                process = subprocess.Popen(command, stdin=subprocess.PIPE,
                                           stdout=subprocess.PIPE, stderr=errfile)
                streams[device] = (process, errfile)
            process, _ = streams[device]
            req = request_for(i, n, values, delays[i], nonce)
            start = time.monotonic_ns()
            process.stdin.write(REQUEST.pack(*req))
            process.stdin.flush()
            if issue_hook is not None:
                issue_hook()
            reply = RESPONSE.unpack(read_exact(process.stdout, RESPONSE.size))
            end = time.monotonic_ns()
            record["events"].append(dict(request=req, response=reply, device=device,
                                         worker=str(selected), start_monotonic_ns=start,
                                         end_monotonic_ns=end))
            if end - start < delays[i]:
                raise Refusal("REALIZATION_DELAY_NOT_OBSERVED",
                              dict(requested_ns=delays[i], observed_ns=end - start))
            verify_response(req, reply, expected[i] if check_values else None)
            values[i] = reply[8]
            seen.add(i)
        if len(seen) != len(graph):
            raise Refusal("SCHEDULE_INCOMPLETE", len(seen))
    except BaseException as exc:
        failure = exc
    finally:
        record["workers"] = {}
        for device, (process, errfile) in streams.items():
            try:
                process.stdin.close()
                process.wait(timeout=30)
                trailing = process.stdout.read()
                errfile.seek(0)
                stderr = errfile.read()
                record["workers"][device] = dict(exit=process.returncode,
                                                 stderr_hex=stderr.hex(),
                                                 trailing_hex=trailing.hex())
                if failure is None:
                    if process.returncode != 0 or trailing:
                        raise Refusal("WORKER_EXIT_OR_TRAILING_OUTPUT",
                                      record["workers"][device])
                    expected_effects = bytes(graph[i]["x"] for i in order
                                             if graph[i]["op"] == 4) if effects else b""
                    if stderr != expected_effects:
                        raise Refusal("UNDECLARED_STDERR_EFFECT", stderr.hex())
            except BaseException as exc:
                if failure is None:
                    failure = exc
                if process.poll() is None:
                    process.kill()
                    process.wait()
            finally:
                process.stdout.close()
                errfile.close()
        record["end_monotonic_ns"] = time.monotonic_ns()
    if failure is not None:
        record["verdict"] = "REFUSED"
        record["execution_verdict"] = "REFUSED"
        record["reason"] = getattr(failure, "reason", type(failure).__name__)
        record["detail"] = str(failure)
        raise failure
    record["values"] = [values[i] for i in range(len(graph))]
    record["observed_program_preimage"] = observed_preimage(graph, record["events"])
    if canonical(record["observed_program_preimage"]) != canonical(record["program_preimage"]):
        raise Refusal("PROJECTION_SOUNDNESS", "full labeled occurrence graph differs")
    record["full_graph_preimage_equal"] = True
    record["verdict"] = "PASS"
    record["execution_verdict"] = "PASS"
    return record


def concurrent_pair(worker, nonce):
    """Complete paper graph after actual A-before-B / B-before-A completion."""
    graph = paper_graph()
    expected = reference(graph)
    started = __import__("threading").Event()
    processes = []
    record = dict(kind="independent-process-completion-reversal", graph=graph,
                  program_preimage=program_preimage(graph), expected=expected,
                  nonce=nonce, events=[], workers={})
    record["program_id"] = hashlib.sha256(canonical(record["program_preimage"])).hexdigest()
    values = {}
    try:
        for _ in range(2):
            stderr = tempfile.TemporaryFile()
            process = subprocess.Popen([str(worker)], stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=stderr)
            processes.append((process, stderr))

        def event(i, actor, delay):
            if i == 1 and not started.wait(timeout=30):
                raise Refusal("CONCURRENT_START_TIMEOUT", i)
            req = request_for(i, graph[i], values, delay, nonce)
            process = processes[actor][0]
            start = time.monotonic_ns()
            process.stdin.write(REQUEST.pack(*req))
            process.stdin.flush()
            if i == 0:
                started.set()
            reply = RESPONSE.unpack(read_exact(process.stdout, RESPONSE.size))
            end = time.monotonic_ns()
            observation = dict(request=req, response=reply, device="cpu",
                               worker=str(worker), actor=actor,
                               start_monotonic_ns=start, end_monotonic_ns=end)
            verify_response(req, reply, expected[i])
            if end - start < delay:
                raise Refusal("REALIZATION_DELAY_NOT_OBSERVED", observation)
            return observation

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            a = executor.submit(event, 0, 0, 30000000)
            b = executor.submit(event, 1, 1, 0)
            roots = [a.result(), b.result()]
        record["events"].extend(roots)
        starts = [r["start_monotonic_ns"] for r in roots]
        ends = [r["end_monotonic_ns"] for r in roots]
        if not starts[0] < starts[1] < ends[1] < ends[0]:
            raise Refusal("COMPLETION_REVERSAL_NOT_OBSERVED", dict(starts=starts, ends=ends))
        values.update({i: r["response"][8] for i, r in enumerate(roots)})
        for i in (2, 3):
            observation = event(i, 0, 0)
            record["events"].append(observation)
            values[i] = observation["response"][8]
        record.update(start_order=[0, 1, 2, 3], completion_order=[1, 0, 2, 3],
                      values=[values[i] for i in range(4)])
    finally:
        for actor, (process, stderr) in enumerate(processes):
            if process.poll() is None:
                process.stdin.close()
            try:
                process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
                raise Refusal("WORKER_TIMEOUT", actor)
            trailing = process.stdout.read()
            stderr.seek(0)
            error = stderr.read()
            record["workers"][actor] = dict(exit=process.returncode,
                                            trailing_hex=trailing.hex(), stderr_hex=error.hex())
            process.stdout.close()
            stderr.close()
            if process.returncode != 0 or trailing or error:
                raise Refusal("WORKER_EXIT_OR_TRAILING_OUTPUT", record["workers"][actor])
    record.update(verdict="PASS", execution_verdict="PASS")
    record["observed_program_preimage"] = observed_preimage(graph, record["events"])
    if canonical(record["observed_program_preimage"]) != canonical(record["program_preimage"]):
        raise Refusal("PROJECTION_SOUNDNESS", "concurrent full labeled occurrence graph differs")
    record["full_graph_preimage_equal"] = True
    return record


def program_preimage(graph):
    meanings = {1: "add(left,right) mod modulus", 2: "multiply(left,right) mod modulus",
                3: "subtract(left,right) mod modulus", 4: "append_byte(left); return left"}
    occurrences = []
    for i, n in enumerate(graph):
        label = dict(schema="semantic-vertex-label-v1", operation=n["op"],
                     definition=meanings[n["op"]],
                     value_type="unsigned integer residue", modulus=MOD,
                     parameter_types=dict(left="uint64", right="uint64"),
                     literal_parameters=dict(left=n["x"] if n["left"] is None else None,
                                             right=n["y"] if n["right"] is None else None),
                     ordered_input_port_roles=["left", "right"],
                     output_port_role="value",
                     declared_effects=["append left byte to shared write-only output channel"]
                     if n["op"] == 4 else [])
        occurrences.append(dict(id=i, **n, label_preimage=label,
                                label_sha256=hashlib.sha256(canonical(label)).hexdigest()))
    return dict(schema="labeled-occurrence-graph-v1", modulus=MOD,
                occurrences=occurrences,
                output_policy="all occurrence values in ID order; exact equality",
                effect_policy="ordered shared-channel byte trace retained exactly",
                operation_meanings=meanings)


def observed_preimage(declared_graph, events):
    """Reconstruct occurrence operations, port bindings, and literals from real replies."""
    observed = [dict(n, parents=list(n["parents"])) for n in declared_graph]
    seen = set()
    for event in events:
        reply = event["response"]
        i, op, left, right = reply[:4]
        if i in seen or not 0 <= i < len(observed):
            raise Refusal("PROJECTION_SOUNDNESS", "duplicate or foreign occurrence")
        seen.add(i)
        n = observed[i]
        n.update(op=op, left=None if left == 0 else left - 1,
                 right=None if right == 0 else right - 1,
                 parents=sorted({p - 1 for p in (left, right) if p != 0}))
        if left == 0:
            n["x"] = reply[4]
        if right == 0:
            n["y"] = reply[5]
    if seen != set(range(len(observed))):
        raise Refusal("PROJECTION_SOUNDNESS", "missing occurrence")
    return program_preimage(observed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", type=Path, required=True)
    parser.add_argument("--gpu-worker", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    worker = args.worker.resolve()
    gpu = args.gpu_worker.resolve() if args.gpu_worker else None
    args.out.mkdir(parents=True, exist_ok=False)
    rng = random.Random(SEED)
    mutants = {name: worker.with_name("worker-" + name)
               for name in ("clock", "random", "state", "hardcode")}
    if gpu:
        mutants["gpu-cache"] = worker.with_name("worker-gpu-cache")
    config = dict(schema="atemporal-schedule-invariance-v1", seed=SEED,
                  modulus=MOD, small_max_nodes=4,
                  small_graphs="all naturally numbered binary-input DAGs; every linear extension",
                  exclusions="DAGs with any vertex indegree greater than two",
                  port_rule="sorted parent 0 is left; sorted parent 1 is right",
                  varied_paper_inputs=32,
                  large_families=[dict(nodes=32, schedules=128),
                                  dict(nodes=96, schedules=64)],
                  per_event_delay_ns_choices=[0, 1000, 100000],
                  concurrent_delay_ns=30000000, worker_timeout_seconds=30,
                  timing="independent host monotonic request-to-response interval; includes IPC and scheduling",
                  gpu_schedules_per_family=32 if gpu else 0,
                  scope="finite host experiment" if not gpu else "finite CPU/GPU experiment",
                  excludes=["universal theorem proof", "production FORGE qualification",
                            "overlapping GPU dispatch"],
                  binaries={str(p): digest(p) for p in [worker, *mutants.values()] +
                            ([gpu] if gpu else [])},
                  oracle_sha256=digest(__file__))
    config_path = args.out / "config.json"
    config_path.write_bytes(canonical(config) + b"\n")
    summary = dict(config_sha256=digest(config_path), verdict="RUNNING",
                   positives=0, event_observations=0, small_graphs=0,
                   negatives={}, scope=config["scope"])
    tracefile = (args.out / "runs.jsonl").open("x")
    graph_family_preimages = {}

    def save(rec):
        if rec.get("kind") == "negative":
            rec.setdefault("control_admission", "REJECTED_BY_CLASSIFIER; see summary reason")
        tracefile.write(json.dumps(rec, sort_keys=True) + "\n")
        tracefile.flush()

    def positive(name, graph, order, gpu_placements=None):
        rec = dict(kind="positive", name=name,
                   program_preimage=program_preimage(graph),
                   program_id=hashlib.sha256(canonical(program_preimage(graph))).hexdigest())
        try:
            execute(worker, graph, order, rng.getrandbits(64),
                    [rng.choice(config["per_event_delay_ns_choices"]) for _ in graph],
                    rec, gpu, gpu_placements)
            family = name.rsplit("-order-", 1)[0] if "-order-" in name else name.rsplit("-", 1)[0]
            full_preimage = canonical(rec["observed_program_preimage"])
            if family in graph_family_preimages and graph_family_preimages[family] != full_preimage:
                raise Refusal("GRAPH_CHANGED_ACROSS_SCHEDULES", family)
            graph_family_preimages.setdefault(family, full_preimage)
            rec["cross_schedule_preimage_equal"] = True
            summary["positives"] += 1
            summary["event_observations"] += len(rec["events"])
        finally:
            save(rec)

    def control(name, action, reason):
        try:
            action()
        except Refusal as exc:
            if exc.reason != reason:
                raise Refusal("CONTROL_WRONG_REASON", dict(name=name, expected=reason,
                                                           observed=exc.reason)) from exc
            detail = exc.detail
        else:
            raise Refusal("CONTROL_ESCAPED", name)
        summary["negatives"][name] = dict(verdict="REJECTED_AS_REQUIRED",
                                          reason=reason, detail=detail)

    try:
        for name, graph in small_graphs(rng):
            summary["small_graphs"] += 1
            for index, order in enumerate(orderings(graph)):
                positive(f"{name}-order-{index}", graph, order)
        paper_input_preimages = set()
        for case in range(config["varied_paper_inputs"] + 1):
            graph = paper_graph() if case == 0 else paper_graph(
                *(rng.randrange(1, 128) for _ in range(4)))
            identity = canonical(graph[:2])
            if identity in paper_input_preimages:
                raise Refusal("SOURCE_INPUT_REUSED", case)
            paper_input_preimages.add(identity)
            for index, order in enumerate(orderings(graph)):
                positive(f"paper-{case}-order-{index}", graph, order)
        summary["distinct_paper_input_valuations"] = len(paper_input_preimages)
        for family in config["large_families"]:
            graph = large_graph(family["nodes"], rng)
            for index in range(family["schedules"]):
                positive(f"large-{len(graph)}-{index}", graph, random_order(graph, rng))
            if gpu:
                additive = large_graph(family["nodes"], rng, additive=True)
                for index in range(config["gpu_schedules_per_family"]):
                    placements = [rng.choice(("cpu", "gpu")) for _ in additive]
                    positive(f"mixed-{len(additive)}-{index}", additive,
                             random_order(additive, rng), placements)
        save(concurrent_pair(worker, rng.getrandbits(63)))
        summary["physical_completion_reversal"] = "OBSERVED_CPU_PROCESSES"

        def external_control(kind, syscall, reason):
            rec = dict(kind="negative", name=kind)
            path = args.out / (kind + ".strace")
            try:
                execute(mutants[kind], paper_graph(), [0, 1, 2, 3], 7,
                        [0] * 4, rec, check_values=False, trace=path)
                observed = path.read_text()
                if syscall + "(" not in observed:
                    raise Refusal("CONTROL_SYSCALL_NOT_OBSERVED", kind)
                raise Refusal(reason, dict(trace=path.name, sha256=digest(path),
                                           observed_values=rec["values"]))
            finally:
                save(rec)
        control("hidden_clock", lambda: external_control(
            "clock", "clock_gettime", "CAUSAL_COMPLETENESS_CLOCK"),
            "CAUSAL_COMPLETENESS_CLOCK")
        control("unseeded_randomness", lambda: external_control(
            "random", "getrandom", "DETERMINISM_RANDOM"), "DETERMINISM_RANDOM")

        def state_control():
            records = []
            for order in ([0, 1, 2, 3], [1, 0, 2, 3]):
                rec = dict(kind="negative", name="state")
                execute(mutants["state"], paper_graph(), order, 9, [0] * 4,
                        rec, check_values=False)
                records.append(rec)
                save(rec)
            if records[0]["values"] == records[1]["values"]:
                raise Refusal("CONTROL_STATE_NOT_OBSERVED", records)
            raise Refusal("CAUSAL_COMPLETENESS_STATE",
                          [r["values"] for r in records])
        control("undeclared_mutable_state", state_control, "CAUSAL_COMPLETENESS_STATE")

        def effects_control():
            effects_graph = [node(4, x=65), node(4, x=66)]
            traces = []
            for order in ([0, 1], [1, 0]):
                rec = dict(kind="negative", name="declared_effects")
                execute(worker, effects_graph, order, 11, [0, 0], rec, effects=True)
                traces.append(rec["workers"]["cpu"]["stderr_hex"])
                save(rec)
            if traces[0] == traces[1]:
                raise Refusal("CONTROL_EFFECT_DIFFERENCE_NOT_OBSERVED", traces)
            raise Refusal("DIAMOND_NONCOMMUTATION", traces)
        control("noncommuting_declared_effects", effects_control, "DIAMOND_NONCOMMUTATION")

        projection_source = dict(kind="negative", name="projection-control-source")
        execute(worker, paper_graph(), [0, 1, 2, 3], 91, [0] * 4, projection_source)
        projection_source["control_admission"] = "VALID_BASELINE_FOR_TAMPER_CONTROL"
        save(projection_source)
        actual_event = projection_source["events"][2]
        sample_request = actual_event["request"]
        sample_response = actual_event["response"]
        for name, field in (("forged_input_provenance", 7), ("forged_port_binding", 2)):
            changed = list(sample_response)
            changed[field] += 1
            tamper = dict(kind="negative", name=name,
                          program_preimage=projection_source["program_preimage"],
                          original_worker_observation=actual_event,
                          tampered_response=changed,
                          execution_verdict="PASS_BEFORE_RECEIPT_TAMPERING")
            def projection_control():
                try:
                    verify_response(sample_request, changed, sample_response[8])
                finally:
                    save(tamper)
            control(name, projection_control, "PROJECTION_SOUNDNESS")

        def hardcode_control():
            rec = dict(kind="negative", name="hardcoded_result")
            try:
                execute(mutants["hardcode"], paper_graph(9, 11, 2, 7),
                        [0, 1, 2, 3], 13, [0] * 4, rec)
            finally:
                save(rec)
        control("hardcoded_result", hardcode_control, "VALUE_MISMATCH")

        def bad_order():
            rec = dict(kind="negative", name="dependency_violation")
            try:
                execute(worker, paper_graph(), [2, 0, 1, 3], 17, [0] * 4, rec)
            finally:
                save(rec)
        control("dependency_violation", bad_order, "SCHEDULE_DEPENDENCY")
        if gpu:
            def stale_gpu_input():
                rec = dict(kind="negative", name="gpu_cached_mutable_input")
                graph = [node(1, x=2144, y=12692), node(1, x=18004, y=3522)]
                try:
                    execute(worker, graph, [0, 1], 97, [0, 0], rec,
                            gpu=mutants["gpu-cache"], placements=["gpu", "gpu"])
                finally:
                    save(rec)
            control("gpu_cached_mutable_input", stale_gpu_input, "VALUE_MISMATCH")
        summary["verdict"] = "PASS_BOUNDED_CONFORMANCE"
    except BaseException as exc:
        summary.update(verdict="FAIL", reason=getattr(exc, "reason", type(exc).__name__),
                       error=str(exc), traceback=traceback.format_exc())
    finally:
        tracefile.close()
        summary["runs_sha256"] = digest(args.out / "runs.jsonl")
        (args.out / "summary.json").write_bytes(canonical(summary) + b"\n")
    print(json.dumps(summary, sort_keys=True))
    return 0 if summary["verdict"] == "PASS_BOUNDED_CONFORMANCE" else 1


if __name__ == "__main__":
    raise SystemExit(main())
