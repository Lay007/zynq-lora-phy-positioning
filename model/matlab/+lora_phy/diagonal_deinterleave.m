function codewords = diagonal_deinterleave(labels, spreadingFactor, codingRate, reducedRate)
%DIAGONAL_DEINTERLEAVE Recover hard-decision codewords from label integers.
% Reduced-rate labels contain SF-2 core bits after inverse symbol mapping.

if nargin < 4
    reducedRate = false;
end
sfApp = spreadingFactor - 2*logical(reducedRate);
expectedLabels = 4 + codingRate;
labels = labels(:);
if numel(labels) ~= expectedLabels
    error("lora_phy:DeinterleaverRows", "Expected 4+CR labels");
end
interleaved = lora_phy.integers_to_bits(labels, sfApp);
codewords = false(sfApp, expectedLabels);
for bitIndex = 0:expectedLabels-1
    for symbolBit = 0:sfApp-1
        destinationRow = mod(bitIndex-symbolBit-1, sfApp);
        codewords(destinationRow+1, bitIndex+1) = ...
            interleaved(bitIndex+1, symbolBit+1);
    end
end
end
