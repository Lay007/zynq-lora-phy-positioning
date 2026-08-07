function result = evaluate_reference_toa( ...
    datasetDirectory, captureName, options)
%EVALUATE_REFERENCE_TOA Measure fixed-geometry ToA repeatability from IQ.
%
% The TX millisecond counter and RX sample counter have unrelated epochs.
% An affine fit removes epoch and linear clock-scale error; the remaining
% residual describes complete-chain repeatability, not propagation delay.

arguments
    datasetDirectory (1,1) string
    captureName (1,1) string
    options.OutputDirectory (1,1) string = ""
    options.SearchRadiusSamples (1,1) double ...
        {mustBeInteger, mustBePositive} = 8
end

manifest = jsondecode(fileread(fullfile(datasetDirectory, "manifest.json")));
names = string({manifest.captures.name});
captureIndex = find(names == captureName, 1);
if isempty(captureIndex)
    error("lora_phy:UnknownCapture", ...
        "Capture '%s' is not present in the manifest", captureName);
end
item = manifest.captures(captureIndex);
tx = item.transmitter;
receiver = item.receiver;
capturePath = fullfile(datasetDirectory, string(item.capture.path));
[iq, ~] = lora_phy.load_iq_capture(capturePath, "cf32");
syncWord = hex2dec(extractAfter(string(tx.sync_word), "0x"));
receptionSet = lora_phy.receive_lora_packets(iq, ...
    receiver.sample_rate_hz, tx.bandwidth_hz, tx.spreading_factor, ...
    PreambleSymbols=tx.preamble_symbols, SyncWord=syncWord, ...
    IqInverted=tx.iq_inverted, ...
    ExpectedCarrierOffsetHz=tx.frequency_hz-receiver.center_frequency_hz);

[sequences, txStartMilliseconds] = parse_transmissions(item.transmissions);
css = lora_phy.css_config(tx.spreading_factor, ...
    receiver.sample_rate_hz/tx.bandwidth_hz);
reference = repmat(lora_phy.reference_chirp(css, "up"), ...
    tx.preamble_symbols, 1);
rows = repmat(empty_row(), 0, 1);
for receptionIndex = 1:numel(receptionSet.receptions)
    reception = receptionSet.receptions(receptionIndex);
    payload = uint8(reception.decoded.payload(:));
    if ~reception.decoded.success || numel(payload) < 8 || ...
            ~isequal(payload(1:4), uint8('ZLP1').')
        continue
    end
    sequence = double(typecast(payload(5:8), "uint32"));
    transmissionIndex = find(sequences == sequence, 1);
    if isempty(transmissionIndex)
        continue
    end

    guard = options.SearchRadiusSamples;
    localStart = max(1, reception.preambleStartIndex-guard);
    localEnd = min(numel(iq), reception.preambleStartIndex+ ...
        numel(reference)+guard-1);
    sampleAxis = (localStart-1:localEnd-1).';
    corrected = iq(localStart:localEnd).*exp(-2j*pi* ...
        reception.inspection.estimatedCarrierOffsetHz*sampleAxis/ ...
        receiver.sample_rate_hz);
    toa = lora_phy.estimate_fractional_toa(corrected, reference, ...
        receiver.sample_rate_hz, ...
        CoarseStartIndex=reception.preambleStartIndex-localStart+1, ...
        SearchRadiusSamples=guard);

    row = empty_row();
    row.Sequence = sequence;
    row.TxStartMilliseconds = txStartMilliseconds(transmissionIndex);
    row.RxToaSamples = localStart-1+toa.toaSamples;
    row.PeakScore = toa.peakScore;
    row.PeakToSidelobeDb = toa.peakToSidelobeDb;
    rows(end+1, 1) = row; %#ok<AGROW>
end
if numel(rows) < 3
    error("lora_phy:InsufficientToaPackets", ...
        "At least three decoded counter packets are required for ToA fitting");
end

trials = struct2table(rows);
fitCoefficients = polyfit( ...
    trials.TxStartMilliseconds, trials.RxToaSamples, 1);
trials.FittedRxToaSamples = polyval( ...
    fitCoefficients, trials.TxStartMilliseconds);
trials.ResidualSamples = ...
    trials.RxToaSamples-trials.FittedRxToaSamples;
absoluteResidual = sort(abs(trials.ResidualSamples));
p95Index = max(1, ceil(0.95*numel(absoluteResidual)));

summary = struct;
summary.Schema = "zynq-lora-toa-repeatability-v1";
summary.CaptureName = captureName;
summary.Transmissions = numel(item.transmissions);
summary.MatchedPackets = height(trials);
summary.SampleRateHz = receiver.sample_rate_hz;
summary.SlopeSamplesPerMillisecond = fitCoefficients(1);
nominalSlope = receiver.sample_rate_hz/1000;
summary.ClockScaleErrorPpm = ...
    (fitCoefficients(1)/nominalSlope-1)*1e6;
summary.BiasRemoved = true;
summary.ResidualMeanSamples = mean(trials.ResidualSamples);
summary.ResidualStdSamples = std(trials.ResidualSamples);
summary.ResidualRmsSamples = sqrt(mean(trials.ResidualSamples.^2));
summary.ResidualP95AbsoluteSamples = absoluteResidual(p95Index);
summary.ResidualStdMicroseconds = ...
    summary.ResidualStdSamples/receiver.sample_rate_hz*1e6;
summary.Scope = "Fixed-geometry OTA repeatability; " + ...
    "not absolute propagation-delay calibration";

result = struct("trials", trials, "summary", summary, ...
    "receptions", receptionSet);
if options.OutputDirectory ~= ""
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(trials, fullfile(options.OutputDirectory, ...
        "toa-repeatability.csv"));
    jsonPath = fullfile(options.OutputDirectory, "toa-summary.json");
    file = fopen(jsonPath, "w");
    if file < 0
        error("lora_phy:CannotCreateReport", "Cannot create %s", jsonPath);
    end
    cleanup = onCleanup(@() fclose(file));
    fwrite(file, jsonencode(summary, PrettyPrint=true), "char");
    fwrite(file, newline, "char");
    clear cleanup
end
end

function [sequences, startMilliseconds] = parse_transmissions(transmissions)
sequences = zeros(numel(transmissions), 1);
startMilliseconds = zeros(numel(transmissions), 1);
for index = 1:numel(transmissions)
    tokens = regexp(string(transmissions(index).radio_log), ...
        "TX seq=(\d+) len=(\d+) state=(-?\d+) start_ms=(\d+)", ...
        "tokens", "once");
    if isempty(tokens) || str2double(tokens{3}) ~= 0
        error("lora_phy:InvalidTxLog", ...
            "Cannot parse a successful transmission log");
    end
    sequences(index) = str2double(tokens{1});
    startMilliseconds(index) = str2double(tokens{4});
end
end

function row = empty_row()
row = struct("Sequence", 0, "TxStartMilliseconds", 0, ...
    "RxToaSamples", 0, "PeakScore", 0, "PeakToSidelobeDb", 0);
end
