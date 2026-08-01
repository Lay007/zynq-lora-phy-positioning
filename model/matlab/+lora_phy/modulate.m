function waveform = modulate(symbols, config)
%MODULATE Modulate a vector of CSS symbols into a complex column vector.

symbols = symbols(:);
waveform = complex(zeros(numel(symbols) * config.samplesPerSymbol, 1));

for index = 1:numel(symbols)
    destination = (index-1) * config.samplesPerSymbol + ...
        (1:config.samplesPerSymbol);
    waveform(destination) = lora_phy.modulate_symbol(symbols(index), config);
end
end
