function sequence = whitening_sequence(lengthBytes)
%WHITENING_SEQUENCE Generate the LoRa payload whitening byte sequence.
% The x^8+x^6+x^5+x^4+1 LFSR starts at FF. The sequence repeats after
% 255 bytes; packet whitening restarts at the first byte for every packet.

validateattributes(lengthBytes, {'numeric'}, ...
    {"scalar", "integer", ">=", 0}, mfilename, "lengthBytes");

sequence = zeros(lengthBytes, 1, "uint8");
state = uint8(255);
for index = 1:lengthBytes
    sequence(index) = state;
    feedback = bitxor(bitxor(bitget(state, 8), bitget(state, 6)), ...
        bitxor(bitget(state, 5), bitget(state, 4)));
    state = bitor(bitshift(state, 1), uint8(feedback));
end
end
