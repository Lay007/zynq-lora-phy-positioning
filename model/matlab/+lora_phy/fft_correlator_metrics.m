function [symbols, confidence, metrics, spectrum] = ...
    fft_correlator_metrics(waveform, config, options)
%FFT_CORRELATOR_METRICS Exact CSS matched filtering with two FFT stages.
%
% The full-rate FFT is multiplied by the conjugated reference spectrum.
% Only correlation lags spaced by samplesPerChip are needed, so frequency
% bins separated by symbolCount are accumulated before a symbolCount-point
% FFT. This is algebraically equivalent to the full-IFFT matched-filter bank
% while exposing an HDL-oriented streaming architecture.

arguments
    waveform (:,1) {mustBeNumeric}
    config (1,1) struct
    options.Reference (:,1) {mustBeNumeric} = zeros(0, 1)
end

waveform = double(waveform(:));
if mod(numel(waveform), config.samplesPerSymbol) ~= 0
    error("lora_phy:InvalidSampleCount", ...
        "Waveform must contain an integer number of CSS symbols");
end

count = numel(waveform)/config.samplesPerSymbol;
windows = reshape(waveform, config.samplesPerSymbol, count);
reference = double(options.Reference(:));
if isempty(reference)
    reference = lora_phy.reference_chirp(config);
elseif numel(reference) ~= config.samplesPerSymbol
    error("lora_phy:InvalidReferenceLength", ...
        "Reference must contain exactly %d samples", ...
        config.samplesPerSymbol);
elseif ~any(reference)
    error("lora_phy:ZeroReference", ...
        "Reference waveform must contain nonzero energy");
end
referenceSpectrum = fft(reference);
correlationSpectrum = fft(windows, [], 1).*conj(referenceSpectrum);

% For M=N*L and desired lags -k*L, the M-point IFFT reduces to an
% N-point forward FFT after aliasing frequency bins q=m+r*N:
%   c[-kL] = FFT_N(sum_r H[m+rN])/M.
aliased = reshape(correlationSpectrum, config.symbolCount, ...
    config.samplesPerChip, count);
candidateCorrelation = fft(sum(aliased, 2), [], 1)/ ...
    config.samplesPerSymbol;
spectrum = reshape(abs(candidateCorrelation).^2, ...
    config.symbolCount, count);

[peak, peakIndex] = max(spectrum, [], 1);
symbols = peakIndex(:)-1;
confidence = (peak./max(sum(spectrum, 1), eps)).';
noisePower = max(median(spectrum, 1)/log(2), eps);
metrics = min((spectrum./noisePower).', 1e6);
end
