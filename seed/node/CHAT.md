# Standalone own-model chat transport

Compose infer.om with existing seed/json/json.om, jsonw.om, net/http.om and notls.om using the pinned seeded OM-2 compiler. No scheduler import is required.

```
infer --chat PORT MAXTOK DEADLINE_S USER
infer --chat-system PORT MAXTOK DEADLINE_S USER SYSTEM
```

The second mode sends exactly two explicit messages, system then user. Each is nonempty and bounded to 3800 UTF-8 bytes. No default instruction, tools, synthetic response or model fallback is injected. Raw content and server-reported full prompt/completion usage remain in OMNI1. Legacy raw mode and single-user chat remain unchanged. Protected serving port 18091 is refused. JSON serialization capacity is separately bounded; a request that cannot fit is refused.

The explicit system option supports controlled format experiments, not the entire Hermes tool protocol: the successful historical Hermes prompt exceeds this limit and includes tool schemas this transport does not send. A passing transport test is not a successful model-generated program.

Targeted external wire test (loopback mock only):

```
python3 seed/node/check-chat-system.py /path/to/infer
```

The test checks exact role/order and escaped Unicode content, unchanged candidate and usage, no tool/test injection, length/arity and protected-port refusals. The previous single-user client fails this test at the explicit-system case.
