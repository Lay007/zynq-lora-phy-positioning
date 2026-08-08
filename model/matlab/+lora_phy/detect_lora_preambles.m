function [starts, diagnostics] = detect_lora_preambles( ...
    iq, sampleRateHz, bandwidthHz, spreadingFactor, options)
%DETECT_LORA_PREAMBLES Find repeated configured upchirps below the noise floor.

arguments
    iq (:,1) {mustBeNumeric}
    sampleRateHz (1,1) double {mustBePositive}
    bandwidthHz (1,1) double {mustBePositive}
    spreadingFactor (1,1) double ...
        {mustBeInteger, mustBeGreaterThanOrEqual(spreadingFactor,5), ...
        mustBeLessThanOrEqual(spreadingFactor,12)}
    options.PreambleSymbols (1,1) double ...
        {mustBeInteger, mustBeGreaterThanOrEqual(options.PreambleSymbols,4)} = 8
    options.Repetitions (1,1) double ...
        {mustBeInteger, mustBeGreaterThanOrEqual(options.Repetitions,3)} = 5
    options.MinimumPeakToMedianDb (1,1) double = 3
    options.MaximumBinDrift (1,1) double ...
        {mustBeInteger, mustBeNonnegative} = 1
    options.SyncWord (1,1) double ...
        {mustBeInteger, mustBeNonnegative} = hex2dec("12")
end

if options.SyncWord > 255
    error("lora_phy:InvalidSyncWord", "SyncWord must fit one byte");
end

samplesPerChip = sampleRateHz/bandwidthHz;
if abs(samplesPerChip-round(samplesPerChip)) > 1e-9
    error("lora_phy:NonIntegerOversampling", ...
        "Preamble detection requires an integer Fs/BW ratio");
end
samplesPerChip = round(samplesPerChip);
config = lora_phy.css_config(spreadingFactor, samplesPerChip);
symbolSamples = config.samplesPerSymbol;
hop = max(samplesPerChip, round(symbolSamples/4));
hop = max(samplesPerChip, round(hop/samplesPerChip)*samplesPerChip);
scanStarts = (1:hop:numel(iq)-symbolSamples+1).';
windowCount = numel(scanStarts);
bins = zeros(windowCount, 1);
peakToMedianDb = -inf(windowCount, 1);
reference = lora_phy.reference_chirp(config);
downReference = lora_phy.reference_chirp(config, "down");
downBins = zeros(windowCount, 1);
downPeakToMedianDb = -inf(windowCount, 1);
for window = 1:windowCount
    indices = scanStarts(window)+(0:symbolSamples-1);
    dechirped = double(iq(indices(:))).*conj(reference);
    spectrum = lora_phy.polyphase_spectrum(dechirped, samplesPerChip);
    [peak, peakIndex] = max(spectrum);
    noiseBin = max(median(spectrum), eps);
    bins(window) = peakIndex-1;
    peakToMedianDb(window) = 10*log10(max(peak, eps)/noiseBin);
    downDechirped = double(iq(indices(:))).*conj(downReference);
    downSpectrum = lora_phy.polyphase_spectrum( ...
        downDechirped, samplesPerChip);
    [downPeak, downPeakIndex] = max(downSpectrum);
    downBins(window) = downPeakIndex-1;
    downPeakToMedianDb(window) = 10*log10( ...
        max(downPeak, eps)/max(median(downSpectrum), eps));
end

stride = max(1, round(symbolSamples/hop));
repetitions = min([options.Repetitions, options.PreambleSymbols, ...
    floor((windowCount-1)/stride)+1]);
sequenceCount = max(0, windowCount-(repetitions-1)*stride);
sequenceScore = -inf(sequenceCount, 1);
sequenceStable = false(sequenceCount, 1);
sequenceSyncValid = false(sequenceCount, 1);
sequenceSfdValid = false(sequenceCount, 1);
syncSymbols = mod(8*double([bitshift(uint8(options.SyncWord), -4); ...
    bitand(uint8(options.SyncWord), 15)]), config.symbolCount);
for sequence = 1:sequenceCount
    rows = sequence+(0:repetitions-1)*stride;
    distance = circular_distance( ...
        bins(rows), bins(rows(1)), config.symbolCount);
    sequenceStable(sequence) = all(distance <= options.MaximumBinDrift);
    if sequenceStable(sequence)
        sequenceScore(sequence) = mean(peakToMedianDb(rows))-mean(distance);
    end
    syncRows = sequence+(options.PreambleSymbols+(0:1))*stride;
    if syncRows(end) <= windowCount
        expectedSync = mod(bins(sequence)+syncSymbols, config.symbolCount);
        sequenceSyncValid(sequence) = all(circular_distance( ...
            bins(syncRows), expectedSync, config.symbolCount) <= ...
            options.MaximumBinDrift+1);
    end
    sfdRows = sequence+(options.PreambleSymbols+2+(0:1))*stride;
    if sfdRows(end) <= windowCount
        sfdDistance = circular_distance(downBins(sfdRows), ...
            downBins(sfdRows(1)), config.symbolCount);
        sequenceSfdValid(sequence) = ...
            all(sfdDistance <= options.MaximumBinDrift+1) && ...
            mean(downPeakToMedianDb(sfdRows)) >= ...
            options.MinimumPeakToMedianDb;
    end
end
detections = find(sequenceStable & sequenceSyncValid & sequenceSfdValid & ...
    sequenceScore >= options.MinimumPeakToMedianDb);
starts = zeros(0, 1);
selectedScores = zeros(0, 1);
if ~isempty(detections)
    detectionStarts = scanStarts(detections);
    clusterBreaks = [true; diff(detectionStarts) > 2*symbolSamples];
    clusterIds = cumsum(clusterBreaks);
    for cluster = 1:max(clusterIds)
        members = detections(clusterIds == cluster);
        % Preserve the earliest verified repetition. It is closest to the
        % first preamble upchirp; choosing the strongest repetition can move
        % the coarse start several symbols into the same preamble.
        starts(end+1, 1) = scanStarts(members(1)); %#ok<AGROW>
        selectedScores(end+1, 1) = sequenceScore(members(1)); %#ok<AGROW>
    end
end

diagnostics = struct;
diagnostics.hopSamples = hop;
diagnostics.windowStarts = scanStarts;
diagnostics.peakBins = bins;
diagnostics.peakToMedianDb = peakToMedianDb;
diagnostics.downPeakBins = downBins;
diagnostics.downPeakToMedianDb = downPeakToMedianDb;
diagnostics.sequenceScore = sequenceScore;
diagnostics.sequenceStable = sequenceStable;
diagnostics.sequenceSyncValid = sequenceSyncValid;
diagnostics.sequenceSfdValid = sequenceSfdValid;
diagnostics.repetitions = repetitions;
diagnostics.minimumPeakToMedianDb = options.MinimumPeakToMedianDb;
diagnostics.selectedStarts = starts;
diagnostics.selectedScores = selectedScores;
end

function distance = circular_distance(values, reference, modulus)
distance = abs(mod(double(values)-double(reference)+modulus/2, ...
    modulus)-modulus/2);
end
