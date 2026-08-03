function results = decode_reference_sweep(datasetDirectory, options)
%DECODE_REFERENCE_SWEEP Decode the curated Heltec/SX1262 IQ data set.

arguments
    datasetDirectory (1,1) string
    options.SelectedNames (:,1) string = strings(0, 1)
    options.OutputCsv (1,1) string = ""
    options.PlotDirectory (1,1) string = ""
end

manifest = jsondecode(fileread(fullfile(datasetDirectory, "manifest.json")));
captures = manifest.captures;
rows = repmat(empty_row(), 0, 1);
for index = 1:numel(captures)
    item = captures(index);
    name = string(item.name);
    if ~isempty(options.SelectedNames) && ~ismember(name, options.SelectedNames)
        continue
    end
    row = empty_row();
    row.Name = name;
    row.SF = item.transmitter.spreading_factor;
    row.BandwidthHz = item.transmitter.bandwidth_hz;
    row.CodingRate = item.transmitter.coding_rate_denominator;
    row.ExpectedLength = item.transmitter.payload_length;
    capturePath = fullfile(datasetDirectory, string(item.capture.path));
    try
        [iq, ~] = lora_phy.load_iq_capture(capturePath, "cf32");
        syncWord = hex2dec(extractAfter(string(item.transmitter.sync_word), "0x"));
        reception = lora_phy.receive_lora_packet(iq, ...
            item.receiver.sample_rate_hz, item.transmitter.bandwidth_hz, ...
            item.transmitter.spreading_factor, ...
            PreambleSymbols=item.transmitter.preamble_symbols, ...
            SyncWord=syncWord, IqInverted=item.transmitter.iq_inverted, ...
            ExpectedCarrierOffsetHz=item.transmitter.frequency_hz- ...
                item.receiver.center_frequency_hz);
        row.Success = reception.success;
        row.PreambleValid = reception.preambleValid;
        row.SyncValid = reception.syncValid;
        row.HeaderValid = reception.decoded.headerValid;
        row.CrcValid = reception.decoded.crcValid;
        row.DecodedLength = numel(reception.decoded.payload);
        row.CfoHz = reception.inspection.estimatedCarrierOffsetHz;
        row.ResidualCfoHz = reception.inspection.residualCfoHz;
        row.FailureReason = string(reception.decoded.failureReason);
        if numel(reception.decoded.payload) >= 8
            prefix = char(reception.decoded.payload(1:4).');
            prefix(prefix < 32 | prefix > 126) = '.';
            row.Prefix = string(prefix);
            row.Sequence = double(typecast(uint8( ...
                reception.decoded.payload(5:8)), "uint32"));
        end
        if options.PlotDirectory ~= "" && reception.success
            plotPath = fullfile(options.PlotDirectory, name+"-decode.png");
            figureHandle = lora_phy.visualize_lora_packet(iq, ...
                item.receiver.sample_rate_hz, reception, ...
                OutputPath=plotPath, Visible=false);
            close(figureHandle);
        end
    catch exception
        row.FailureReason = string(exception.identifier)+": "+string(exception.message);
    end
    rows(end+1, 1) = row; %#ok<AGROW>
    fprintf("%-22s success=%d header=%d crc=%d %s\n", name, ...
        row.Success, row.HeaderValid, row.CrcValid, row.FailureReason);
end
results = struct2table(rows);
if options.OutputCsv ~= ""
    outputDirectory = fileparts(options.OutputCsv);
    if outputDirectory ~= "" && ~isfolder(outputDirectory)
        mkdir(outputDirectory);
    end
    writetable(results, options.OutputCsv);
end
end

function row = empty_row()
row = struct("Name", "", "SF", 0, "BandwidthHz", 0, ...
    "CodingRate", 0, "ExpectedLength", 0, "Success", false, ...
    "PreambleValid", false, "SyncValid", false, "HeaderValid", false, ...
    "CrcValid", false, "DecodedLength", 0, "Prefix", "", ...
    "Sequence", NaN, "CfoHz", NaN, "ResidualCfoHz", NaN, ...
    "FailureReason", "");
end
