function codewords = hamming_encode(nibbles, codingRate)
%HAMMING_ENCODE Encode LoRa data nibbles with CR 1 through 4.
% Rows are MSB-first systematic codewords of width 4+CR.

validateattributes(codingRate, {'numeric'}, ...
    {"scalar", "integer", ">=", 1, "<=", 4}, mfilename, "codingRate");
nibbles = uint8(nibbles(:));
if any(nibbles > 15)
    error("lora_phy:InvalidNibble", "Nibble values must be in [0, 15]");
end

data = lora_phy.integers_to_bits(nibbles, 4);
d0 = data(:, 1);
d1 = data(:, 2);
d2 = data(:, 3);
d3 = data(:, 4);

if codingRate == 1
    parity = xor(xor(d0, d1), xor(d2, d3));
    codewords = [data, parity];
    return;
end

p0 = xor(xor(d0, d1), d2);
p1 = xor(xor(d1, d2), d3);
p2 = xor(xor(d0, d1), d3);
p3 = xor(xor(d0, d2), d3);
parities = [p0, p1, p2, p3];
codewords = [data, parities(:, 1:codingRate)];
end
