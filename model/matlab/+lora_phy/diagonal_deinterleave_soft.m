function codewordLlrs = diagonal_deinterleave_soft( ...
    labelLlrs, spreadingFactor, codingRate, reducedRate)
%DIAGONAL_DEINTERLEAVE_SOFT Apply the LoRa permutation to bit LLRs.

if nargin < 4
    reducedRate = false;
end
effectiveSf = spreadingFactor-2*logical(reducedRate);
expectedLabels = 4+codingRate;
if ~isequal(size(labelLlrs), [expectedLabels, effectiveSf])
    error("lora_phy:SoftDeinterleaverSize", ...
        "Expected a (4+CR)-by-effectiveSF LLR matrix");
end
codewordLlrs = zeros(effectiveSf, expectedLabels);
for bitIndex = 0:expectedLabels-1
    for symbolBit = 0:effectiveSf-1
        destinationRow = mod(bitIndex-symbolBit-1, effectiveSf);
        codewordLlrs(destinationRow+1, bitIndex+1) = ...
            labelLlrs(bitIndex+1, symbolBit+1);
    end
end
end
