function [symbols, confidence, metrics] = ...
    matched_filter_metrics(waveform, config)
%MATCHED_FILTER_METRICS Coherently correlate symbols with every CSS waveform.
%
% This is a floating-point reference receiver rather than an RTL-oriented
% implementation. It uses every complex sample and preserves phase while
% correlating against the complete bank of cyclically shifted chirps.

waveform = double(waveform(:));
if mod(numel(waveform), config.samplesPerSymbol) ~= 0
    error("lora_phy:InvalidSampleCount", ...
        "Waveform must contain an integer number of CSS symbols");
end

count = numel(waveform)/config.samplesPerSymbol;
windows = reshape(waveform, config.samplesPerSymbol, count);
referenceSpectrum = fft(lora_phy.reference_chirp(config));

% Circular correlation with the unshifted chirp produces all cyclic-shift
% hypotheses in one FFT. MODULATE_SYMBOL shifts symbol k by -k*L samples,
% hence its correlation peak is at lag -k*L modulo the symbol length.
correlation = ifft(fft(windows, [], 1).*conj(referenceSpectrum), [], 1);
candidateLags = mod(-(0:config.symbolCount-1)*config.samplesPerChip, ...
    config.samplesPerSymbol);
spectrum = abs(correlation(candidateLags+1, :)).^2;

[peak, peakIndex] = max(spectrum, [], 1);
symbols = peakIndex(:)-1;
confidence = (peak./max(sum(spectrum, 1), eps)).';
noisePower = max(median(spectrum, 1)/log(2), eps);
metrics = min((spectrum./noisePower).', 1e6);
end
