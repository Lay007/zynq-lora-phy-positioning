function [nibbles, margins, correctedCodewords] = ...
    hamming_decode_soft(codewordLlrs, codingRate)
%HAMMING_DECODE_SOFT Maximum-likelihood LoRa FEC decode from bit LLRs.
% Positive input values favour zero; negative values favour one.

validateattributes(codingRate, {'numeric'}, ...
    {"scalar", "integer", ">=", 1, "<=", 4}, mfilename, "codingRate");
if size(codewordLlrs, 2) ~= 4+codingRate
    error("lora_phy:CodewordWidth", "Expected 4+CR LLR columns");
end
if any(~isfinite(codewordLlrs), "all")
    error("lora_phy:InvalidLlrs", "Codeword LLRs must be finite");
end

codebook = lora_phy.hamming_encode(uint8((0:15).'), codingRate);
signedCodebook = 1-2*double(codebook);
nibbles = zeros(size(codewordLlrs, 1), 1, "uint8");
margins = zeros(size(codewordLlrs, 1), 1);
correctedCodewords = false(size(codewordLlrs));
for row = 1:size(codewordLlrs, 1)
    scores = 0.5*signedCodebook*codewordLlrs(row, :).';
    [orderedScores, order] = sort(scores, "descend");
    selected = order(1);
    nibbles(row) = uint8(selected-1);
    correctedCodewords(row, :) = codebook(selected, :);
    if numel(orderedScores) > 1
        margins(row) = orderedScores(1)-orderedScores(2);
    else
        margins(row) = inf;
    end
end
end
