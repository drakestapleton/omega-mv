#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Drake Stapleton (AIEN / aien-dev)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# TEST HARNESS: PATH-1 boundary check (spec 8.2 and 17.2).
# A path is evidence, never authority: the PATH module must not reference
# runtime or capability symbols, offer any execute, dispatch, promote or
# authorize entry point, or use heap, threads, sockets or host I/O syscalls.
# Comments are stripped before matching.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
bad=0
for f in "$root/src/path/rx_path.om" "$root/src/path/rx_path_core.om"; do
    code=$(sed -E '/^[[:space:]]*note([[:space:]].*)?$/d' "$f")
    if printf '%s\n' "$code" | grep -nE 'aienos_cap_|RX_ERR_CAP|rx_world_|rx_argus_|rx_cortex_|rx_jspace_' ; then
        echo "BOUNDARY $f: references capability or runtime symbols" >&2; bad=1
    fi
    if printf '%s\n' "$code" | grep -nE 'rx_path_[a-z_]*(exec|run|dispatch|authori|grant|promot|permit|effect)' ; then
        echo "BOUNDARY $f: declares an authority-bearing entry point" >&2; bad=1
    fi
    if printf '%s\n' "$code" | grep -nE '\b(fopen|fclose|read|write|stat|renames|socknew|bind|listen|accept|send|recv|connect|execve|fork|mmap|malloc|calloc|realloc|free|pthread_[a-z_]*)\b' ; then
        echo "BOUNDARY $f: uses heap, threads or system calls" >&2; bad=1
    fi
done
if [ "$bad" -ne 0 ]; then exit 1; fi
echo "PATH boundary: PASS (no runtime links, no authority entry points, no heap or threads)"
