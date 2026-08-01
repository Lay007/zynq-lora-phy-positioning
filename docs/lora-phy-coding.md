# LoRa PHY coding stages

This document separates the purpose of each bit-processing stage from its exact
SX1262-compatible bit ordering. The conceptual chain is stable; parity matrices,
whitening sequence alignment, header exceptions, and low-data-rate optimization
will be locked only after MATLAB golden vectors match Heltec/SX1262 captures.

## Transmit and receive order

The MATLAB implementation will use this explicit pipeline:

```text
TX
payload bytes
  → append payload CRC when enabled
  → whitening
  → FEC encoding
  → diagonal interleaving
  → Gray/symbol mapping
  → CSS chirp modulation

RX
CSS symbol decisions or soft metrics
  → inverse Gray/symbol mapping
  → deinterleaving
  → FEC decoding
  → dewhitening
  → split and verify payload CRC
  → accept/reject payload
```

The explicit LoRa physical header is processed with its prescribed protection
and carries the payload length, payload coding rate, and payload-CRC-present
flag. Header mode and payload mode must therefore be parameters of every golden
vector, not implicit global state.

## Whitening

Whitening XORs the data bits with a deterministic pseudo-random binary sequence:

```text
whitened[n] = data[n] XOR sequence[n]
```

Applying the same aligned sequence again restores the data. Whitening:

- breaks up long or repetitive bit patterns;
- reduces data-dependent structure presented to later PHY stages;
- helps different payloads exercise the symbol alphabet more uniformly;
- adds no redundancy and corrects no errors.

Synchronization of the sequence is critical. A one-bit offset produces a
completely wrong payload even if every CSS symbol is detected correctly. The
project will therefore test known byte patterns (`00`, `FF`, counters, PRBS),
packet-length boundaries, and reset/alignment behavior against SX1262 captures.

## Forward error correction (FEC)

LoRa applies a systematic block code to four-bit input nibbles. The configured
coding rate selects a codeword length of `4 + CR` bits:

| CR setting | Nominal rate | Encoded bits per 4 data bits | Trade-off |
|---:|---:|---:|---|
| 1 | 4/5 | 5 | least redundancy, shortest airtime |
| 2 | 4/6 | 6 | more parity |
| 3 | 4/7 | 7 | Hamming-derived protection |
| 4 | 4/8 | 8 | most redundancy, longest airtime |

The systematic property means the original data bits appear in the codeword and
the remaining bits are parity. The decoder uses parity consistency to detect or
correct likely errors. More redundancy generally improves robustness but
increases the number of transmitted symbols and time on air.

The first MATLAB version will implement hard-decision encode/decode and inject
errors into every codeword position. A later version should accept soft metrics
from the FFT detector so competing codewords can be ranked by likelihood rather
than by hard bits alone.

## Interleaving

Interleaving writes coded bits into a block and reads them out in a different,
diagonal order before symbol mapping. It does not change bit values or add
redundancy.

Its purpose is to spread adjacent bits of each FEC codeword across different CSS
symbols. A burst disturbance or a badly detected symbol is then converted into
smaller errors distributed among several codewords, which is a better input for
the block decoder than destroying one complete codeword.

The inverse permutation must exactly match spreading factor, coding rate, header
rules, and low-data-rate optimization. Tests will verify both identities:

```text
deinterleave(interleave(bits)) == bits
interleave(deinterleave(bits)) == bits
```

as well as impulse-error propagation through the permutation.

## Cyclic redundancy check (CRC)

CRC appends a deterministic remainder computed over the protected payload. At
the receiver, the payload is reconstructed first and the remainder is computed
again. A mismatch marks the packet invalid.

CRC:

- detects residual errors after FEC;
- does not identify which bit is wrong;
- does not correct errors;
- is not encryption, authentication, or a replacement for the LoRaWAN MIC.

The LoRa payload CRC is configurable. In explicit-header mode, the physical
header tells the receiver whether payload CRC is present, along with payload
length and coding rate. Tests must include zero-length payloads, odd/even byte
counts, single-bit faults, burst faults, correct/incorrect CRC, and explicit vs
implicit header operation.

## Why processing order matters

These blocks solve different problems:

| Stage | Changes length? | Corrects errors? | Detects residual packet error? |
|---|---:|---:|---:|
| Whitening | No | No | No |
| FEC | Yes | Yes, within code capability | Partly through parity |
| Interleaving | No | No | No |
| CRC | Yes | No | Yes |

CRC is calculated on the payload before reversible scrambling/coding so the
receiver can validate the final reconstructed bytes. Interleaving follows FEC
so correlated symbol errors are dispersed before the individual codewords are
decoded. Keeping stage boundaries visible in MATLAB lets us measure BER before
and after each operation instead of treating the PHY as an opaque packet block.

## Planned MATLAB acceptance tests

1. Every stage has an inverse and deterministic bit-order convention.
2. TX → RX round-trip succeeds for payload lengths and all CR settings.
3. Golden intermediate vectors are stored after CRC, whitening, FEC,
   interleaving, and symbol mapping.
4. Single-bit and burst faults demonstrate expected FEC/interleaver behavior.
5. CRC rejects residual corrupted payloads and accepts correct payloads.
6. Generated symbols match SX1262 captures for the same payload and settings.

## References

- [Semtech SX1262 product page and current datasheet](https://www.semtech.com/products/wireless-rf/lora-connect/sx1262)
- [Semtech LoRaWAN FAQ: explicit header fields and coding-rate guidance](https://www.semtech.com/design-support/faq/faq-lorawan)
- [Semtech TN1300.05: 4/5 coding rate and normal interleaving baseline](https://www.semtech.com/uploads/technology/LoRa/predicting-lorawan-capacity.pdf)
- [Marquet, Montavont, Papadopoulos: SDR LoRa PHY reverse engineering](https://doi.org/10.1016/j.comcom.2020.02.034)
