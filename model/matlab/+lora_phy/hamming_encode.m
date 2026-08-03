function codewords = hamming_encode(nibbles, codingRate)
%HAMMING_ENCODE Encode LoRa data nibbles with CR 1 through 4.
% LoRa transmits the four data bits least-significant bit first inside each
% codeword. Rows use that on-air order, so the systematic prefix is
% [b0 b1 b2 b3], followed by the selected parity bits.

validateattributes(codingRate, {'numeric'}, ...
    {"scalar", "integer", ">=", 1, "<=", 4}, mfilename, "codingRate");
nibbles = uint8(nibbles(:));
if any(nibbles > 15)
    error("lora_phy:InvalidNibble", "Nibble values must be in [0, 15]");
end

dataMsbFirst = lora_phy.integers_to_bits(nibbles, 4);
b3 = dataMsbFirst(:, 1);
b2 = dataMsbFirst(:, 2);
b1 = dataMsbFirst(:, 3);
b0 = dataMsbFirst(:, 4);
systematic = [b0, b1, b2, b3];

if codingRate == 1
    parity = xor(xor(b0, b1), xor(b2, b3));
    codewords = [systematic, parity];
    return;
end

p0 = xor(xor(b0, b1), b2);
p1 = xor(xor(b1, b2), b3);
p2 = xor(xor(b0, b1), b3);
p3 = xor(xor(b0, b2), b3);
parities = [p0, p1, p2, p3];
codewords = [systematic, parities(:, 1:codingRate)];
end
