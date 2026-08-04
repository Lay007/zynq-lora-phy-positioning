function report = evaluate_reference_sweep(datasetDirectory, options)
%EVALUATE_REFERENCE_SWEEP Produce packet-level BER/PER reports for IQ data.

arguments
    datasetDirectory (1,1) string
    options.SelectedNames (:,1) string = strings(0, 1)
    options.OutputDirectory (1,1) string = ""
    options.SoftDecoding (1,1) logical = true
end
manifest = jsondecode(fileread(fullfile(datasetDirectory, "manifest.json")));
caseRows = repmat(empty_case_row(), 0, 1);
packetTables = cell(0, 1);
for index = 1:numel(manifest.captures)
    item = manifest.captures(index);
    name = string(item.name);
    if ~isempty(options.SelectedNames) && ~ismember(name, options.SelectedNames)
        continue
    end
    capturePath = fullfile(datasetDirectory, string(item.capture.path));
    [iq, ~] = lora_phy.load_iq_capture(capturePath, "cf32");
    syncWord = hex2dec(extractAfter(string(item.transmitter.sync_word), "0x"));
    receptionSet = lora_phy.receive_lora_packets(iq, ...
        item.receiver.sample_rate_hz, item.transmitter.bandwidth_hz, ...
        item.transmitter.spreading_factor, ...
        PreambleSymbols=item.transmitter.preamble_symbols, ...
        SyncWord=syncWord, IqInverted=item.transmitter.iq_inverted, ...
        ExpectedCarrierOffsetHz=item.transmitter.frequency_hz- ...
            item.receiver.center_frequency_hz, ...
        SoftDecoding=options.SoftDecoding);

    [expectedPayloads, sequences, startMilliseconds] = ...
        expected_payloads(item.transmissions, item.transmitter.payload_length);
    config = lora_phy.phy_config(item.transmitter.spreading_factor, ...
        item.receiver.sample_rate_hz/item.transmitter.bandwidth_hz, ...
        item.transmitter.coding_rate_denominator-4);
    config.payloadCrc = item.transmitter.crc_enabled;
    config.lowDataRateOptimization = ...
        2^item.transmitter.spreading_factor/item.transmitter.bandwidth_hz >= 16e-3;
    evaluation = lora_phy.evaluate_packet_receptions( ...
        receptionSet.receptions, expectedPayloads, config);
    packets = evaluation.packets;
    packets.Name = repmat(name, height(packets), 1);
    packets.Sequence = sequences;
    packets.StartMilliseconds = startMilliseconds;
    packets = movevars(packets, ["Name", "Sequence", "StartMilliseconds"], ...
        "Before", 1);
    packetTables{end+1, 1} = packets; %#ok<AGROW>

    summary = evaluation.summary;
    caseRow = empty_case_row();
    caseRow.Name = name;
    caseRow.SF = item.transmitter.spreading_factor;
    caseRow.BandwidthHz = item.transmitter.bandwidth_hz;
    caseRow.CodingRate = item.transmitter.coding_rate_denominator;
    caseRow.Transmissions = summary.Transmissions;
    caseRow.ActivityCandidates = receptionSet.candidateCount;
    caseRow.AcquiredPackets = summary.AcquiredPackets;
    caseRow.HeaderValidPackets = summary.HeaderValidPackets;
    caseRow.CrcValidPackets = summary.CrcValidPackets;
    caseRow.PayloadMatchedPackets = summary.PayloadMatchedPackets;
    caseRow.SoftRecoveredPackets = summary.SoftRecoveredPackets;
    caseRow.PacketErrors = summary.PacketErrors;
    caseRow.PER = summary.PER;
    caseRow.PreFecBitErrors = summary.PreFecBitErrors;
    caseRow.PreFecBits = summary.PreFecBits;
    caseRow.PreFecBER = summary.PreFecBER;
    caseRow.PayloadBitErrors = summary.PayloadBitErrors;
    caseRow.PayloadBits = summary.PayloadBits;
    caseRow.PayloadBER = summary.PayloadBER;
    caseRows(end+1, 1) = caseRow; %#ok<AGROW>
    fprintf("%-22s packets=%d/%d PER=%.3g payload_errors=%d\n", ...
        name, summary.PayloadMatchedPackets, summary.Transmissions, ...
        summary.PER, summary.PayloadBitErrors);
end

if isempty(packetTables)
    packetTable = table;
else
    packetTable = vertcat(packetTables{:});
end
caseTable = struct2table(caseRows);
aggregate = aggregate_rows(packetTable);
report = struct("packets", packetTable, "cases", caseTable, ...
    "aggregate", aggregate);

if options.OutputDirectory ~= ""
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(packetTable, fullfile(options.OutputDirectory, ...
        "packet-performance.csv"));
    writetable(caseTable, fullfile(options.OutputDirectory, ...
        "case-performance.csv"));
    jsonPath = fullfile(options.OutputDirectory, "performance-summary.json");
    file = fopen(jsonPath, "w");
    if file < 0
        error("lora_phy:CannotCreateReport", "Cannot create %s", jsonPath);
    end
    cleanup = onCleanup(@() fclose(file));
    fwrite(file, jsonencode(aggregate, PrettyPrint=true), "char");
    fwrite(file, newline, "char");
    clear cleanup
end
end

function [payloads, sequences, startMilliseconds] = ...
    expected_payloads(transmissions, payloadLength)
payloads = cell(numel(transmissions), 1);
sequences = zeros(numel(transmissions), 1);
startMilliseconds = zeros(numel(transmissions), 1);
for index = 1:numel(transmissions)
    tokens = regexp(string(transmissions(index).radio_log), ...
        "TX seq=(\d+) len=(\d+) state=(-?\d+) start_ms=(\d+)", ...
        "tokens", "once");
    if isempty(tokens)
        error("lora_phy:InvalidTxLog", "Cannot parse TX log");
    end
    sequence = str2double(tokens{1});
    loggedLength = str2double(tokens{2});
    state = str2double(tokens{3});
    startMs = str2double(tokens{4});
    if state ~= 0 || loggedLength ~= payloadLength
        error("lora_phy:UnexpectedTxLog", ...
            "TX log state or payload length differs from manifest");
    end
    sequences(index) = sequence;
    startMilliseconds(index) = startMs;
    payloads{index} = lora_phy.counter_payload(sequence, startMs, payloadLength);
end
end

function aggregate = aggregate_rows(packets)
aggregate = struct;
aggregate.Schema = "zynq-lora-packet-performance-v1";
aggregate.Transmissions = height(packets);
aggregate.AcquiredPackets = sum(packets.Acquired);
aggregate.HeaderValidPackets = sum(packets.HeaderValid);
aggregate.CrcCheckedPackets = sum(packets.CrcChecked);
aggregate.CrcValidPackets = sum(packets.CrcChecked & packets.CrcValid);
aggregate.PayloadMatchedPackets = sum(packets.PayloadMatch);
aggregate.HardSuccessPackets = sum(packets.HardSuccess);
aggregate.SoftSuccessPackets = sum(packets.SoftSuccess);
aggregate.SoftRecoveredPackets = sum(packets.SoftRecovered);
aggregate.PacketErrors = sum(packets.PacketError);
aggregate.PER = safe_ratio(aggregate.PacketErrors, aggregate.Transmissions);
aggregate.PreFecBitErrors = sum(packets.PreFecBitErrors);
aggregate.PreFecBits = sum(packets.PreFecBits);
aggregate.PreFecBER = safe_ratio(aggregate.PreFecBitErrors, aggregate.PreFecBits);
aggregate.PayloadBitErrors = sum(packets.PayloadBitErrors);
aggregate.PayloadBits = sum(packets.PayloadBits);
aggregate.PayloadBER = safe_ratio(aggregate.PayloadBitErrors, aggregate.PayloadBits);
aggregate.ComparedPayloadBitErrors = sum(packets.ComparedPayloadBitErrors);
aggregate.ComparedPayloadBits = sum(packets.ComparedPayloadBits);
aggregate.ComparedPayloadBER = safe_ratio( ...
    aggregate.ComparedPayloadBitErrors, aggregate.ComparedPayloadBits);
end

function value = safe_ratio(numerator, denominator)
if denominator == 0
    value = NaN;
else
    value = numerator/denominator;
end
end

function row = empty_case_row()
row = struct("Name", "", "SF", 0, "BandwidthHz", 0, "CodingRate", 0, ...
    "Transmissions", 0, "ActivityCandidates", 0, "AcquiredPackets", 0, ...
    "HeaderValidPackets", 0, "CrcValidPackets", 0, ...
    "PayloadMatchedPackets", 0, "SoftRecoveredPackets", 0, ...
    "PacketErrors", 0, "PER", NaN, ...
    "PreFecBitErrors", 0, "PreFecBits", 0, "PreFecBER", NaN, ...
    "PayloadBitErrors", 0, "PayloadBits", 0, "PayloadBER", NaN);
end
