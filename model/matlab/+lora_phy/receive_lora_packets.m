function result = receive_lora_packets( ...
    iq, sampleRateHz, bandwidthHz, spreadingFactor, options)
%RECEIVE_LORA_PACKETS Find and decode every energy-separated LoRa burst.

arguments
    iq (:,1) {mustBeNumeric}
    sampleRateHz (1,1) double {mustBePositive}
    bandwidthHz (1,1) double {mustBePositive}
    spreadingFactor (1,1) double {mustBeInteger, ...
        mustBeGreaterThanOrEqual(spreadingFactor,5), ...
        mustBeLessThanOrEqual(spreadingFactor,12)}
    options.PreambleSymbols (1,1) double {mustBeInteger, mustBePositive} = 8
    options.SyncWord (1,1) double {mustBeInteger, mustBeNonnegative} = hex2dec("12")
    options.IqInverted (1,1) logical = false
    options.LowDataRateOptimization (1,1) double = NaN
    options.ExpectedCarrierOffsetHz (1,1) double = NaN
    options.SoftDecoding (1,1) logical = true
    options.MaximumPayloadSymbols (1,1) double {mustBeInteger, mustBePositive} = 1024
    options.MaximumCandidates (1,1) double {mustBeInteger, mustBePositive} = 128
end

iq = double(iq(:));
samplesPerChip = sampleRateHz/bandwidthHz;
if abs(samplesPerChip-round(samplesPerChip)) > 1e-9
    error("lora_phy:NonIntegerOversampling", ...
        "On-air decoding currently requires an integer Fs/BW ratio");
end
symbolSamples = round(samplesPerChip)*2^spreadingFactor;
[runs, detector] = detect_activity_runs(iq, sampleRateHz);
minimumRunSamples = max(detector.blockLength, ...
    round(0.5*options.PreambleSymbols*symbolSamples));
longEnough = runs(:, 2)-runs(:, 1)+1 >= minimumRunSamples;
runs = runs(longEnough, :);
detector.runExcessPower = detector.runExcessPower(longEnough);
if size(runs, 1) > options.MaximumCandidates
    runPower = detector.runExcessPower;
    [~, order] = sort(runPower, "descend");
    selected = sort(order(1:options.MaximumCandidates));
    runs = runs(selected, :);
    detector.runExcessPower = runPower(selected);
end

receptionCells = cell(size(runs, 1), 1);
diagnostics = strings(size(runs, 1), 1);
segmentBounds = zeros(size(runs));
% Keep each single-packet inspector close to the activity run that created
% the candidate.  Midpoint-only segmentation can leave hundreds of
% milliseconds of unrelated IQ around the final burst; the inspector may
% then lock to a stronger artefact instead of the detected LoRa packet.
guardSamples = max(4*symbolSamples, 2*detector.blockLength);
segmentGuardSamples = zeros(size(runs, 1), 1);
for candidate = 1:size(runs, 1)
    if candidate == 1
        segmentStart = 1;
    else
        segmentStart = floor(0.5*(runs(candidate-1, 2)+runs(candidate, 1)))+1;
    end
    if candidate == size(runs, 1)
        segmentEnd = numel(iq);
    else
        segmentEnd = floor(0.5*(runs(candidate, 2)+runs(candidate+1, 1)));
    end
    candidateGuard = max(guardSamples, ...
        runs(candidate, 2)-runs(candidate, 1)+1);
    segmentGuardSamples(candidate) = candidateGuard;
    segmentStart = max(segmentStart, runs(candidate, 1)-candidateGuard);
    segmentEnd = min(segmentEnd, runs(candidate, 2)+candidateGuard);
    segmentBounds(candidate, :) = [segmentStart, segmentEnd];
    try
        reception = lora_phy.receive_lora_packet( ...
            iq(segmentStart:segmentEnd), sampleRateHz, bandwidthHz, ...
            spreadingFactor, PreambleSymbols=options.PreambleSymbols, ...
            SyncWord=options.SyncWord, IqInverted=options.IqInverted, ...
            LowDataRateOptimization=options.LowDataRateOptimization, ...
            ExpectedCarrierOffsetHz=options.ExpectedCarrierOffsetHz, ...
            SoftDecoding=options.SoftDecoding, ...
            MaximumPayloadSymbols=options.MaximumPayloadSymbols);
        reception = shift_reception_indices(reception, segmentStart-1, sampleRateHz);
        reception.activityStartIndex = runs(candidate, 1);
        reception.activityEndIndex = runs(candidate, 2);
        reception.candidateIndex = candidate;
        receptionCells{candidate} = reception;
    catch exception
        diagnostics(candidate) = string(exception.identifier)+": "+ ...
            string(exception.message);
    end
end

valid = ~cellfun(@isempty, receptionCells);
if any(valid)
    receptions = vertcat(receptionCells{valid});
    successful = [receptions.success].';
    packets = receptions(successful);
else
    receptions = repmat(struct, 0, 1);
    packets = repmat(struct, 0, 1);
end

result = struct;
result.packets = packets;
result.receptions = receptions;
result.activityRuns = runs;
result.segmentBounds = segmentBounds;
result.diagnostics = diagnostics;
result.detector = detector;
result.candidateCount = size(runs, 1);
result.receptionCount = numel(receptions);
result.successCount = numel(packets);
result.sampleRateHz = sampleRateHz;
result.bandwidthHz = bandwidthHz;
result.spreadingFactor = spreadingFactor;
result.guardSamples = guardSamples;
result.segmentGuardSamples = segmentGuardSamples;
end

function [runs, detector] = detect_activity_runs(iq, sampleRateHz)
blockLength = max(32, round(sampleRateHz/2000));
blockCount = floor(numel(iq)/blockLength);
if blockCount < 4
    error("lora_phy:CaptureTooShort", ...
        "At least four activity-detector blocks are required");
end
blocks = reshape(iq(1:blockCount*blockLength), blockLength, blockCount);
blockPower = mean(abs(blocks).^2, 1);
blockPowerDb = 10*log10(blockPower+eps);
sortedPowerDb = sort(blockPowerDb);
noiseSubset = sortedPowerDb(1:max(3, floor(0.4*blockCount)));
noiseDb = median(noiseSubset);
spreadDb = median(abs(noiseSubset-noiseDb));
thresholdDb = noiseDb+max(4, 6*spreadDb);
active = blockPowerDb > thresholdDb;

% Bridge short holes inside one constant-envelope packet, but retain the
% long quiet intervals that separate transmissions.
edges = diff([true, active, true]);
gapStarts = find(edges == -1);
gapEnds = find(edges == 1)-1;
for gap = 1:numel(gapStarts)
    if gapStarts(gap) > 1 && gapEnds(gap) < numel(active) && ...
            gapEnds(gap)-gapStarts(gap)+1 <= 2
        active(gapStarts(gap):gapEnds(gap)) = true;
    end
end
edges = diff([false, active, false]);
runStarts = find(edges == 1);
runEnds = find(edges == -1)-1;
runs = [(runStarts(:)-1)*blockLength+1, ...
    min(numel(iq), runEnds(:)*blockLength)];
runExcessPower = zeros(size(runStarts(:)));
for run = 1:numel(runStarts)
    range = runStarts(run):runEnds(run);
    runExcessPower(run) = sum(max(blockPowerDb(range)-noiseDb, 0));
end
detector = struct;
detector.blockLength = blockLength;
detector.blockTimeSeconds = (((1:blockCount)-0.5)*blockLength/sampleRateHz).';
detector.blockPowerDb = blockPowerDb(:);
detector.noisePowerDb = noiseDb;
detector.thresholdDb = thresholdDb;
detector.activeBlocks = active(:);
detector.runExcessPower = runExcessPower;
end

function reception = shift_reception_indices(reception, offset, sampleRateHz)
indexFields = ["preambleStartIndex", "payloadStartIndex", "packetEndIndex"];
for field = indexFields
    reception.(field) = reception.(field)+offset;
end
reception.preambleStartSeconds = (reception.preambleStartIndex-1)/sampleRateHz;
reception.payloadStartSeconds = (reception.payloadStartIndex-1)/sampleRateHz;
reception.packetEndSeconds = (reception.packetEndIndex-1)/sampleRateHz;

inspectionIndexFields = ["packetStartIndex", "packetEndIndex", "alignedStartIndex"];
for field = inspectionIndexFields
    reception.inspection.(field) = reception.inspection.(field)+offset;
end
reception.inspection.packetStartSeconds = ...
    (reception.inspection.packetStartIndex-1)/sampleRateHz;
reception.inspection.packetEndSeconds = ...
    (reception.inspection.packetEndIndex-1)/sampleRateHz;
if isfield(reception.inspection, "spectrogram")
    reception.inspection.spectrogram.timeSeconds = ...
        reception.inspection.spectrogram.timeSeconds+offset/sampleRateHz;
end
end
