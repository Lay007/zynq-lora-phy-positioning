function values = bits_to_integers(bits)
%BITS_TO_INTEGERS Convert MSB-first logical rows to uint16 labels.

bits = logical(bits);
if isvector(bits)
    bits = reshape(bits, 1, []);
end
if size(bits, 2) > 16
    error("lora_phy:TooManyBits", "At most 16 bits per integer are supported");
end
values = zeros(size(bits, 1), 1, "uint16");
for column = 1:size(bits, 2)
    values = bitor(bitshift(values, 1), uint16(bits(:, column)));
end
end
