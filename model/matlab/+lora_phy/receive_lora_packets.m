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
    options.ExplicitHeader (1,1) logical = true
    options.PayloadLength (1,1) double = NaN
    options.CodingRate (1,1) double ...
        {mustBeInteger, mustBeGreaterThanOrEqual(options.CodingRate,1), ...
        mustBeLessThanOrEqual(options.CodingRate,4)} = 1
    options.PayloadCrc (1,1) logical = true
    options.ReturnSymbolWindows (1,1) logical = false
end

iq = double(iq(:));
samplesPerChip = sampleRateHz/bandwidthHz;
if abs(samplesPerChip-round(samplesPerChip)) > 1e-9
    error("lora_phy:NonIntegerOversampling", ...
        "On-air decoding currently requires an integer Fs/BW ratio");
end
symbolSamples = round(samplesPerChip)*2^spreadingFactor;
[runs, detector] = detect_activity_runs( ...
    iq, sampleRateHz, options.PreambleSymbols*symbolSamples);
minimumRunSamples = max(detector.blockLength, round( ...
    (options.PreambleSymbols+2+2.25+2*(spreadingFactor < 7))*symbolSamples));
longEnough = runs(:, 2)-runs(:, 1)+1 >= minimumRunSamples;
runs = runs(longEnough, :);
detector.runExcessPower = detector.runExcessPower(longEnough);
[chirpStarts, chirpDiagnostics] = lora_phy.detect_lora_preambles( ...
    iq, sampleRateHz, bandwidthHz, spreadingFactor, ...
    PreambleSymbols=options.PreambleSymbols, SyncWord=options.SyncWord);
energyRuns = runs;
candidatePreambleStarts = nan(size(runs, 1), 1);
candidateSources = repmat("energy", size(runs, 1), 1);
candidateScores = detector.runExcessPower(:);
for chirp = 1:numel(chirpStarts)
    nearby = find(chirpStarts(chirp) >= runs(:, 1)-2*symbolSamples & ...
        chirpStarts(chirp) <= runs(:, 2)+2*symbolSamples & ...
        isnan(candidatePreambleStarts), 1);
    if ~isempty(nearby)
        candidatePreambleStarts(nearby) = chirpStarts(chirp);
        candidateSources(nearby) = "energy+chirp";
        candidateScores(nearby) = candidateScores(nearby)+ ...
            chirpDiagnostics.selectedScores(chirp);
    else
        % A strong packet elsewhere in the capture must not suppress a
        % chirp-validated packet that remains below the energy threshold.
        % Keep every unmatched chirp sequence as an independent candidate.
        pseudoStart = max(1, chirpStarts(chirp)-symbolSamples);
        pseudoEnd = min(numel(iq), chirpStarts(chirp)+ ...
            (options.PreambleSymbols+4)*symbolSamples-1);
        runs(end+1, :) = [pseudoStart, pseudoEnd]; %#ok<AGROW>
        candidatePreambleStarts(end+1, 1) = chirpStarts(chirp); %#ok<AGROW>
        candidateSources(end+1, 1) = "chirp"; %#ok<AGROW>
        candidateScores(end+1, 1) = ...
            chirpDiagnostics.selectedScores(chirp); %#ok<AGROW>
    end
end
if ~isempty(runs)
    candidateCentres = mean(runs, 2);
    hasPreambleStart = isfinite(candidatePreambleStarts);
    candidateCentres(hasPreambleStart) = ...
        candidatePreambleStarts(hasPreambleStart);
    [~, order] = sort(candidateCentres);
    runs = runs(order, :);
    candidatePreambleStarts = candidatePreambleStarts(order);
    candidateSources = candidateSources(order);
    candidateScores = candidateScores(order);
end
detector.energyRuns = energyRuns;
detector.chirp = chirpDiagnostics;
detector.runExcessPower = candidateScores;
if size(runs, 1) > options.MaximumCandidates
    runPower = candidateScores;
    [~, order] = sort(runPower, "descend");
    selected = sort(order(1:options.MaximumCandidates));
    runs = runs(selected, :);
    detector.runExcessPower = runPower(selected);
    candidatePreambleStarts = candidatePreambleStarts(selected);
    candidateSources = candidateSources(selected);
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
hasChirp = candidateSources == "chirp";
for candidate = 1:size(runs, 1)
    if hasChirp(candidate)
        segmentStart = max(1, ...
            candidatePreambleStarts(candidate)-2*symbolSamples);
        % A repeated payload symbol can look like a preamble candidate.
        % Do not let that unvalidated candidate truncate the preceding real
        % packet. The supplied coarse start keeps the single-packet receiver
        % local even though its candidate segment extends to stream end.
        segmentEnd = numel(iq);
    else
        if candidate == 1
            segmentStart = 1;
        else
            segmentStart = floor(0.5*(runs(candidate-1, 2)+ ...
                runs(candidate, 1)))+1;
        end
        if candidate == size(runs, 1)
            segmentEnd = numel(iq);
        else
            segmentEnd = floor(0.5*(runs(candidate, 2)+ ...
                runs(candidate+1, 1)));
        end
    end
    candidateGuard = max(guardSamples, ...
        runs(candidate, 2)-runs(candidate, 1)+1);
    segmentGuardSamples(candidate) = candidateGuard;
    if ~hasChirp(candidate)
        segmentStart = max(segmentStart, runs(candidate, 1)-candidateGuard);
        segmentEnd = min(segmentEnd, runs(candidate, 2)+candidateGuard);
    end
    segmentBounds(candidate, :) = [segmentStart, segmentEnd];
    try
        coarseLocal = NaN;
        if hasChirp(candidate)
            coarseLocal = candidatePreambleStarts(candidate)-segmentStart+1;
        end
        reception = lora_phy.receive_lora_packet( ...
            iq(segmentStart:segmentEnd), sampleRateHz, bandwidthHz, ...
            spreadingFactor, PreambleSymbols=options.PreambleSymbols, ...
            SyncWord=options.SyncWord, IqInverted=options.IqInverted, ...
            LowDataRateOptimization=options.LowDataRateOptimization, ...
            ExpectedCarrierOffsetHz=options.ExpectedCarrierOffsetHz, ...
            SoftDecoding=options.SoftDecoding, ...
            MaximumPayloadSymbols=options.MaximumPayloadSymbols, ...
            ExplicitHeader=options.ExplicitHeader, ...
            PayloadLength=options.PayloadLength, ...
            CodingRate=options.CodingRate, PayloadCrc=options.PayloadCrc, ...
            ReturnSymbolWindows=options.ReturnSymbolWindows, ...
            CoarsePreambleStartIndex=coarseLocal);
        selectedSegmentStart = segmentStart;
        if ~(reception.preambleValid && reception.syncValid)
            retryStart = runs(candidate, 1);
            if retryStart > segmentStart
                try
                    retryCoarse = NaN;
                    if hasChirp(candidate)
                        retryCoarse = candidatePreambleStarts(candidate)- ...
                            retryStart+1;
                    end
                    retry = lora_phy.receive_lora_packet( ...
                        iq(retryStart:segmentEnd), sampleRateHz, bandwidthHz, ...
                        spreadingFactor, PreambleSymbols=options.PreambleSymbols, ...
                        SyncWord=options.SyncWord, IqInverted=options.IqInverted, ...
                        LowDataRateOptimization=options.LowDataRateOptimization, ...
                        ExpectedCarrierOffsetHz=options.ExpectedCarrierOffsetHz, ...
                        SoftDecoding=options.SoftDecoding, ...
                        MaximumPayloadSymbols=options.MaximumPayloadSymbols, ...
                        ExplicitHeader=options.ExplicitHeader, ...
                        PayloadLength=options.PayloadLength, ...
                        CodingRate=options.CodingRate, ...
                        PayloadCrc=options.PayloadCrc, ...
                        ReturnSymbolWindows=options.ReturnSymbolWindows, ...
                        CoarsePreambleStartIndex=retryCoarse);
                    originalQuality = acquisition_quality(reception);
                    retryQuality = acquisition_quality(retry);
                    if retryQuality > originalQuality
                        reception = retry;
                        selectedSegmentStart = retryStart;
                        segmentBounds(candidate, 1) = retryStart;
                    end
                catch
                    % Preserve the structured first-pass result when the
                    % tighter retry cannot hold a complete acquisition.
                end
            end
        end
        reception = shift_reception_indices( ...
            reception, selectedSegmentStart-1, sampleRateHz);
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
result.candidatePreambleStarts = candidatePreambleStarts;
result.candidateSources = candidateSources;
end

function [runs, detector] = detect_activity_runs( ...
    iq, sampleRateHz, preambleSamples)
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
% A single threshold fails when the receiver gain or an interferer raises
% the floor for part of a capture: several packets then become one long
% activity run. Track that slow change with a median window that is at
% least four preambles wide. A 200 ms lower bound also leaves enough quiet
% samples around short SF5/SF6 packets for an unbiased local floor.
localWindowBlocks = max(3, ceil(max(0.2*sampleRateHz, ...
    4*preambleSamples)/blockLength));
if mod(localWindowBlocks, 2) == 0
    localWindowBlocks = localWindowBlocks+1;
end
localNoiseDb = movmedian(blockPowerDb, localWindowBlocks);
adaptiveThresholdDb = max(thresholdDb, localNoiseDb+4);
globalActive = bridge_short_holes(blockPowerDb > thresholdDb, 2);
% Do not bridge the local mask: on a raised floor, isolated high-power
% outliers around a real packet can otherwise become additional
% preamble-sized false candidates.
localActive = blockPowerDb > adaptiveThresholdDb;
[globalStarts, globalEnds] = logical_runs(globalActive);
[localStarts, localEnds] = logical_runs(localActive);

% Preserve an ordinary global run when the dense packet sequence raises the
% rolling median so far that no local run remains. When one or more local
% preamble-sized runs do exist, they are the tighter packet candidates and
% replace the broad global run.
minimumLocalBlocks = max(1, ceil(0.5*preambleSamples/blockLength));
localLongEnough = localEnds-localStarts+1 >= minimumLocalBlocks;
localStarts = localStarts(localLongEnough);
localEnds = localEnds(localLongEnough);
runStarts = zeros(0, 1);
runEnds = zeros(0, 1);
for globalRun = 1:numel(globalStarts)
    contained = localStarts >= globalStarts(globalRun) & ...
        localEnds <= globalEnds(globalRun);
    if any(contained)
        runStarts = [runStarts; localStarts(contained)]; %#ok<AGROW>
        runEnds = [runEnds; localEnds(contained)]; %#ok<AGROW>
    else
        runStarts(end+1, 1) = globalStarts(globalRun); %#ok<AGROW>
        runEnds(end+1, 1) = globalEnds(globalRun); %#ok<AGROW>
    end
end
active = false(size(globalActive));
for run = 1:numel(runStarts)
    active(runStarts(run):runEnds(run)) = true;
end
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
detector.localWindowBlocks = localWindowBlocks;
detector.localNoisePowerDb = localNoiseDb(:);
detector.adaptiveThresholdDb = adaptiveThresholdDb(:);
detector.activeBlocks = active(:);
detector.runExcessPower = runExcessPower;
end

function quality = acquisition_quality(reception)
quality = 4*double(reception.success)+ ...
    2*double(reception.preambleValid && reception.syncValid)+ ...
    double(reception.decoded.headerValid);
end

function active = bridge_short_holes(active, maximumGapBlocks)
edges = diff([true, active, true]);
gapStarts = find(edges == -1);
gapEnds = find(edges == 1)-1;
for gap = 1:numel(gapStarts)
    if gapStarts(gap) > 1 && gapEnds(gap) < numel(active) && ...
            gapEnds(gap)-gapStarts(gap)+1 <= maximumGapBlocks
        active(gapStarts(gap):gapEnds(gap)) = true;
    end
end
end

function [starts, ends] = logical_runs(active)
edges = diff([false, active, false]);
starts = find(edges == 1).';
ends = (find(edges == -1)-1).';
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
