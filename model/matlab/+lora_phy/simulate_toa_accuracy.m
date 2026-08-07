function result = simulate_toa_accuracy(snrDb, options)
%SIMULATE_TOA_ACCURACY Measure fractional-ToA bias and jitter in AWGN.

arguments
    snrDb (:,1) double = [-25; -20; -15; -10; -5]
    options.TrialsPerPoint (1,1) double ...
        {mustBeInteger, mustBePositive} = 100
    options.SpreadingFactor (1,1) double ...
        {mustBeInteger, mustBeGreaterThanOrEqual(options.SpreadingFactor,5), ...
        mustBeLessThanOrEqual(options.SpreadingFactor,12)} = 7
    options.SamplesPerChip (1,1) double ...
        {mustBeInteger, mustBePositive} = 2
    options.BandwidthHz (1,1) double {mustBePositive} = 125e3
    options.RandomSeed (1,1) double ...
        {mustBeInteger, mustBeNonnegative} = 31415
end

config = lora_phy.css_config( ...
    options.SpreadingFactor, options.SamplesPerChip);
reference = lora_phy.preamble_waveform(config, 8, 2);
sampleRateHz = options.BandwidthHz*options.SamplesPerChip;
leadingSamples = config.samplesPerSymbol;
cleanCapture = [zeros(leadingSamples, 1); reference; ...
    zeros(config.samplesPerSymbol, 1)];
trialCount = numel(snrDb)*options.TrialsPerPoint;
snrColumn = zeros(trialCount, 1);
trialColumn = zeros(trialCount, 1);
trueToa = zeros(trialCount, 1);
estimatedToa = zeros(trialCount, 1);
errorSamples = zeros(trialCount, 1);

previousState = rng;
restoreState = onCleanup(@() rng(previousState));
rng(options.RandomSeed, "twister");
row = 0;
for snrIndex = 1:numel(snrDb)
    noiseScale = sqrt(10^(-snrDb(snrIndex)/10)/2);
    for trial = 1:options.TrialsPerPoint
        row = row+1;
        fractionalDelay = rand;
        delayed = lora_phy.apply_channel_impairments(cleanCapture, ...
            sampleRateHz, FractionalDelaySamples=fractionalDelay);
        noise = noiseScale*(randn(size(delayed))+1j*randn(size(delayed)));
        received = delayed+noise;
        estimate = lora_phy.estimate_fractional_toa( ...
            received, reference, sampleRateHz, ...
            CoarseStartIndex=leadingSamples+1, SearchRadiusSamples=8);
        snrColumn(row) = snrDb(snrIndex);
        trialColumn(row) = trial;
        trueToa(row) = leadingSamples+fractionalDelay;
        estimatedToa(row) = estimate.toaSamples;
        errorSamples(row) = estimate.toaSamples-trueToa(row);
    end
end
trials = table(snrColumn, trialColumn, trueToa, estimatedToa, ...
    errorSamples, VariableNames=["SnrDb", "Trial", "TrueToaSamples", ...
    "EstimatedToaSamples", "ErrorSamples"]);

summary = table(snrDb, zeros(size(snrDb)), zeros(size(snrDb)), ...
    zeros(size(snrDb)), zeros(size(snrDb)), ...
    VariableNames=["SnrDb", "BiasSamples", "StdSamples", ...
    "RmsSamples", "P95AbsoluteSamples"]);
for snrIndex = 1:numel(snrDb)
    errors = errorSamples(snrColumn == snrDb(snrIndex));
    summary.BiasSamples(snrIndex) = mean(errors);
    summary.StdSamples(snrIndex) = std(errors);
    summary.RmsSamples(snrIndex) = sqrt(mean(errors.^2));
    sortedAbsolute = sort(abs(errors));
    percentileIndex = max(1, ceil(0.95*numel(sortedAbsolute)));
    summary.P95AbsoluteSamples(snrIndex) = ...
        sortedAbsolute(percentileIndex);
end

result = struct;
result.trials = trials;
result.summary = summary;
result.config = config;
result.sampleRateHz = sampleRateHz;
result.reference = reference;
result.randomSeed = options.RandomSeed;
end
