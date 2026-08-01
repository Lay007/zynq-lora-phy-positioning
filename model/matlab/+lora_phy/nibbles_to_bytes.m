function bytes = nibbles_to_bytes(nibbles)
%NIBBLES_TO_BYTES Join low-nibble-first LoRa nibbles into bytes.

nibbles = uint8(nibbles(:));
if mod(numel(nibbles), 2) ~= 0
    error("lora_phy:OddNibbleCount", "Nibble count must be even");
end
if any(nibbles > 15)
    error("lora_phy:InvalidNibble", "Nibble values must be in [0, 15]");
end

bytes = bitor(nibbles(1:2:end), bitshift(nibbles(2:2:end), 4));
end
