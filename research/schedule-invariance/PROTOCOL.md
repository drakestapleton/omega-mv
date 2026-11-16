# Schedule-invariance experiment, SI-2

Intent, from the operator: "I would like to run this" followed by the description
of the unrun schedule-invariance experiment in Zenodo 23547813.

Authority: the experiment in section 8 of *The Atemporal AIEN Postulate:
Causal Semantics Without Clocks*, version 1.1, DOI 10.5281/zenodo.23547813.
The downloaded record and paper are preserved with each campaign's evidence.
The older AT-0 and AT-1 experiments explicitly do not establish this result.

This protocol is frozen by its source commit before the campaign begins.
SI-2 adds a regression control for stale GPU input caches found by the failed
SI-1 campaign. The positive acceptance criteria are unchanged. SI-1 failures
remain under their original source revision and are not rescored.
Each campaign also writes its exact configuration before its first execution.
Failed campaigns are preserved. Changing acceptance criteria requires a new
protocol and campaign. These are public, development examples, not held-out data.

## Objects and observations

A graph lists immutable occurrence numbers, labeled operations, ordered left and
right operand roles, literal operands, and direct parent occurrences. Two equal
operations remain two occurrences. Arithmetic is exact unsigned modular arithmetic
modulo 65521, with add, multiply and ordered subtraction. The paper's example uses
values below the modulus and yields the paper's exact integer result. A separate
effect operation writes its declared byte to a shared ordered channel.

The semantic result is the complete occurrence-to-value mapping and the complete
declared channel trace. No tolerance or sorting of an ordered channel is permitted.
Semantic identity commits the full graph, ordered ports, labels, arithmetic policy,
external input valuation and observable policy. Placement, launch order, nonce and
delay are realization metadata. The nonce binds responses to the current request;
it does not change the graph's mathematical value.

The Omega worker receives fixed-width records containing occurrence, operation,
ordered source references, both actual operand values, requested physical delay
and run nonce. It echoes the request unchanged alongside its computed result.
The external experiment instrument retains the authoritative graph and schedule,
admits a node only after its parents have completed, and independently checks each
binding and value. Echoes alone are not evidence of correct computation.

The worker is a deliberately small experiment realizer, not an integration with
production FORGE or AEGIS. The Python instrument controls experiments and computes
an independent recursive oracle; it is not a production dependency. The experiment
does not establish universal noninterference of arbitrary programs or verify a
production admission system. Full source and executable digests bind the tested
programs. Hash equality is checked alongside actual graph/record equality.

## Positive arm

Run both schedules of the paper's graph, then vary its literal inputs. Enumerate
every topological ordering of every naturally labeled binary-input DAG through
four occurrences. Graphs needing more than two direct parents are outside this
corpus. Use noncommutative subtraction as well as addition and multiplication so
reversed input roles cannot hide behind commutative arithmetic.

For larger DAGs use reproducible randomized schedules and fresh source valuations.
The configuration records graph sizes, sample counts and RNG seeds before running.
For each input valuation, compare schedules against the same independently
computed oracle result. Exercise physical delays and both completion orders of
independent operations. Independent worker processes may overlap on CPU; a
synchronous GPU launch is reported as synchronous, never as overlapping dispatch.

If authorized, use the existing native NVIDIA context/vector/launch implementation
for actual addition, with randomized CPU/GPU placement. Multiplication and
subtraction stay on CPU. A GPU-labeled worker executes its additions on GPU and
never substitutes CPU on GPU failure. Receipts state each event's actual mechanism.
Any omitted GPU arm leaves the paper's full experiment incomplete.

## Acceptance and controls

Every completed positive event must match the oracle exactly, with unchanged
occurrence, operation, ordered parent references, external input and run binding.
All declared outputs and effects must be retained. Failed execution, incomplete
trace, malformed response, unexpected channel bytes or extra output fails the arm.
Receipts record actual monotonic start/end observations, requested delays,
placements, schedule and raw responses. Time observations need only be honest;
they need not differ by a predetermined amount and are not a performance claim.

Deliberately faulty compiled realizers exercise a hidden clock read, an unseeded
random draw, undeclared mutable counter state, and hardcoded arithmetic. Linux
system-call traces independently expose clock and randomness reads; changed
values expose their effects. Reversing independent counter events must expose
schedule dependence. Independent declared channel writes must produce opposite
ordered traces and be rejected specifically for noncommutation. Correct arithmetic
with falsified nonce or input-port provenance must be rejected for projection
soundness. Neither correct numeric output nor a graph digest rescues false binding.
Each negative control is recorded by its violated obligation. A missed control
fails the experiment; it is not normalized into a passing result.

The GPU arm additionally restores the unsafe cached-input allocation in a
deliberately faulty executable. Repeated additions with changed inputs must
expose its stale result and be refused as an implementation value mismatch.
The correct realizer uses GPU-uncached CPU-written inputs, as required by the
NVIDIA allocation contract (`nvos.h`, GPU_CACHEABLE comments). This is a repair
to physical realization, not a change to the graph's declared semantics.

## Interpretation

PASS means bounded conformance of these realizers on these graphs, valuations,
schedules and placements, with the named fault controls caught. It is not a
universal proof of the postulate, proof of the physical refinement obligation,
independence from physical time, or production FORGE/AEGIS qualification.
Any GPU arm not physically executed remains NOT_RUN. No Zenodo record or public
paper is changed by running the experiment.
