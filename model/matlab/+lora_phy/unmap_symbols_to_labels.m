function labels = unmap_symbols_to_labels(symbols, spreadingFactor, reducedRate)
%UNMAP_SYMBOLS_TO_LABELS Undo LoRa CSS-bin and Gray mapping.
% Reduced first-block symbols are divided by four before Gray mapping;
% diagonal-interleaver parity occupies the two discarded label bits.

if nargin < 3
    reducedRate = false;
end
symbolCount = 2^spreadingFactor;
symbols = double(symbols(:));
if any(symbols < 0 | symbols >= symbolCount | symbols ~= floor(symbols))
    error("lora_phy:SymbolOutOfRange", "CSS symbols must be integer labels in range");
end
binary = mod(symbols-1, symbolCount);
if reducedRate
    binary = floor(binary/4);
end
labels = lora_phy.binary_to_gray(uint16(binary));
end
