function labelLlrs = soft_symbol_to_label_llrs( ...
    symbolMetrics, spreadingFactor, reducedRate)
%SOFT_SYMBOL_TO_LABEL_LLRS Convert FFT-bin metrics to max-log label LLRs.
% Positive LLR means bit zero is more likely; negative means bit one.

if nargin < 3
    reducedRate = false;
end
symbolCount = 2^spreadingFactor;
if size(symbolMetrics, 2) ~= symbolCount
    error("lora_phy:MetricWidth", "Expected one metric per CSS FFT bin");
end
if any(~isfinite(symbolMetrics), "all")
    error("lora_phy:InvalidMetrics", "Symbol metrics must be finite");
end
possibleBins = (0:symbolCount-1).';
possibleLabels = lora_phy.unmap_symbols_to_labels( ...
    possibleBins, spreadingFactor, reducedRate);
effectiveSf = spreadingFactor-2*logical(reducedRate);
labelBits = lora_phy.integers_to_bits(possibleLabels, effectiveSf);
labelLlrs = zeros(size(symbolMetrics, 1), effectiveSf);
for bit = 1:effectiveSf
    zeroMetrics = symbolMetrics(:, ~labelBits(:, bit));
    oneMetrics = symbolMetrics(:, labelBits(:, bit));
    labelLlrs(:, bit) = max(zeroMetrics, [], 2)-max(oneMetrics, [], 2);
end
end
