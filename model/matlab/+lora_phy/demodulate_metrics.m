function [symbols, confidence, metrics] = ...
    demodulate_metrics(waveform, config, options)
%DEMODULATE_METRICS Demodulate aligned CSS symbols and retain FFT metrics.

arguments
    waveform (:,1) {mustBeNumeric}
    config (1,1) struct
    options.CombineOversamplingPhases (1,1) logical = true
    options.Mode (1,1) string = ""
end
waveform = double(waveform(:));
if mod(numel(waveform), config.samplesPerSymbol) ~= 0
    error("lora_phy:InvalidSampleCount", ...
        "Waveform must contain an integer number of CSS symbols");
end
mode = options.Mode;
if mode == ""
    mode = "single-phase";
    if options.CombineOversamplingPhases
        mode = "polyphase";
    end
end
if ~ismember(mode, ["single-phase", "polyphase", "fft-correlator"])
    error("lora_phy:InvalidDemodulationMode", ...
        "Unsupported demodulation mode: %s", mode);
end
if mode == "fft-correlator"
    [symbols, confidence, metrics] = ...
        lora_phy.fft_correlator_metrics(waveform, config);
    return
end

count = numel(waveform)/config.samplesPerSymbol;
reference = lora_phy.reference_chirp(config);
windows = reshape(waveform, config.samplesPerSymbol, count);
dechirped = windows.*conj(reference);
if mode == "polyphase"
    streams = reshape(dechirped, config.samplesPerChip, ...
        config.symbolCount, count);
    phaseSpectra = fft(streams, [], 2);
    spectrum = reshape(sum(abs(phaseSpectra).^2, 1), ...
        config.symbolCount, count);
else
    chipRate = dechirped(1:config.samplesPerChip:end, :);
    spectrum = abs(fft(chipRate, [], 1)).^2;
end
[peak, peakIndex] = max(spectrum, [], 1);
symbols = peakIndex(:)-1;
confidence = (peak./max(sum(spectrum, 1), eps)).';
noisePower = max(median(spectrum, 1)/log(2), eps);
metrics = min((spectrum./noisePower).', 1e6);
end
