function labels = diagonal_interleave(codewords, spreadingFactor, reducedRate)
%DIAGONAL_INTERLEAVE Convert one LoRa FEC block to interleaved labels.
% A normal block has SF codewords. The first/reduced block has SF-2.

if nargin < 3
    reducedRate = false;
end
validateattributes(spreadingFactor, {'numeric'}, ...
    {"scalar", "integer", ">=", 5, "<=", 12});
codewords = logical(codewords);
sfApp = spreadingFactor - 2*logical(reducedRate);
if size(codewords, 1) ~= sfApp
    error("lora_phy:InterleaverRows", "Expected SF or SF-2 codewords");
end

codewordLength = size(codewords, 2);
interleaved = false(codewordLength, sfApp);
for bitIndex = 0:codewordLength-1
    for symbolBit = 0:sfApp-1
        sourceRow = mod(bitIndex-symbolBit-1, sfApp);
        interleaved(bitIndex+1, symbolBit+1) = ...
            codewords(sourceRow+1, bitIndex+1);
    end
end

if reducedRate
    parity = mod(sum(interleaved, 2), 2) ~= 0;
    fullBits = [interleaved, parity, false(codewordLength, 1)];
else
    fullBits = interleaved;
end
labels = lora_phy.bits_to_integers(fullBits);
end
