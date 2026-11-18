# Four recorded operator-control cases

This fixture reproduces the four synthetic Omega repair objectives used by the native operator-view and release scenarios. The records cover a wrong loop count, a missing file, a wrong calculation and a passing program.

The records were reconstructed from the retained native qualification run at omega-mv revision `2ee9da3574747b8f3dbbca2f5910def0a24d6aa2`, using its prepared `rel/full/expect.json` and `objs.txt`. The first read response provides each initial source file. The missing-file objective has no initial file. A present file uses the label `present` because the preparation code distinguishes only missing and present files. The reconstructed file is a four-case projection. The full 108-run replay and the digest-pinned live-test still require the original selection.

From the repository root, build the seeded drivers as described in [the node guide](../../README.md). With a fresh output directory, reproduce the projection and check its three products against the historical run:

```sh
cases="$PWD/seed/node/tests/recorded-control"
out=$(mktemp -d)
build/node/view-prep "$cases" "$out/prepared" 76666,83423,82342,85188 &&
(cd "$out/prepared" && sha256sum -c - <<'HASHES'
2c97e2a9e54651138f0df9196459e946d5ea05ed0bd9bc246960b3f0ca4f5f0d  expect.json
4f62b13ea6dcc92bd7c135747bbc34d9b6ad4f11e1cb58f6ac8930ee3e9c13b3  objs.txt
05386b30c5d1a027fa8f943233368ba62c690cd5877ae9bf82369c7b404a01b0  map
HASHES
)
```

Pass `"$cases"` as the ROUND40 argument of `view-accept` or `release-accept fake`. A fake server answers only the recorded prompts. A new prompt after restart remains unrecorded.
