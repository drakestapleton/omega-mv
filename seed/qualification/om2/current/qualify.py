#!/usr/bin/env python3
"""External ABI/SHA qualification instrument; never part of Omega's runtime."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


class Failure(Exception):
    pass


class NotRun(Failure):
    pass


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1048576), b''):
            h.update(block)
    return h.hexdigest()


def admit(root: Path) -> str:
    # The expected identity comes from the repository's seed receipt, never from the candidate being
    # qualified. Nothing is created, read from the bridge or compiled before this returns.
    pinfile = root / 'seed/out/omc.sha256'
    try:
        record = pinfile.read_text()
    except OSError as e:
        raise NotRun(f'no compiler pin in seed/out/omc.sha256: {e}') from e
    match = re.fullmatch(r'([0-9a-f]{64})  seed/out/omc\n', record)
    if match is None:
        raise NotRun('no compiler pin in seed/out/omc.sha256')
    compiler = root / 'seed/out/omc'
    if not compiler.is_file() or not os.access(compiler, os.X_OK):
        raise NotRun('no executable compiler at seed/out/omc')
    if digest(compiler) != match[1]:
        raise NotRun(f'omc is not the pinned compiler {match[1]}')
    return match[1]


class Qualification:
    def __init__(self, root: Path, bridge: Path, out: Path):
        self.root, self.bridge, self.out = root, bridge, out
        self.report = {'schema': 1, 'scope': 'ABI/SHA external callers only',
                       'verdict': 'NOT_RUN', 'commands': [], 'inputs': [],
                       'cases': {}, 'controls': {},
                       'limits': ['Not the full RM7 gate or Omega 1.0 qualification.',
                                  'Leakage, all-language ABI-v2 traps and physical x86 are separate.']}
        self.originals: list[tuple[Path, str]] = []
        self.tools: dict[str, str] = {}
        self.save()

    def save(self):
        temporary = self.out / 'result.json.tmp'
        temporary.write_text(json.dumps(self.report, indent=2) + '\n')
        temporary.replace(self.out / 'result.json')

    def run(self, tag, args, stdin=None, expected=0, extra_env=None, timeout=900):
        stdout, stderr = self.out / (tag + '.stdout'), self.out / (tag + '.stderr')
        command = [str(a) for a in args]
        env = os.environ.copy()
        # Unit generation must not inherit a caller's alternate unit list or destination.
        for name in ('OMEGA_UNITS', 'OMEGA_UNITS_DEST', 'OMEGA_OMC', 'OMEGA_BRIDGE'):
            env.pop(name, None)
        env.update(extra_env or {})
        record = {'tag': tag, 'argv': command, 'cwd': str(self.root),
                  'stdin': str(stdin) if stdin else None,
                  'environment_overrides': extra_env or {},
                  'expected_exit': expected, 'exit': None}
        self.report['commands'].append(record)
        self.save()
        with (Path(stdin).open('rb') if stdin else open(os.devnull, 'rb')) as inp, \
                stdout.open('wb') as out, stderr.open('wb') as err:
            try:
                p = subprocess.run(command, cwd=self.root, env=env, stdin=inp,
                                   stdout=out, stderr=err, timeout=timeout)
                record['exit'] = p.returncode
            except (OSError, subprocess.TimeoutExpired) as e:
                record['error'] = str(e)
                self.save()
                raise NotRun(f'{tag}: {e}') from e
        record.update(stdout=str(stdout), stdout_sha256=digest(stdout),
                      stderr=str(stderr), stderr_sha256=digest(stderr))
        self.save()
        if p.returncode != expected:
            raise Failure(f'{tag}: exit {p.returncode}, expected {expected}; see {stderr}')
        return stdout

    def require(self, condition, message):
        if not condition:
            raise Failure(message)

    def snapshot(self, path: Path, relative: str) -> Path:
        if not path.is_file():
            raise NotRun(f'missing input: {path}')
        target = self.out / 'inputs' / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        sha = digest(target)
        self.originals.append((path, sha))
        self.report['inputs'].append({'path': str(path), 'snapshot': str(target), 'sha256': sha})
        self.save()
        return target

    def compile(self, tag: str, source: Path) -> Path:
        target = self.run(tag, [self.omc], stdin=source)
        target.chmod(0o700)
        return target

    def frame(self, name: str, source: Path) -> bytes:
        code = self.compile('compile-' + name, source).read_bytes()
        self.require(len(code) < 100000000, 'artifact exceeds the native framing 8-digit length field')
        src = source.read_bytes()
        first = next((line.strip() for line in src.decode().splitlines()
                      if line.strip() and not re.match(r'^\s*note(?:\s|$)', line)), '')
        self.require(first == 'om2' or name == 'abi1', f'unsupported fixture profile: {name}')
        metadata = b'' if name == 'abi1' else f'omega-unit {name} {self.pin}\n'.encode()
        return src + b'\0' + f'{len(code):08d}'.encode() + code + metadata

    def generated(self, tag, mode, frame, target):
        got = self.run(tag, [self.native, mode], stdin=frame)
        shutil.copyfile(got, target)
        return target

    def record_case(self, name, evidence):
        self.require(name not in self.report['cases'], f'duplicate case: {name}')
        self.report['cases'][name] = {'verdict': 'PASS', 'evidence': evidence}
        self.save()

    def caller_cases(self, source, output):
        expected = re.findall(r'check\("([^"\n]+)"', source.read_text())
        self.require(len(expected) == len(set(expected)), f'duplicate oracle case in {source}')
        observed = re.findall(r'^(PASS|FAIL) ((?:abi|sha)-\S+) ', output.read_text(), re.M)
        self.require(len(observed) == len(expected), f'incomplete or duplicated caller output: {output}')
        self.require({name for _, name in observed} == set(expected), f'caller case set differs: {output}')
        for status, name in observed:
            self.require(status == 'PASS', f'{name} failed in {output}')
            self.record_case(name, output.name)

    def control(self, name, evidence):
        self.report['controls'][name] = {'verdict': 'PASS', 'evidence': evidence}
        self.save()

    def execute(self):
        # main() admitted the compiler before the evidence directory existed; it is admitted again here so that
        # a compiler or record replaced in between is refused before any input is compiled.
        self.pin = admit(self.root)
        if not self.bridge.is_dir():
            raise NotRun(f"missing bridge checkout: {self.bridge}")
        for tool in ('git', 'cc', 'nm', 'sh'):
            found = shutil.which(tool)
            if not found:
                raise NotRun(f'missing qualification tool: {tool}')
            self.tools[tool] = found
        self.report['platform'] = {'uname': list(os.uname()), 'python': sys.version,
                                   'python_executable': sys.executable}
        if os.uname().sysname != 'Linux' or os.uname().machine not in ('aarch64', 'arm64'):
            raise NotRun('this native caller instrument requires Linux AArch64')
        self.run('source-clean', [self.tools['git'], 'diff', '--quiet', 'HEAD', '--'])
        self.run('bridge-clean', [self.tools['git'], '-C', self.bridge, 'diff', '--quiet', 'HEAD', '--'])
        source_head = self.run('source-head', [self.tools['git'], 'rev-parse', 'HEAD']).read_text().strip()
        bridge_head = self.run('bridge-head', [self.tools['git'], '-C', self.bridge, 'rev-parse', 'HEAD']).read_text().strip()
        lock_lines = [line.strip() for line in (self.root/'om/omega-bridge.lock').read_text().splitlines()
                      if line.strip() and not line.startswith('#')]
        self.require(len(lock_lines) == 1 and re.fullmatch(r'[0-9a-f]{40}', lock_lines[0]) is not None,
                     'invalid om/omega-bridge.lock')
        if bridge_head != lock_lines[0]:
            raise NotRun(f'bridge checkout {bridge_head} does not match lock {lock_lines[0]}')
        self.report.update(source_head=source_head, bridge_head=bridge_head)
        self.run('cc-version', [self.tools['cc'], '--version'])
        self.run('nm-version', [self.tools['nm'], '--version'])
        relative = [
            'seed/out/omc', 'seed/out/omc.sha256', 'om/units.sh', 'om/omega-bridge.lock',
            'seed/qualification/om2/current/qualify.py',
            'seed/qualification/om2/sec/s5s7/candidate.cases',
            'seed/qualification/om2/oracle/s5s7/abi/driver.c',
            'seed/qualification/om2/oracle/s5s7/abi/v1link.c',
            'seed/qualification/om2/oracle/s5s7/sha/sha_driver.c',
            'seed/qualification/om2/oracle/s5s7/sha/expected.h',
        ]
        relative += [f'seed/qualification/om2/sec/s5s7/abi/{n}.om' for n in ('abiv','abiw','abi1')]
        # Snapshot the source closure consumed by the existing unit generator, including its defaults.
        omfiles = self.run('om-files', [self.tools['git'], 'ls-files', '-z', 'om']).read_bytes().split(b'\0')
        relative += [os.fsdecode(name) for name in omfiles if name]
        relative += ['src/' + name for name in ('omega_om_units.c','omega_om_units_fs.c',
                     'omega_native.h','omega_api_decl.h','omega_om_units.ident')]
        self.inputs = {name: self.snapshot(self.root/name, 'omega/'+name) for name in sorted(set(relative))}
        native_source = self.snapshot(self.bridge/'src/native.om', 'bridge/src/native.om')
        self.omc = self.inputs['seed/out/omc']
        self.omc.chmod(0o700)
        # admit() accepted exactly one line "<pin>  seed/out/omc"; the snapshot must hold that same record.
        if digest(self.omc) != self.pin or self.inputs['seed/out/omc.sha256'].read_text() != f'{self.pin}  seed/out/omc\n':
            raise NotRun('compiler or seed/out/omc.sha256 changed during snapshot')
        self.report['compiler_sha256'] = self.pin
        self.native = self.compile('native-build', native_source)
        self.abi_and_sha()
        self.unit_identity_controls()
        declarations = re.findall(r'^((?:abi|sha)-\S+) notrun ',
                                  self.inputs['seed/qualification/om2/sec/s5s7/candidate.cases'].read_text(), re.M)
        self.require(len(declarations) == len(set(declarations)), 'duplicate external case declaration')
        self.require(set(declarations) == set(self.report['cases']),
                     'external declaration inventory differs from exercised cases')
        for path, sha in self.originals:
            self.require(digest(path) == sha, f'input changed during qualification: {path}')
        self.run('source-clean-final', [self.tools['git'], 'diff', '--quiet', 'HEAD', '--'])
        final_head = self.run('source-head-final', [self.tools['git'], 'rev-parse', 'HEAD']).read_text().strip()
        self.require(final_head == source_head, 'source HEAD changed during qualification')
        self.report['artifacts'] = [
            {'path': str(p.relative_to(self.out)), 'sha256': digest(p)}
            for p in sorted(self.out.rglob('*'))
            if p.is_file() and p.name not in ('result.json', 'result.json.tmp')
        ]
        self.report['verdict'] = 'PASS'
        self.save()
        print(f'ABI_SHA_GATE PASS cases={len(self.report["cases"])} controls={len(self.report["controls"])} '
              f'source={source_head} compiler={self.pin} result={self.out / "result.json"}')

    def abi_and_sha(self):
        src = 'seed/qualification/om2/'
        abi = {n:self.inputs[src+f'sec/s5s7/abi/{n}.om'] for n in ('abiv','abiw','abi1')}
        frame = self.out/'abi.in'
        frame.write_bytes(b''.join(self.frame(n, p) for n,p in abi.items()))
        c = self.generated('abi-c', 'c', frame, self.out/'abi.c')
        lib = self.out/'libabi.so'
        self.run('abi-library', [self.tools['cc'],'-std=gnu11','-O2','-Wall','-Wextra','-Werror',
                                '-fPIC','-shared',c,'-o',lib])
        driver = self.inputs[src+'oracle/s5s7/abi/driver.c']
        exe = self.out/'abi-driver'
        self.run('abi-driver-build',[self.tools['cc'],'-std=gnu11','-O2','-Wall','-Wextra','-Werror',driver,
                                    '-L'+str(self.out),'-labi','-Wl,-rpath,'+str(self.out),'-o',exe])
        sha_v, sha_w = digest(abi['abiv']), digest(abi['abiw'])
        output = self.run('abi-driver',[exe,sha_v,sha_w,self.pin])
        self.caller_cases(driver, output)
        symbols = self.run('abi-symbols',[self.tools['nm'],'-D','--defined-only',lib])
        names = {line.split()[-1] for line in symbols.read_text().splitlines() if line.split()}
        self.require('omega2_vsum' in names and 'omega_vsum' not in names, 'ABI v2/v1 symbol boundary failed')
        self.run('abi-v1-link',[self.tools['cc'],self.inputs[src+'oracle/s5s7/abi/v1link.c'],
                              '-L'+str(self.out),'-labi','-o',self.out/'v1-link'],expected=1)
        error = (self.out/'abi-v1-link.stderr').read_text()
        self.require('undefined reference' in error and 'omega_vsum' in error, 'link control failed for another reason')
        self.record_case('abi-v1-absent','abi-v1-link.stderr; abi-symbols.stdout')
        self.require('omega_madd1' in names and 'omega2_ident_abi1' not in names, 'OM-1 symbol boundary failed')
        self.record_case('abi-v1-kept','abi-symbols.stdout')
        program = ('import ctypes,sys; l=ctypes.CDLL(sys.argv[1]); f=l.omega2_vcnt; '
                   'f.argtypes=[ctypes.POINTER(ctypes.c_uint64),ctypes.c_void_p,ctypes.c_uint64]; '
                   'f.restype=ctypes.c_uint32; r=ctypes.c_uint64(123); '
                   's=f(ctypes.byref(r),ctypes.c_void_p(1),0); print(s,r.value); '
                   'sys.exit(0 if s==0 and r.value==0 else 1)')
        empty = self.run('abi-empty-misaligned',[sys.executable,'-c',program,lib])
        self.require(empty.read_bytes() == b'0 0\n', 'empty misaligned view did not return status/result zero')
        self.record_case('abi-misaligned-len0',empty.name)
        wrong = self.run('control-wrong-compiler-identity',[exe,sha_v,sha_w,'0'*64],expected=1)
        self.require('FAIL abi-ident-abiv ' in wrong.read_text() and 'FAIL abi-ident-abiw ' in wrong.read_text(),
                     'wrong-identity control did not reach both identity assertions')
        self.control('wrong-compiler-identity',wrong.name)
        wrong = self.run('control-wrong-source-identity',[exe,'0'*64,sha_w,self.pin],expected=1)
        self.require('FAIL abi-ident-abiv ' in wrong.read_text(), 'wrong-source control did not reach identity assertion')
        self.control('wrong-source-identity',wrong.name)
        frame = self.out/'sha.in'
        frame.write_bytes(self.frame('sha256',self.inputs['om/sha256/sha256-om2.om']))
        c = self.generated('sha-c','c',frame,self.out/'sha.c')
        api = self.generated('sha-api','apic',frame,self.out/'sha-api.c')
        self.generated('sha-native-header','h',frame,self.out/'omega_native.h')
        self.generated('sha-api-header','apih',frame,self.out/'omega_api_decl.h')
        driver = self.inputs[src+'oracle/s5s7/sha/sha_driver.c']
        exe = self.out/'sha-driver'
        cc = [self.tools['cc'],'-std=gnu11','-O2','-Wall','-Wextra','-Werror',
              '-DGENHDR="omega_api_decl.h"','-I'+str(self.out)]
        self.run('sha-driver-build',cc+[driver,c,api,'-o',exe])
        output = self.run('sha-driver',[exe,'big'])
        self.caller_cases(driver,output)
        # A wrong independent digest must be rejected by the same caller and generated library.
        bad = self.out/'wrong-sha-oracle'
        bad.mkdir()
        shutil.copyfile(driver,bad/'sha_driver.c')
        expected = self.inputs[src+'oracle/s5s7/sha/expected.h'].read_text()
        match = re.search(r'(#define EXP_EMPTY\s+")([0-9a-f])',expected)
        self.require(match is not None,'cannot locate the independent empty SHA digest')
        pos = match.start(2)
        (bad/'expected.h').write_text(expected[:pos]+('1' if expected[pos]=='0' else '0')+expected[pos+1:])
        self.run('control-sha-build',cc+[bad/'sha_driver.c',c,api,'-o',bad/'driver'])
        wrong = self.run('control-sha-digest',[bad/'driver'],expected=1)
        self.require('FAIL sha-empty ' in wrong.read_text(),'wrong SHA oracle did not fail its digest assertion')
        self.control('wrong-sha-digest',wrong.name)

    def unit_identity_controls(self):
        stage = self.out/'units-check'
        for relative, source in self.inputs.items():
            if relative.startswith(('om/','src/')) or relative == 'seed/out/omc.sha256':
                target = stage/relative
                target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copyfile(source,target)
        # om/units.sh derives its generator pin from om/omega-bridge.lock with git, so it needs the
        # verified git checkout (clean, at the lock: execute() checked both), not the plain snapshot.
        # The snapshot still fixes the bytes: the checkout's native.om must equal it.
        bridge = self.bridge
        self.require(digest(bridge/'src/native.om') == digest(self.out/'inputs/bridge/src/native.om'),
                     'bridge native.om changed since its snapshot')
        env = {'OMEGA_OMC':str(self.omc),'OMEGA_BRIDGE':str(bridge)}
        # Test the unchanged checker on candidate-generated bindings in a private tree.
        # Its expected compiler identity comes from the same snapshotted seed receipt;
        # no script/pin projection or canonical generated-output change is needed.
        script = stage/'om/units.sh'
        original = self.inputs['om/units.sh']
        self.require(digest(script) == digest(original), 'unit checker copy changed')
        self.require((stage/'seed/out/omc.sha256').read_text() ==
                     self.inputs['seed/out/omc.sha256'].read_text(), 'unit checker pin copy changed')
        self.report['unit_checker_projection'] = {
            'original_compiler_pin': self.pin, 'candidate_compiler_pin': self.pin,
            'original_script_sha256': digest(original),
            'projected_script_sha256': digest(script),
            'pin_source': 'seed/out/omc.sha256 (snapshotted unchanged)',
            'change': 'None: the checker and repository compiler pin are copied unchanged.',
            'canonical_binding_check': 'NOT_RUN: this check uses freshly generated candidate bindings.'
        }
        self.save()
        self.run('units-generate-candidate',[self.tools['sh'],script],extra_env=env)
        command = [self.tools['sh'],script,'--check']
        self.run('units-baseline',command,extra_env=env)
        source = stage/'om/sha256/sha256-om2.om'
        before = source.read_bytes()
        source.write_bytes(before+b'\nnote Qualification control: source identity changed.\n')
        output = self.run('units-stale-source',command,expected=1,extra_env=env)
        self.require('differs from the pinned tools' in output.read_text(),'stale-source refusal missing')
        self.record_case('abi-units-stale-source',output.name)
        source.write_bytes(before)
        output = self.run('units-stale-omc',command,expected=3,
                          extra_env=dict(env,OMEGA_OMC=str(self.native)))
        self.require('omc is not the pinned compiler' in output.read_text(),'stale-compiler refusal missing')
        self.record_case('abi-units-stale-omc',output.name)
        ident = stage/'src/omega_om_units.ident'
        before = ident.read_text()
        self.require('profile=OM-2' in before,'missing profile control target')
        ident.write_text(before.replace('profile=OM-2','profile=OM-1',1))
        output = self.run('units-stale-profile',command,expected=1,extra_env=env)
        self.require('omega_om_units.ident differs' in output.read_text(),'stale-profile refusal missing')
        self.record_case('abi-units-stale-profile',output.name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bridge',type=Path,required=True,help='clean checkout at om/omega-bridge.lock')
    parser.add_argument('--output',type=Path,required=True,help='new evidence directory, never overwritten')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[4]
    output = args.output.resolve()
    try:
        admit(root)
    except NotRun as e:
        print(f'ABI_SHA_GATE NOT_RUN: {e}; nothing was created',file=sys.stderr)
        return 3
    try:
        output.mkdir(mode=0o700,parents=True,exist_ok=False)
    except OSError as e:
        print(f'ABI_SHA_GATE NOT_RUN: evidence directory must be new: {e}',file=sys.stderr)
        return 3
    q = Qualification(root,args.bridge.resolve(),output)
    try:
        q.execute()
        return 0
    except (Failure,KeyboardInterrupt) as e:
        not_run = isinstance(e,(NotRun,KeyboardInterrupt))
        q.report['verdict'] = 'NOT_RUN' if not_run else 'FAIL'
        q.report['error'] = str(e) or 'interrupted'
        q.save()
        print(f'ABI_SHA_GATE {q.report["verdict"]}: {q.report["error"]}; result={output / "result.json"}',file=sys.stderr)
        return 3 if not_run else 1
    except Exception as e:
        q.report.update(verdict='FAIL',error=f'{type(e).__name__}: {e}')
        q.save()
        print(f'ABI_SHA_GATE FAIL: {q.report["error"]}; result={output / "result.json"}',file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
