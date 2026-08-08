function report = evaluate_lora_stream(receiverResult, truth, config)
%EVALUATE_LORA_STREAM Score detections and packet data against time truth.

arguments
    receiverResult (1,1) struct
    truth
    config (1,1) struct
end

if isstruct(truth)
    truth = struct2table(truth);
end
if ~istable(truth)
    error("lora_phy:InvalidStreamTruth", ...
        "truth must be a table or structure array");
end
requiredTruth = ["PacketIndex", "StartIndex", "EndIndex", "Payload"];
if ~all(ismember(requiredTruth, string(truth.Properties.VariableNames)))
    error("lora_phy:InvalidStreamTruth", ...
        "truth is missing required packet boundary or payload columns");
end
requiredReceiver = ["activityRuns", "receptions", "candidateCount", ...
    "sampleRateHz"];
for field = requiredReceiver
    if ~isfield(receiverResult, field)
        error("lora_phy:InvalidStreamResult", ...
            "receiverResult is missing field: %s", field);
    end
end

packetCount = height(truth);
candidateRuns = double(receiverResult.activityRuns);
candidateCount = size(candidateRuns, 1);
assignment = zeros(candidateCount, 1);
for candidate = 1:candidateCount
    overlap = max(0, min(candidateRuns(candidate, 2), truth.EndIndex)- ...
        max(candidateRuns(candidate, 1), truth.StartIndex)+1);
    [maximumOverlap, packet] = max(overlap);
    if maximumOverlap > 0
        assignment(candidate) = packet;
    end
end

rows = cell(packetCount, 1);
activityCandidates = zeros(packetCount, 1);
duplicateCandidates = zeros(packetCount, 1);
structuredReception = false(packetCount, 1);
for packet = 1:packetCount
    associatedCandidates = find(assignment == packet);
    activityCandidates(packet) = numel(associatedCandidates);
    duplicateCandidates(packet) = max(0, numel(associatedCandidates)-1);
    selected = repmat(struct, 0, 1);
    if ~isempty(receiverResult.receptions) && ...
            ~isempty(associatedCandidates)
        receptionCandidates = [receiverResult.receptions.candidateIndex].';
        receptionIndices = find(ismember( ...
            receptionCandidates, associatedCandidates));
        if ~isempty(receptionIndices)
            qualities = arrayfun(@(index) reception_quality( ...
                receiverResult.receptions(index)), receptionIndices);
            [~, best] = max(qualities);
            selected = receiverResult.receptions(receptionIndices(best));
            structuredReception(packet) = true;
        end
    end
    expectedPayload = truth.Payload(packet);
    if iscell(expectedPayload)
        expectedPayload = expectedPayload{1};
    end
    packetReport = lora_phy.evaluate_packet_receptions( ...
        selected, {uint8(expectedPayload(:))}, config);
    row = packetReport.packets;
    row.PacketIndex = truth.PacketIndex(packet);
    rows{packet} = row;
end
if packetCount == 0
    packets = table;
else
    packets = vertcat(rows{:});
end
packets.TruthStartIndex = truth.StartIndex;
packets.TruthEndIndex = truth.EndIndex;
packets.ActivityCandidates = activityCandidates;
packets.DuplicateCandidates = duplicateCandidates;
packets.StructuredReception = structuredReception;
packets.EnergyDetected = activityCandidates > 0;
packets.UndetectedError = packets.CrcChecked & packets.CrcValid & ...
    ~packets.PayloadMatch;

unmatchedCandidates = find(assignment == 0);
falseLoRaReceptions = 0;
if ~isempty(receiverResult.receptions) && ~isempty(unmatchedCandidates)
    for index = 1:numel(receiverResult.receptions)
        reception = receiverResult.receptions(index);
        if ismember(reception.candidateIndex, unmatchedCandidates) && ...
                reception.preambleValid && reception.syncValid
            falseLoRaReceptions = falseLoRaReceptions+1;
        end
    end
end

summary = struct;
summary.Transmissions = packetCount;
summary.ActivityCandidates = candidateCount;
summary.EnergyDetectedPackets = sum(packets.EnergyDetected);
summary.MissedEnergyDetections = packetCount-summary.EnergyDetectedPackets;
summary.StructuredReceptions = sum(packets.StructuredReception);
summary.AcquiredPackets = sum(packets.Acquired);
summary.DetectionProbability = safe_ratio( ...
    summary.AcquiredPackets, packetCount);
summary.FalseAlarmCandidates = numel(unmatchedCandidates);
summary.FalseLoRaReceptions = falseLoRaReceptions;
summary.DuplicateCandidates = sum(duplicateCandidates);
summary.PacketErrors = sum(packets.PacketError);
summary.PER = safe_ratio(summary.PacketErrors, packetCount);
summary.PayloadBitErrors = sum(packets.PayloadBitErrors);
summary.PayloadBits = sum(packets.PayloadBits);
summary.PayloadBER = safe_ratio(summary.PayloadBitErrors, summary.PayloadBits);
summary.ComparedPayloadBitErrors = sum(packets.ComparedPayloadBitErrors);
summary.ComparedPayloadBits = sum(packets.ComparedPayloadBits);
summary.ComparedPayloadBER = safe_ratio( ...
    summary.ComparedPayloadBitErrors, summary.ComparedPayloadBits);
summary.PreFecBitErrors = sum(packets.PreFecBitErrors);
summary.PreFecBits = sum(packets.PreFecBits);
summary.PreFecBER = safe_ratio(summary.PreFecBitErrors, summary.PreFecBits);
summary.HeaderFailures = packetCount-sum(packets.HeaderValid);
summary.CrcFailures = sum(packets.CrcChecked & ~packets.CrcValid);
summary.UndetectedErrors = sum(packets.UndetectedError);
summary.FftCorrelatorPackets = sum( ...
    packets.DemodulationMode == "fft-correlator");
summary.PolyphaseFallbackPackets = sum( ...
    packets.DemodulationMode == "polyphase");
durationSeconds = NaN;
if isfield(receiverResult, "durationSeconds")
    durationSeconds = receiverResult.durationSeconds;
end
summary.DurationSeconds = durationSeconds;
summary.FalseAlarmsPerSecond = safe_ratio( ...
    summary.FalseAlarmCandidates, durationSeconds);
if packetCount > 0
    [summary.DetectionLower95, summary.DetectionUpper95] = ...
        lora_phy.binomial_wilson_interval( ...
        summary.AcquiredPackets, packetCount);
    [summary.PER_Lower95, summary.PER_Upper95] = ...
        lora_phy.binomial_wilson_interval( ...
        summary.PacketErrors, packetCount);
else
    summary.DetectionLower95 = NaN;
    summary.DetectionUpper95 = NaN;
    summary.PER_Lower95 = NaN;
    summary.PER_Upper95 = NaN;
end

report = struct("packets", packets, "summary", summary, ...
    "candidateAssignment", assignment, ...
    "unmatchedCandidateIndices", unmatchedCandidates);
end

function quality = reception_quality(reception)
quality = 100*double(reception.success)+ ...
    20*double(reception.preambleValid && reception.syncValid)+ ...
    5*double(reception.decoded.headerValid);
if ~isempty(reception.symbolConfidence)
    confidence = mean(reception.symbolConfidence, "omitnan");
    if isfinite(confidence)
        quality = quality+confidence;
    end
end
end

function value = safe_ratio(numerator, denominator)
if denominator == 0 || isnan(denominator)
    value = NaN;
else
    value = numerator/denominator;
end
end
