function nibbles = bytes_to_nibbles(bytes)
%BYTES_TO_NIBBLES Split bytes into low-nibble-first LoRa order.

bytes = uint8(bytes(:));
nibbles = zeros(2*numel(bytes), 1, "uint8");
nibbles(1:2:end) = bitand(bytes, uint8(15));
nibbles(2:2:end) = bitshift(bytes, -4);
end
