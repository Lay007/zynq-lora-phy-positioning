function bits = integers_to_bits(values, width)
%INTEGERS_TO_BITS Convert integer labels to MSB-first logical rows.

validateattributes(width, {'numeric'}, {"scalar", "integer", ">=", 1, "<=", 16});
values = uint16(values(:));
if any(double(values) >= 2^width)
    error("lora_phy:LabelOutOfRange", "Integer does not fit requested width");
end
bits = false(numel(values), width);
for column = 1:width
    bits(:, column) = logical(bitget(values, width-column+1));
end
end
