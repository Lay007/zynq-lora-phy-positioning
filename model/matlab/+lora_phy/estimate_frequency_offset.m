function frequencyOffset = estimate_frequency_offset(samples, config, knownSymbol)
%ESTIMATE_FREQUENCY_OFFSET Estimate normalized CFO from one known CSS symbol.

if nargin < 3
    knownSymbol = 0;
end

samples = samples(:);
if numel(samples) ~= config.samplesPerSymbol
    error("lora_phy:InvalidSampleCount", ...
        "CFO estimation requires exactly one symbol");
end

known = lora_phy.modulate_symbol(knownSymbol, config);
phase = unwrap(angle(samples .* conj(known)));
n = (0:numel(phase)-1).';
centeredN = n - mean(n);
slopeRadiansPerSample = (centeredN.' * phase) / (centeredN.' * centeredN);
frequencyOffset = slopeRadiansPerSample / (2*pi);
end
