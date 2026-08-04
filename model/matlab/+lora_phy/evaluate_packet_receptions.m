function report = evaluate_packet_receptions(receptions, expectedPayloads, config)
%EVALUATE_PACKET_RECEPTIONS Calculate acquisition, BER, CRC, and PER counters.
% Receptions and expected payloads are paired in chronological order.

expectedPayloads = expectedPayloads(:);
if ~iscell(expectedPayloads)
    error("lora_phy:ExpectedPayloadCell", "expectedPayloads must be a cell array");
end
if ~isempty(receptions) && isfield(receptions, "preambleStartIndex")
    [~, order] = sort([receptions.preambleStartIndex]);
    receptions = receptions(order);
end
packetCount = numel(expectedPayloads);
pairing = pair_receptions(receptions, expectedPayloads);
rows = repmat(empty_row(), packetCount, 1);
for packet = 1:packetCount
    expected = uint8(expectedPayloads{packet}(:));
    row = empty_row();
    row.PacketIndex = packet;
    row.ExpectedLength = numel(expected);
    row.PayloadBits = 8*numel(expected);
    expectedEncoded = lora_phy.encode_packet(expected, config);
    if pairing(packet) > 0
        reception = receptions(pairing(packet));
        row.CandidatePresent = true;
        row.HardSuccess = reception.decoded.success;
        row.SoftSuccess = reception.decoded.success;
        if isfield(reception, "hardDecoded")
            row.HardSuccess = reception.hardDecoded.success;
        end
        if isfield(reception, "softDecoded")
            row.SoftSuccess = reception.softDecoded.success;
        end
        row.SoftRecovered = row.SoftSuccess && ~row.HardSuccess;
        row.DecoderMethod = "unspecified";
        if isfield(reception, "decodingMethod")
            row.DecoderMethod = string(reception.decodingMethod);
        end
        row.Acquired = reception.preambleValid && reception.syncValid;
        row.HeaderValid = reception.decoded.headerValid;
        row.CrcChecked = logical(config.payloadCrc);
        row.CrcValid = reception.decoded.crcValid;
        received = uint8(reception.decoded.payload(:));
        row.DecodedLength = numel(received);
        row.PayloadLengthValid = numel(received) == numel(expected);
        if row.PayloadLengthValid
            row.ComparedPayloadBits = row.PayloadBits;
            row.ComparedPayloadBitErrors = bit_errors(expected, received);
            row.PayloadBitErrors = row.ComparedPayloadBitErrors;
            row.PayloadMatch = row.ComparedPayloadBitErrors == 0;
        else
            row.PayloadBitErrors = row.PayloadBits;
        end
        expectedCodewords = logical(expectedEncoded.payloadCodewords);
        receivedCodewords = logical(reception.decoded.receivedPayloadCodewords);
        if isequal(size(receivedCodewords), size(expectedCodewords))
            row.PreFecBits = numel(expectedCodewords);
            row.PreFecBitErrors = nnz(xor(expectedCodewords, receivedCodewords));
        end
        row.PacketError = ~row.Acquired || ~row.HeaderValid || ...
            ~row.PayloadMatch || (row.CrcChecked && ~row.CrcValid);
    else
        row.CrcChecked = logical(config.payloadCrc);
        row.PayloadBitErrors = row.PayloadBits;
        row.PacketError = true;
    end
    rows(packet) = row;
end

packets = struct2table(rows);
summary = struct;
summary.Transmissions = packetCount;
summary.Candidates = numel(receptions);
summary.AcquiredPackets = sum(packets.Acquired);
summary.HeaderValidPackets = sum(packets.HeaderValid);
summary.CrcCheckedPackets = sum(packets.CrcChecked);
summary.CrcValidPackets = sum(packets.CrcChecked & packets.CrcValid);
summary.PayloadMatchedPackets = sum(packets.PayloadMatch);
summary.HardSuccessPackets = sum(packets.HardSuccess);
summary.SoftSuccessPackets = sum(packets.SoftSuccess);
summary.SoftRecoveredPackets = sum(packets.SoftRecovered);
summary.PacketErrors = sum(packets.PacketError);
summary.PER = safe_ratio(summary.PacketErrors, summary.Transmissions);
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
report = struct("packets", packets, "summary", summary);
end

function pairing = pair_receptions(receptions, expectedPayloads)
packetCount = numel(expectedPayloads);
pairing = zeros(packetCount, 1);
used = false(numel(receptions), 1);
expectedSequences = nan(packetCount, 1);
for packet = 1:packetCount
    payload = uint8(expectedPayloads{packet}(:));
    if numel(payload) >= 8
        expectedSequences(packet) = double(typecast(payload(5:8), "uint32"));
    end
end

% Sequence is the strongest association key and remains usable even when
% the final payload CRC fails because it is carried inside the payload.
for candidate = 1:numel(receptions)
    payload = uint8(receptions(candidate).decoded.payload(:));
    if ~receptions(candidate).decoded.headerValid || numel(payload) < 8
        continue
    end
    sequence = double(typecast(payload(5:8), "uint32"));
    packet = find(expectedSequences == sequence & pairing == 0, 1);
    if ~isempty(packet)
        pairing(packet) = candidate;
        used(candidate) = true;
    end
end

% A corrupted sequence cannot be used as a key. Pair only plausible LoRa
% receptions with the remaining expected transmissions in time order;
% unrelated energy runs are deliberately ignored.
plausible = false(numel(receptions), 1);
for candidate = 1:numel(receptions)
    plausible(candidate) = receptions(candidate).preambleValid && ...
        receptions(candidate).syncValid || receptions(candidate).decoded.headerValid;
end
remainingCandidates = find(plausible & ~used);
remainingPackets = find(pairing == 0);
pairCount = min(numel(remainingCandidates), numel(remainingPackets));
for index = 1:pairCount
    pairing(remainingPackets(index)) = remainingCandidates(index);
end
end

function errors = bit_errors(expected, received)
differences = bitxor(expected, received);
errors = sum(lora_phy.integers_to_bits(differences, 8), "all");
end

function value = safe_ratio(numerator, denominator)
if denominator == 0
    value = NaN;
else
    value = numerator/denominator;
end
end

function row = empty_row()
row = struct("PacketIndex", 0, "CandidatePresent", false, ...
    "HardSuccess", false, "SoftSuccess", false, "SoftRecovered", false, ...
    "DecoderMethod", "none", ...
    "Acquired", false, "HeaderValid", false, "CrcChecked", false, ...
    "CrcValid", false, "PayloadLengthValid", false, ...
    "PayloadMatch", false, "PacketError", true, "ExpectedLength", 0, ...
    "DecodedLength", 0, "PreFecBitErrors", 0, "PreFecBits", 0, ...
    "ComparedPayloadBitErrors", 0, "ComparedPayloadBits", 0, ...
    "PayloadBitErrors", 0, "PayloadBits", 0);
end
