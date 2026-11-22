<!-- SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception -->
# ERC1: coded E4M3 weight matrix, byte format

One file holds one matrix of `rows x cols` bytes (any byte values; E4M3 weights are the target).
All integers are unsigned and little-endian. `R` is `rows`. There is no padding and no alignment.

| Offset | Width | Field | Value |
|---|---|---|---|
| 0 | 4 | magic | bytes `45 52 43 31` (`ERC1`) |
| 4 | 2 | version | 1 |
| 6 | 2 | flags | 0 |
| 8 | 4 | rows | 1 .. 2^32 - 1 |
| 12 | 4 | cols | 1 .. 2^32 - 1 |
| 16 | 4 | prob_bits | 14 |
| 20 | 4 | matrix_crc32 | CRC-32 of the original `rows * cols` bytes, row-major |
| 24 | 8 | total_len | length of this file in bytes |
| 32 | 512 | freq | 256 x u16: frequency of byte value 0 .. 255; the sum is 2^14 |
| 544 | 4 (R + 1) | offset | R + 1 x u32: start of row r's stream, counted from the first stream byte; `offset[R]` is the length of the stream area |
| 548 + 4 R | 2 R | row_crc16 | R x u16: CRC-16 of row r's stream bytes |
| 548 + 6 R | 4 | header_crc32 | CRC-32 of bytes 0 .. 548 + 6 R - 1 (everything above) |
| 552 + 6 R | offset[R] | streams | row 0's stream, row 1's stream, ... |

Header size is `552 + 6 R` bytes; the file is that plus `offset[R]` bytes.

## One row stream

Static rANS over the model in `freq`, 14-bit probabilities, state in `[2^23, 2^31)`, byte-wise renormalisation.
Slot table: symbol `s` owns slots `cum[s] .. cum[s] + freq[s] - 1`, where `cum[s]` is the sum of `freq` below `s`.

* The stream is a u32 (little-endian) initial state `x`, then renormalisation bytes in the order the decoder reads them.
* Decode `cols` symbols: `k = x & 16383`, `s` = the symbol that owns slot `k`, output `s`,
  `x = freq[s] * (x >> 14) + (k - cum[s])`, then while `x < 2^23` read the next byte `b` and set `x = (x << 8) | b`.
* The encoder runs the same model backwards from `x = 2^23` and writes the final state first.
* The frequencies come from the matrix: `f = floor(count * 2^14 / n)`, raised to 1 when the symbol is present and `f` is 0,
  then 1 added to or taken from the first largest symbol until the sum is 2^14. This is the rule of the measurement prototype
  `evidence/FLASH-NEXT-WEIGHT-WASTE-20261118/rowrans.c`, so the stream bytes equal the prototype's. A decoder does not need the rule; it reads `freq`.

Rows are independent: a row is decoded from its own stream, the table and `cols`. No state passes between rows.

## What the decoder checks, in this order

Each refusal prints `erc: refused NAME` (and ` row N` for a row) on stderr and exits 3.

| Name | Check |
|---|---|
| TRUNC | fewer than 32 bytes, or fewer bytes than the header size |
| MAGIC | bytes 0 .. 3 are not `ERC1` |
| VERSION | version is not 1 or flags is not 0 |
| FIELD | prob_bits is not 14, or rows or cols is 0 |
| LENGTH | total_len differs from the file length |
| HDRCRC | header_crc32 differs from the CRC-32 of the header, frequency table, offsets and row CRCs |
| FREQ | the 256 frequencies do not sum to 2^14 |
| OFFSET | `offset[0]` is not 0, a stream is shorter than 4 bytes, an offset decreases, or `offset[R]` is not the stream area length |
| ROWCRC | the CRC-16 of the row's stream bytes differs from `row_crc16[r]` (checked before the row is decoded) |
| STATE | the initial state is below 2^23 or at least 2^31 |
| EXHAUST | the decoder needs a byte past the end of the row's stream |
| LEFTOVER | the row is decoded and bytes of its stream are unread |
| FINAL | the row is decoded, every byte is read, and the state is not 2^23 (the encoder's start state) |
| MATCRC | after every row is decoded, the CRC-32 of the output differs from matrix_crc32 (only whole-matrix decode) |

The checks from TRUNC to OFFSET run once when the file is opened (an `info`, `decode`, `decode-row` or `bench` call).
Decoding one row alone checks the header, the table, the offsets and that row; it cannot check matrix_crc32.
The STATE, EXHAUST, LEFTOVER and FINAL checks cost no bytes: a valid stream ends exactly at state 2^23 with no byte left.
They alone let some single-bit stream flips through (the flip scan receipt counts them on real expert rows), which is why each row has a CRC-16.
CRC-16 detects every single-bit flip in a stream of any length, and every burst of 16 bits or fewer.

## Checksums

* CRC-32: IEEE 802.3, reflected, polynomial `0xEDB88320`, initial value `0xFFFFFFFF`, final xor `0xFFFFFFFF`. `123456789` gives `0xCBF43926`; `matrix_crc32` equals the trailer CRC-32 of `gzip` on the raw matrix.
* CRC-16: CRC-16/CCITT-FALSE, polynomial `0x1021`, initial value `0xFFFF`, most significant bit first, no final xor. `123456789` gives `0x29B1`.

## Size

`file bytes = 552 + 6 R + sum of stream bytes`. The measurement prototype counts `512 + 4 R + sum of stream bytes` and no header,
row CRCs or matrix CRC, so an ERC1 file is larger than the prototype's count by `40 + 2 R` bytes for the same matrix
(32 header, 4 for the extra offset, 4 header CRC, `2 R` row CRCs; the 512 frequency bytes and the streams are identical).

## Limits

The width of a field is the limit: rows and cols are u32, the stream area is at most 2^32 - 1 bytes (the encoder refuses a larger one,
message `the stream area is longer than a u32 offset can address`). The program itself sizes its buffers from the input.
