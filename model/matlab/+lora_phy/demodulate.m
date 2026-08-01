function symbols = demodulate(waveform, config, frequencyOffset)
%DEMODULATE Demodulate an aligned waveform containing complete CSS symbols.

if nargin < 3
    frequencyOffset = 0;
end

waveform = waveform(:);
if mod(numel(waveform), config.samplesPerSymbol) ~= 0
    error("lora_phy:InvalidSampleCount", ...
        "Waveform must contain an integer number of symbols");
end

symbolCount = numel(waveform) / config.samplesPerSymbol;
symbols = zeros(symbolCount, 1);
for index = 1:symbolCount
    source = (index-1) * config.samplesPerSymbol + ...
        (1:config.samplesPerSymbol);
    symbols(index) = lora_phy.demodulate_symbol( ...
        waveform(source), config, frequencyOffset);
end
end
