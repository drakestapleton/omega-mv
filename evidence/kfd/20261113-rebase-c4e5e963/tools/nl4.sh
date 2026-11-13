#!/bin/sh
# neuralese/README.md nl4 host gate, sources from sibling clones; refuse unless deps match nl4-dependencies.json
set -e
rm -rf build/nl4-deps build/nl4-host; mkdir -p build/nl4-deps
git -C ../aien-train show 0e01c58a41f1a2fb976efa75c1cc554503aa2ee4:native/neuralese/hadamard.om > build/nl4-deps/h.om
git -C ../aien-protocols-mv show 6fb728a14781eb4e5262ffbdc9c2e6be64974f36:specs/latent-payload/validator.om > build/nl4-deps/v.om
sha256sum build/nl4-deps/h.om build/nl4-deps/v.om
printf '%s  %s\n' da4a1b91fcd72b4f5fa3a70461932626acdbc62a9a8d0b9876433f4a44f6ed20 build/nl4-deps/h.om e85d174839f7d0c3406f783ec0fd69d52ce5576bdcca4892c16b21b09f14b003 build/nl4-deps/v.om | sha256sum -c
seed/out/omc < seed/qualification/om2/gate.om > build/nl4-gate
chmod +x build/nl4-gate
build/nl4-gate seed/out/omc "$(cut -d' ' -f1 seed/out/omc.sha256)" neuralese/nl4-host.cases build/nl4-host
