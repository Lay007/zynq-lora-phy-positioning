function result = estimate_fractional_toa( ...
    samples, reference, sampleRateHz, options)
%ESTIMATE_FRACTIONAL_TOA Estimate a known waveform start below one sample.
%
% The integer peak comes from normalized matched filtering. A three-point
% Gaussian interpolation of the correlation magnitude provides the
% fractional correction; see the comment at the fit for why the log rather
% than power, and what the difference is worth in metres.
% toaSamples is zero-based; startIndex is MATLAB's one-based integer index.

arguments
    samples (:,1) {mustBeNumeric}
    reference (:,1) {mustBeNumeric}
    sampleRateHz (1,1) double {mustBePositive}
    options.CoarseStartIndex (1,1) double = NaN
    options.SearchRadiusSamples (1,1) double ...
        {mustBeNonnegative} = Inf
end

samples = double(samples(:));
reference = double(reference(:));
if isempty(reference)
    error("lora_phy:EmptyReference", "Reference waveform cannot be empty");
end
if numel(samples) < numel(reference)
    error("lora_phy:CaptureTooShort", ...
        "Capture is shorter than the ToA reference waveform");
end
referenceEnergy = sum(abs(reference).^2);
if referenceEnergy == 0
    error("lora_phy:ZeroReference", ...
        "Reference waveform must contain nonzero energy");
end

correlation = conv(samples, flipud(conj(reference)), "valid");
windowEnergy = conv(abs(samples).^2, ones(numel(reference), 1), "valid");
scores = abs(correlation)./sqrt(referenceEnergy*windowEnergy+eps);
candidateIndices = (1:numel(scores)).';
eligible = true(size(scores));
if ~isnan(options.CoarseStartIndex)
    if options.CoarseStartIndex < 1 || ...
            options.CoarseStartIndex > numel(scores)
        error("lora_phy:InvalidCoarseStart", ...
            "CoarseStartIndex is outside the valid correlation range");
    end
    eligible = abs(candidateIndices-options.CoarseStartIndex) <= ...
        options.SearchRadiusSamples;
end
if ~any(eligible)
    error("lora_phy:EmptyToaSearch", ...
        "No candidate lies inside the requested ToA search window");
end

eligibleIndices = find(eligible);
[peakScore, localPeak] = max(scores(eligible));
peakIndex = eligibleIndices(localPeak);
if peakScore == 0
    error("lora_phy:NoToaSignal", ...
        "The ToA search window contains no correlated signal energy");
end

fractionalOffset = 0;
if peakIndex > 1 && peakIndex < numel(scores)
    % Gaussian interpolation: the same three-point rule, fitted to the log
    % magnitude rather than to power.
    %
    % A chirp correlation peak is closer to a Gaussian than to a parabola,
    % and fitting the wrong shape leaves a systematic S-curve rather than a
    % random error. Measured noiseless, on the same delay sweep:
    %
    %   parabola on power       0.0625 samples RMS   (75.0 m at Fs=250 kHz)
    %   parabola on magnitude   0.0347               (41.6 m)
    %   parabola on log         0.0066               ( 8.0 m)
    %
    % That bias is deterministic, so averaging over packets does not remove
    % it and across three stations it does not cancel -- it becomes a
    % position offset. TestToaInterpolatorBias pins it.
    %
    % The logs are guarded rather than assumed positive: a correlation
    % magnitude can be zero next to the peak on a short or clipped capture,
    % and log(0) would silently produce a NaN offset.
    magnitudeTriplet = abs(correlation(peakIndex+(-1:1)));
    if all(magnitudeTriplet > 0)
        logTriplet = log(magnitudeTriplet);
        denominator = logTriplet(1)-2*logTriplet(2)+logTriplet(3);
        if abs(denominator) > eps(max(abs(logTriplet)))
            fractionalOffset = 0.5*(logTriplet(1)-logTriplet(3))/ ...
                denominator;
            fractionalOffset = max(-0.5, min(0.5, fractionalOffset));
        end
    end
end

sidelobeScores = scores;
exclusion = max(1, peakIndex-2):min(numel(scores), peakIndex+2);
sidelobeScores(exclusion) = 0;
peakToSidelobeDb = 20*log10(peakScore/max(max(sidelobeScores), eps));
toaSamples = peakIndex-1+fractionalOffset;

result = struct;
result.startIndex = peakIndex;
result.fractionalOffsetSamples = fractionalOffset;
result.toaSamples = toaSamples;
result.toaSeconds = toaSamples/sampleRateHz;
result.peakScore = peakScore;
result.peakToSidelobeDb = peakToSidelobeDb;
result.candidateStartIndices = candidateIndices;
result.scores = scores;
result.sampleRateHz = sampleRateHz;
result.referenceLength = numel(reference);
end
