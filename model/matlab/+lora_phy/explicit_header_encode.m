function nibbles = explicit_header_encode(payloadLength, codingRate, payloadCrc)
%EXPLICIT_HEADER_ENCODE Build the five protected LoRa explicit-header nibbles.

validateattributes(payloadLength, {'numeric'}, ...
    {"scalar", "integer", ">=", 0, "<=", 255});
validateattributes(codingRate, {'numeric'}, ...
    {"scalar", "integer", ">=", 1, "<=", 4});

h0 = uint8(bitshift(uint8(payloadLength), -4));
h1 = uint8(bitand(uint8(payloadLength), 15));
h2 = uint8(2*codingRate + logical(payloadCrc));
b0 = lora_phy.integers_to_bits(h0, 4);
b1 = lora_phy.integers_to_bits(h1, 4);
b2 = lora_phy.integers_to_bits(h2, 4);

c4 = xor(xor(b0(1), b0(2)), xor(b0(3), b0(4)));
c3 = xor(xor(xor(xor(b0(1), b1(1)), b1(2)), b1(3)), b2(4));
c2 = xor(xor(xor(xor(b0(2), b1(1)), b1(4)), b2(1)), b2(3));
c1 = xor(xor(xor(xor(xor(b0(3), b1(2)), b1(4)), b2(2)), b2(3)), b2(4));
c0 = xor(xor(xor(xor(xor(b0(4), b1(3)), b2(1)), b2(2)), b2(3)), b2(4));

checksumLow = lora_phy.bits_to_integers([c3, c2, c1, c0]);
nibbles = uint8([h0; h1; h2; c4; checksumLow]);
end
