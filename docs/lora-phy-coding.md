# LoRa PHY coding stages

This document describes the implemented MATLAB hard-decision packet-coding
model. Its conventions follow the reverse-engineered Semtech-compatible PHY
chain and are kept visible as intermediate vectors for later Simulink and HDL
comparison.

## Implemented transmit and receive order

```text
TX
payload bytes
  -> calculate payload CRC over the original bytes when enabled
  -> whiten payload bytes only
  -> split bytes into low-nibble-first order
  -> prepend the five-nibble explicit header
  -> append four unwhitened CRC nibbles
  -> FEC encode each nibble
  -> diagonal interleave each block
  -> inverse-Gray label mapping and +1 CSS-bin offset
  -> CSS chirp modulation

RX
hard CSS symbol decisions
  -> remove CSS-bin offset and restore Gray labels
  -> diagonal deinterleave
  -> hard maximum-likelihood FEC decode
  -> parse and verify explicit header
  -> join and dewhiten payload bytes
  -> reconstruct and verify payload CRC
  -> accept or reject packet
```

The first block is a special case: it contains `SF-2` codewords, always uses
CR 4/8, and produces eight reduced-rate symbols. At SF7 the five explicit
header nibbles exactly fill that block. Subsequent blocks use the payload CR;
with low-data-rate optimization they also use `SF-2` codewords per block.

## Whitening

Whitening XORs each payload byte with a deterministic sequence. The implemented
8-bit LFSR uses polynomial `x^8 + x^6 + x^5 + x^4 + 1`, starts at `0xFF`, and
restarts for every packet. Its first bytes are:

```text
FF FE FC F8 F0 E1 C2 85 0B 17 2F 5E BC 78 F1 E3
```

The operation is self-inverse:

```text
whiten(whiten(payload)) == payload
```

Whitening adds no redundancy and corrects no errors. It breaks up repetitive
patterns before coding. The CRC nibbles are not whitened in this compatibility
chain.

## Forward error correction (FEC)

Each four-bit nibble becomes a systematic codeword of `4 + CR` bits:

| CR setting | Nominal rate | Codeword width | Use |
|---:|---:|---:|---|
| 1 | 4/5 | 5 | shortest airtime |
| 2 | 4/6 | 6 | additional parity |
| 3 | 4/7 | 7 | more protection |
| 4 | 4/8 | 8 | strongest supported hard code |

For CR 2 through 4, with MSB-first data bits `[d0 d1 d2 d3]`, parity bits are
selected from:

```text
p0 = d0 xor d1 xor d2
p1 = d1 xor d2 xor d3
p2 = d0 xor d1 xor d3
p3 = d0 xor d2 xor d3
```

CR 1 uses the single parity `d0 xor d1 xor d2 xor d3`. The MATLAB decoder
compares a received hard codeword with all 16 valid codewords and chooses the
minimum Hamming-distance candidate. This makes tie behavior explicit and gives
the distance needed for diagnostics. Soft-decision decoding is not implemented
yet.

## Diagonal interleaving

Interleaving permutes coded bits without adding or removing information. For a
codeword-bit row `i` and an output-symbol bit `j`, the implemented permutation
selects codeword row:

```text
source = mod(i - j - 1, effectiveSF)
```

where `effectiveSF` is `SF` normally and `SF-2` for the first block or LDRO.
The reduced-rate transmitter adds one parity bit and one zero bit to make a
full-SF label. The receiver removes the two reduced-rate label bits before the
inverse permutation.

Spreading adjacent codeword bits across multiple CSS symbols makes a bad symbol
look like smaller errors in several codewords rather than the destruction of a
single complete codeword. Tests verify normal and reduced-rate round trips for
all four coding rates.

## CRC

The payload CRC uses polynomial `0x1021` and initial state zero. Compatibility
requires a LoRa-specific final-byte convention: all but the last two payload
bytes pass through the bitwise CRC recurrence, then the penultimate byte is
XORed into the high CRC byte and the final byte into the low CRC byte. Four CRC
nibbles are serialized least-significant nibble first.

CRC detects residual payload errors after FEC. It does not correct errors and
is not authentication or a replacement for the LoRaWAN MIC. The explicit
header separately carries payload length, payload CR, and the CRC-present flag,
and has its own five-bit checksum.

## Bit ordering and mapping

- Payload bytes split into low nibble then high nibble.
- Codeword rows are represented MSB first.
- Interleaved labels are converted from Gray to binary and incremented modulo
  `2^SF` to obtain the CSS cyclic-shift index.
- The receiver subtracts that offset, applies binary-to-Gray conversion, and
  then deinterleaves.

These are compatibility rules, not cosmetic choices. Reversing a nibble, bit,
or Gray convention can still produce plausible chirps while every packet fails.

## Tests and golden vector

`TestPacketCoding` checks:

1. The known whitening prefix and self-inverse operation.
2. The complete 16-entry CR 4/8 Hamming codebook.
3. Single-bit correction at every CR 4/8 codeword position.
4. Normal and reduced-rate interleaver/mapping inverses.
5. Header and payload-CRC fixed vectors.
6. A fixed 16-byte payload through all intermediate stages and CSS symbols.
7. Complete noiseless packet round trips for every CR.
8. Raw denominators returned by the coded BER/PER experiment.

The machine-readable vector is
[`model/matlab/golden/lora-phy-sf7-cr1.json`](../model/matlab/golden/lora-phy-sf7-cr1.json).
It is a deterministic internal regression vector. Final over-the-air
compatibility still requires comparison with SX1262 IQ captures.

## References

- [Semtech SX1262 product page and datasheet](https://www.semtech.com/products/wireless-rf/lora-connect/sx1262)
- [Semtech LoRaWAN FAQ: explicit header fields and coding rate](https://www.semtech.com/design-support/faq/faq-lorawan)
- [Semtech TN1300.05: normal interleaving baseline](https://www.semtech.com/uploads/technology/LoRa/predicting-lorawan-capacity.pdf)
- [Marquet, Montavont, Papadopoulos: SDR LoRa PHY reverse engineering](https://doi.org/10.1016/j.comcom.2020.02.034)
- [EPFL GNU Radio LoRa SDR implementation](https://github.com/tapparelj/gr-lora_sdr)
