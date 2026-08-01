function output = whiten_bytes(input)
%WHITEN_BYTES Apply or undo packet-aligned LoRa payload whitening.

input = uint8(input(:));
output = bitxor(input, lora_phy.whitening_sequence(numel(input)));
end
