function stages = fft_correlator_stages(waveform, config, options)
%FFT_CORRELATOR_STAGES Expose every intermediate of the CSS FFT correlator.
%
% This is the single numerical definition of the HDL-oriented correlator.
% LORA_PHY.FFT_CORRELATOR_METRICS is a thin wrapper around it, so exported
% golden vectors and the packet receiver can never disagree.
%
% The returned struct contains, for a waveform holding COUNT symbols of
% M = config.samplesPerSymbol samples each:
%
%   input                M x COUNT  aligned symbol windows
%   referenceSpectrum    M x 1      fft(reference)
%   conjReferenceSpectrum M x 1     conj(fft(reference))
%   fftM                 M x COUNT  M-point forward FFT of each window
%   product              M x COUNT  fftM .* conj(referenceSpectrum)
%   partition            N x COUNT  sum over r of product(m + r*N)
%   fftN                 N x COUNT  N-point forward FFT of partition, /M
%   magnitudeSquared     N x COUNT  |fftN|^2
%   symbols              COUNT x 1  argmax(magnitudeSquared) - 1
%   confidence           COUNT x 1  peak / sum(magnitudeSquared)
%   metrics              COUNT x N  magnitudeSquared normalized by noise floor
%
% Stage names match the Simulink and HDL comparison points.

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
conjReferenceSpectrum = conj(referenceSpectrum);
fftM = fft(windows, [], 1);
product = fftM.*conjReferenceSpectrum;

% For M=N*L and desired lags -k*L, the M-point IFFT reduces to an
% N-point forward FFT after aliasing frequency bins q=m+r*N:
%   c[-kL] = FFT_N(sum_r H[m+rN])/M.
aliased = reshape(product, config.symbolCount, config.samplesPerChip, count);
partition = reshape(sum(aliased, 2), config.symbolCount, count);
fftN = fft(partition, [], 1)/config.samplesPerSymbol;
magnitudeSquared = abs(fftN).^2;

[peak, peakIndex] = max(magnitudeSquared, [], 1);
symbols = peakIndex(:)-1;
confidence = (peak./max(sum(magnitudeSquared, 1), eps)).';
noisePower = max(median(magnitudeSquared, 1)/log(2), eps);
metrics = min((magnitudeSquared./noisePower).', 1e6);

stages = struct;
stages.config = config;
stages.symbolCount = count;
stages.input = windows;
stages.reference = reference;
stages.referenceSpectrum = referenceSpectrum;
stages.conjReferenceSpectrum = conjReferenceSpectrum;
stages.fftM = fftM;
stages.product = product;
stages.partition = partition;
stages.fftN = fftN;
stages.magnitudeSquared = magnitudeSquared;
stages.peak = peak(:);
stages.symbols = symbols;
stages.confidence = confidence;
stages.metrics = metrics;
end
