function [nibbles, distances, correctedCodewords] = hamming_decode(codewords, codingRate)
%HAMMING_DECODE Hard-decision maximum-likelihood LoRa nibble decoder.

validateattributes(codingRate, {'numeric'}, ...
    {"scalar", "integer", ">=", 1, "<=", 4}, mfilename, "codingRate");
codewords = logical(codewords);
if size(codewords, 2) ~= 4 + codingRate
    error("lora_phy:CodewordWidth", "Expected 4+CR columns");
end

codebook = lora_phy.hamming_encode(uint8((0:15).'), codingRate);
nibbles = zeros(size(codewords, 1), 1, "uint8");
distances = zeros(size(codewords, 1), 1);
correctedCodewords = false(size(codewords));
for row = 1:size(codewords, 1)
    candidates = sum(xor(codebook, codewords(row, :)), 2);
    [distances(row), selected] = min(candidates);
    nibbles(row) = uint8(selected-1);
    correctedCodewords(row, :) = codebook(selected, :);
end
end
