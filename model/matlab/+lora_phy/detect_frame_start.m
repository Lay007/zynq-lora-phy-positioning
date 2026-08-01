function [startIndex, peakScore, diagnostics] = detect_frame_start( ...
    received, config, upchirpCount, downchirpCount)
%DETECT_FRAME_START Locate a known CSS preamble at integer-sample resolution.
%
% The score is the mean normalized per-symbol correlation. Magnitudes are
% combined so a carrier-induced phase change between symbols does not cancel
% the complete-preamble correlation.

if nargin < 3
    upchirpCount = 8;
end
if nargin < 4
    downchirpCount = 2;
end

received = received(:);
reference = lora_phy.preamble_waveform( ...
    config, upchirpCount, downchirpCount);
preambleSamples = numel(reference);
if numel(received) < preambleSamples
    error("lora_phy:CaptureTooShort", ...
        "Capture is shorter than the configured preamble");
end

symbolSamples = config.samplesPerSymbol;
preambleSymbols = upchirpCount + downchirpCount;
referenceMatrix = reshape(reference, symbolSamples, preambleSymbols);
referenceEnergy = sum(abs(referenceMatrix).^2, 1);
candidateCount = numel(received) - preambleSamples + 1;
scores = zeros(candidateCount, 1);

for candidate = 1:candidateCount
    indices = candidate:candidate+preambleSamples-1;
    segment = reshape(received(indices), symbolSamples, preambleSymbols);
    numerator = abs(sum(conj(referenceMatrix) .* segment, 1));
    segmentEnergy = sum(abs(segment).^2, 1);
    denominator = sqrt(referenceEnergy .* segmentEnergy + eps);
    scores(candidate) = mean(numerator ./ denominator);
end

[peakScore, startIndex] = max(scores);
diagnostics = struct;
diagnostics.candidateStartIndices = (1:candidateCount).';
diagnostics.scores = scores;
end
