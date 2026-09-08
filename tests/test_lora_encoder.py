"""Pin the Python packet encoder to the authoritative MATLAB golden vector.

The golden file is produced by the MATLAB floating-point model, which is the
project's source of truth for packet coding.  These tests compare every
intermediate the encoder exposes, so a disagreement names the stage that
broke rather than only reporting different bytes at the end.
"""

import json
from pathlib import Path

import pytest

from zynq_lora_phy import decode_lora_packet, encode_lora_packet
from zynq_lora_phy.lora_packet import (
    _diagonal_deinterleave,
    _diagonal_interleave,
    _gray_to_binary,
    _hamming_encode,
    _map_labels_to_symbols,
    _unmap_symbols,
    payload_crc,
    whitening_sequence,
)


GOLDEN_PATH = (
    Path(__file__).resolve().parents[1]
    / "model"
    / "matlab"
    / "golden"
    / "lora-phy-sf7-cr1.json"
)


@pytest.fixture(scope="module")
def golden() -> dict:
    return json.loads(GOLDEN_PATH.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def encoded(golden: dict):
    return encode_lora_packet(
        bytes(golden["payload"]), spreading_factor=7, coding_rate=1
    )


def test_whitening_matches_the_golden_sequence(golden: dict) -> None:
    assert list(whitening_sequence(len(golden["payload"]))) == golden[
        "whiteningSequence"
    ]


def test_whitened_payload_matches_the_golden_vector(golden: dict, encoded) -> None:
    assert list(encoded.whitened_payload) == golden["whitenedPayload"]


def test_payload_crc_matches_the_golden_vector(golden: dict) -> None:
    assert f"{payload_crc(bytes(golden['payload'])):04X}" == golden["payloadCrcHex"]


def test_nibble_stages_match_the_golden_vector(golden: dict, encoded) -> None:
    assert list(encoded.header_nibbles) == golden["headerNibbles"]
    assert list(encoded.payload_nibbles) == golden["payloadNibbles"]
    assert list(encoded.crc_nibbles) == golden["crcNibbles"]


def test_codeword_stages_match_the_golden_vector(golden: dict, encoded) -> None:
    header = [[int(bit) for bit in word] for word in encoded.header_codewords]
    payload = [[int(bit) for bit in word] for word in encoded.payload_codewords]
    assert header == golden["headerCodewords"]
    assert payload == golden["payloadCodewords"]


def test_interleaved_labels_match_the_golden_vector(golden: dict, encoded) -> None:
    # The golden file stores full-width Gray labels.  The reduced-rate header
    # interleaver works on the top sf_app bits of the same value.
    assert list(encoded.header_interleaved_labels) == [
        label >> 2 for label in golden["headerInterleavedLabels"]
    ]
    assert list(encoded.payload_interleaved_labels) == golden[
        "payloadInterleavedLabels"
    ]


def test_css_symbols_match_the_golden_vector(golden: dict, encoded) -> None:
    assert list(encoded.symbols) == golden["cssSymbols"]


def test_encoded_symbols_decode_back_to_the_payload(golden: dict, encoded) -> None:
    result = decode_lora_packet(list(encoded.symbols), spreading_factor=7)
    assert result.success
    assert result.header_valid and result.crc_valid
    assert list(result.payload) == golden["payload"]
    assert result.consumed_symbol_count == len(encoded.symbols)


@pytest.mark.parametrize("width", [5, 7, 12])
def test_gray_to_binary_inverts_the_decoder_gray_mapping(width: int) -> None:
    for value in range(1 << width):
        assert _gray_to_binary(value ^ (value >> 1), width) == value


@pytest.mark.parametrize("reduced_rate", [False, True])
def test_label_symbol_mapping_round_trips(reduced_rate: bool) -> None:
    spreading_factor = 7
    sf_app = spreading_factor - 2 * int(reduced_rate)
    labels = list(range(1 << sf_app))
    symbols = _map_labels_to_symbols(labels, spreading_factor, reduced_rate)
    assert _unmap_symbols(symbols, spreading_factor, reduced_rate) == labels


@pytest.mark.parametrize("coding_rate", [1, 2, 3, 4])
@pytest.mark.parametrize("reduced_rate", [False, True])
def test_diagonal_interleaver_round_trips(coding_rate: int, reduced_rate: bool) -> None:
    spreading_factor = 7
    sf_app = spreading_factor - 2 * int(reduced_rate)
    codewords = [
        _hamming_encode((row * 5 + 3) % 16, coding_rate) for row in range(sf_app)
    ]
    labels = _diagonal_interleave(
        codewords, spreading_factor, coding_rate, reduced_rate
    )
    restored = _diagonal_deinterleave(
        labels, spreading_factor, coding_rate, reduced_rate
    )
    assert restored == codewords


@pytest.mark.parametrize("spreading_factor", [7, 8, 9])
@pytest.mark.parametrize("coding_rate", [1, 2, 3, 4])
@pytest.mark.parametrize("length", [1, 7, 16, 32, 64])
def test_encode_decode_round_trip_over_the_mode_grid(
    spreading_factor: int, coding_rate: int, length: int
) -> None:
    payload = bytes((index * 37 + 11) & 0xFF for index in range(length))
    encoded = encode_lora_packet(
        payload, spreading_factor=spreading_factor, coding_rate=coding_rate
    )
    result = decode_lora_packet(
        list(encoded.symbols), spreading_factor=spreading_factor
    )
    assert result.success, result.failure_reason
    assert result.payload == payload
    assert result.header is not None
    assert result.header.payload_length == length
    assert result.header.coding_rate == coding_rate
    assert result.consumed_symbol_count == len(encoded.symbols)


def test_encoder_symbols_are_inside_the_spreading_factor_range() -> None:
    encoded = encode_lora_packet(bytes(range(16)), spreading_factor=7, coding_rate=1)
    assert all(0 <= symbol < 128 for symbol in encoded.symbols)


def test_encoder_rejects_an_unsupported_coding_rate() -> None:
    with pytest.raises(ValueError, match="coding_rate"):
        encode_lora_packet(b"\x00", coding_rate=5)


def test_encoder_rejects_an_unsupported_spreading_factor() -> None:
    with pytest.raises(ValueError, match="spreading_factor"):
        encode_lora_packet(b"\x00", spreading_factor=13)
