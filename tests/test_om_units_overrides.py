#!/usr/bin/env python3
"""Host-only shell orchestration checks, not Omega compilation or ABI evidence.

Run with python3 tests/test_om_units_overrides.py. To exercise an old script,
set OM_UNITS_TEST_SCRIPT to a saved om/units.sh. Only the disposable copy's
compiler/generator pins are replaced with the hashes of explicit test doubles.
Production pins and generated files are never changed by this test.
"""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = Path(os.environ.get("OM_UNITS_TEST_SCRIPT", ROOT / "om/units.sh"))
OUTPUTS = (
    "omega_om_units.c", "omega_native.h", "omega_api_decl.h",
    "omega_om_units.ident", "omega_om_units_fs.c",
)
SHA = "om/sha256/sha256-om2.om"
B3 = "om/blake3/b3unit.om"
ENC = "om/encoder/bw_enc_sm121.om"
NATIVE_DOUBLE = b'''#!/usr/bin/env python3
import hashlib
import os
import sys
data = sys.stdin.buffer.read()
mode = sys.argv[1]
with open(os.environ["STUB_LOG"], "a") as log:
    log.write(mode + "\\n")
if not data:
    print("test double: zero units refused", file=sys.stderr)
    sys.exit(10)
if mode == os.environ.get("STUB_FAIL_MODE"):
    print("test double: generator failure", file=sys.stderr)
    sys.exit(77)
print(mode + ":" + hashlib.sha256(data).hexdigest())
'''


class UnitOverrides(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="omega-units-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.dest = self.root / "dest"
        self.dest.mkdir()
        self.bridge = self.root / "bridge"
        (self.bridge / "src").mkdir(parents=True)
        (self.bridge / "src/native.om").write_bytes(b"explicit generator test double\n")
        self.omc = self.root / "omc"
        self.omc.write_text(
            "#!/usr/bin/env python3\nimport os\nimport sys\n"
            "data = sys.stdin.buffer.read()\n"
            "mode = 'native' if data == b'explicit generator test double\\n' else 'unit'\n"
            "if mode == os.environ.get('STUB_COMPILE_FAIL'): sys.exit(76)\n"
            f"sys.stdout.buffer.write({NATIVE_DOUBLE!r} if data == "
            "b'explicit generator test double\\n' else b'unit-code')\n"
        )
        self.omc.chmod(0o755)
        script = SCRIPT.read_text()
        for key, path in (("OMC_PIN", self.omc),
                          ("NATIVE_PIN", self.bridge / "src/native.om")):
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            script, count = re.subn(rf"^{key}=[0-9a-f]{{64}}$", f"{key}={digest}",
                                    script, flags=re.MULTILINE)
            self.assertEqual(count, 1, f"expected one {key} pin")
        for unit in (SHA, B3, ENC):
            dest = self.root / unit
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes((ROOT / unit).read_bytes())
        self.script = self.root / "om/units.sh"
        self.script.write_text(script)
        self.log = self.root / "calls"
        self.env = os.environ.copy()
        for key in ("OMEGA_UNITS", "OMEGA_UNITS_DEST", "STUB_FAIL_MODE", "STUB_COMPILE_FAIL"):
            self.env.pop(key, None)
        self.env.update(OMEGA_OMC=str(self.omc), OMEGA_BRIDGE=str(self.bridge),
                        OMEGA_UNITS_DEST=str(self.dest), STUB_LOG=str(self.log))

    def run_units(self, units=None, check=False, expected=0, **extra):
        env = self.env.copy()
        if units is not None:
            env["OMEGA_UNITS"] = units
        env.update(extra)
        args = ["sh", str(self.script)] + (["--check"] if check else [])
        result = subprocess.run(args, cwd=self.root, env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def fs(self):
        return (self.dest / OUTPUTS[-1]).read_bytes()

    def test_default_and_check(self):
        self.run_units()
        self.assertEqual(set(p.name for p in self.dest.iterdir()), set(OUTPUTS))
        fs = self.fs()
        self.assertTrue(fs.startswith(b"freest:"))
        self.assertIn(b"\nfapic:", fs)
        self.run_units(check=True)
        self.run_units(SHA)
        self.assertEqual(self.fs(), fs, "default freestanding output must contain only SHA")

    def test_absolute_sha(self):
        self.run_units(SHA)
        expected = self.fs()
        self.run_units(str(self.root / SHA))
        self.assertEqual(self.fs(), expected)
        self.run_units(str(self.root / SHA), check=True)

    def test_relative_dot_sha(self):
        self.run_units(SHA)
        expected = self.fs()
        self.run_units("./om/sha256/../sha256/sha256-om2.om")
        self.assertEqual(self.fs(), expected)

    def test_symlink_alias(self):
        self.run_units(SHA)
        expected = self.fs()
        alias = self.root / "alias/sha256-om2.om"
        alias.parent.mkdir()
        alias.symlink_to(self.root / SHA)
        self.run_units(str(alias))
        self.assertEqual(self.fs(), expected)

    def test_hosted_only_replaces_stale_fs(self):
        self.run_units()
        self.log.write_text("")
        self.run_units(B3)
        self.assertEqual(self.fs(), b"/* No freestanding units selected by OMEGA_UNITS. */\n")
        self.assertEqual(self.log.read_text().splitlines(), ["c", "apic", "h", "apih"])
        self.run_units(B3, check=True)
        (self.dest / OUTPUTS[-1]).write_text("stale freestanding binding\n")
        self.run_units(B3, check=True, expected=1)

    def test_copied_sha_is_not_canonical_fs(self):
        copied = self.root / "copy/sha256-om2.om"
        copied.parent.mkdir()
        copied.write_bytes((self.root / SHA).read_bytes())
        self.run_units(str(copied))
        self.assertEqual(self.fs(), b"/* No freestanding units selected by OMEGA_UNITS. */\n")

    def test_encoder_mutant_shape(self):
        custom = self.root / "mutant/bw_enc_sm121.om"
        custom.parent.mkdir()
        custom.write_bytes((self.root / ENC).read_bytes() + b"note test mutation\n")
        self.run_units()
        expected = self.fs()
        self.run_units(f"{SHA} {B3} {custom}")
        self.assertEqual(self.fs(), expected)

    def test_generator_failures_propagate_without_copying(self):
        for mode in ("c", "apic", "h", "apih", "freest", "fapic"):
            with self.subTest(mode=mode):
                self.run_units()
                before = {p.name: p.read_bytes() for p in self.dest.iterdir()}
                self.run_units(SHA, expected=77, STUB_FAIL_MODE=mode)
                self.assertEqual({p.name: p.read_bytes() for p in self.dest.iterdir()}, before)

    def test_compiler_failures_propagate_without_copying(self):
        for mode in ("native", "unit"):
            with self.subTest(mode=mode):
                self.run_units()
                before = {p.name: p.read_bytes() for p in self.dest.iterdir()}
                self.run_units(SHA, expected=76, STUB_COMPILE_FAIL=mode)
                self.assertEqual({p.name: p.read_bytes() for p in self.dest.iterdir()}, before)

    def test_missing_sha_input_still_refuses(self):
        (self.root / SHA).unlink()
        self.run_units(SHA, expected=2)
        self.assertEqual(list(self.dest.iterdir()), [])

    def test_pin_checks_remain_enforced(self):
        self.omc.write_text(self.omc.read_text() + "# changed compiler\n")
        self.run_units(expected=3)
        self.assertFalse(self.log.exists())

    def test_generator_pin_check_remains_enforced(self):
        (self.bridge / "src/native.om").write_text("changed generator\n")
        self.run_units(expected=3)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
