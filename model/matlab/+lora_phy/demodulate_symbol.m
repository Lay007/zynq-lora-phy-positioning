function symbol = demodulate_symbol(samples, config, frequencyOffset)
%DEMODULATE_SYMBOL Dechirp one aligned CSS symbol and select its FFT bin.

if nargin < 3
    frequencyOffset = 0;
end

samples = samples(:);
if numel(samples) ~= config.samplesPerSymbol
    error("lora_phy:InvalidSampleCount", ...
        "Expected %d samples, received %d", ...
        config.samplesPerSymbol, numel(samples));
end

n = (0:config.samplesPerSymbol-1).';
compensation = exp(-2j * pi * frequencyOffset * n);
symbol = lora_phy.fft_correlator_metrics(samples.*compensation, config);
end
