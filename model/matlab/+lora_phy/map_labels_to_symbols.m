function symbols = map_labels_to_symbols(labels, spreadingFactor)
%MAP_LABELS_TO_SYMBOLS Apply LoRa inverse-Gray and +1 CSS-bin mapping.

symbolCount = 2^spreadingFactor;
labels = uint16(labels(:));
if any(double(labels) >= symbolCount)
    error("lora_phy:LabelOutOfRange", "Label exceeds spreading-factor width");
end
symbols = mod(double(lora_phy.gray_to_binary(labels)) + 1, symbolCount);
end
