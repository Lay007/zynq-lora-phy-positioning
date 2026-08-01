function crc = nibbles_to_crc(nibbles)
%NIBBLES_TO_CRC Deserialize four low-first LoRa CRC nibbles.

nibbles = uint16(nibbles(:));
if numel(nibbles) ~= 4 || any(nibbles > 15)
    error("lora_phy:InvalidCrcNibbles", "CRC requires four nibbles in [0, 15]");
end
crc = bitor(bitor(nibbles(1), bitshift(nibbles(2), 4)), ...
    bitor(bitshift(nibbles(3), 8), bitshift(nibbles(4), 12)));
end
