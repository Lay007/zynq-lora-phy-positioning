function metrics = compare_iq_to_golden(iq, sampleRateHz, spreadingFactor, bandwidthHz, options)
%COMPARE_IQ_TO_GOLDEN Compare one CSS symbol against the MATLAB reference.
%
% The comparison removes one complex scalar gain/phase term, then reports
% normalized EVM, correlation, phase error, and the best sample alignment.

arguments
    iq (:,1) {mustBeNumeric}
    sampleRateHz (1,1) double {mustBePositive}
    spreadingFactor (1,1) double {mustBeInteger, mustBeGreaterThanOrEqual(spreadingFactor,5), mustBeLessThanOrEqual(spreadingFactor,12)}
    bandwidthHz (1,1) double {mustBePositive}
    options.StartIndex (1,1) double {mustBeInteger, mustBePositive} = 1
    options.Symbol (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    options.Direction (1,1) string {mustBeMember(options.Direction,["up","down"])} = "up"
    options.SearchRadiusSamples (1,1) double {mustBeNonnegative} = NaN
end

samplesPerChipExact = sampleRateHz / bandwidthHz;
samplesPerChip = round(samplesPerChipExact);
if abs(samplesPerChipExact-samplesPerChip) > 1e-9
    error("lora_phy:NonIntegerSamplesPerChip", ...
        "Golden comparison requires integer Fs/BW");
end

config = lora_phy.css_config(spreadingFactor, samplesPerChip);
if options.Symbol >= config.symbolCount
    error("lora_phy:InvalidGoldenSymbol", ...
        "Reference symbol must be smaller than 2^SF");
end

reference = lora_phy.modulate_symbol(options.Symbol, config);
if options.Direction == "down"
    reference = conj(reference);
end
reference = reference(:);
symbolSamples = numel(reference);

if isnan(options.SearchRadiusSamples)
    searchRadius = samplesPerChip;
else
    searchRadius = round(options.SearchRadiusSamples);
end

firstStart = max(1, options.StartIndex-searchRadius);
lastStart = min(numel(iq)-symbolSamples+1, options.StartIndex+searchRadius);
if lastStart < firstStart
    error("lora_phy:GoldenWindowOutsideCapture", ...
        "Capture does not contain a complete reference symbol near StartIndex");
end

bestEvm = Inf;
best = struct;
referenceEnergy = sum(abs(reference).^2);
for startIndex = firstStart:lastStart
    received = iq(startIndex:startIndex+symbolSamples-1);
    complexGain = (reference' * received) / referenceEnergy;
    fitted = complexGain * reference;
    residual = received - fitted;
    fittedRms = sqrt(mean(abs(fitted).^2));
    if fittedRms == 0
        evmPercent = Inf;
    else
        evmPercent = 100 * sqrt(mean(abs(residual).^2)) / fittedRms;
    end

    if evmPercent < bestEvm
        bestEvm = evmPercent;
        best.startIndex = startIndex;
        best.received = received;
        best.complexGain = complexGain;
        best.fitted = fitted;
        best.residual = residual;
    end
end

phaseError = angle(best.received .* conj(best.fitted));
correlation = abs(reference' * best.received) / ...
    sqrt(referenceEnergy * sum(abs(best.received).^2));
normalizedReceived = best.received / best.complexGain;

metrics = struct;
metrics.referenceSymbol = options.Symbol;
metrics.direction = options.Direction;
metrics.samplesPerChip = samplesPerChip;
metrics.symbolSamples = symbolSamples;
metrics.requestedStartIndex = options.StartIndex;
metrics.bestStartIndex = best.startIndex;
metrics.startAdjustmentSamples = best.startIndex-options.StartIndex;
metrics.complexGain = best.complexGain;
metrics.gainDb = 20*log10(abs(best.complexGain));
metrics.evmPercent = bestEvm;
metrics.evmDb = 20*log10(bestEvm/100);
metrics.correlation = correlation;
metrics.rmsPhaseErrorDegrees = rad2deg(sqrt(mean(phaseError.^2)));
metrics.maxPhaseErrorDegrees = rad2deg(max(abs(phaseError)));
metrics.maxNormalizedSampleError = max(abs(normalizedReceived-reference));
metrics.passThresholds = struct( ...
    'evmPercent', 1.0, ...
    'correlation', 0.999, ...
    'rmsPhaseErrorDegrees', 1.0);
metrics.passed = metrics.evmPercent <= metrics.passThresholds.evmPercent && ...
    metrics.correlation >= metrics.passThresholds.correlation && ...
    metrics.rmsPhaseErrorDegrees <= metrics.passThresholds.rmsPhaseErrorDegrees;
end
