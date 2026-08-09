function report = run_blind_detector_regression(options)
%RUN_BLIND_DETECTOR_REGRESSION Check the blind detector against MATLAB.
%
% Unlike the acquisition FSM, which frames the symbol stream into groups and
% emits one decision per group, this DUT slides: it re-evaluates the
% predicate on every symbol. So the comparison is per symbol, not per
% sequence, and covers every one of the DUT's four outputs.
%
% The stimulus is built from two sources:
%
% * Correlator bins from real streams. Packets are placed at sample offsets
%   that are deliberately not multiples of the oversampling factor, with
%   noise and carrier frequency offset, and pushed through the same
%   free-running correlator the hardware would run. These exercise
%   detection.
% * Seeded random bins and hand-built edge sequences. These exercise
%   rejection, the wrap at bin 0, and sync targets that overflow past N.
%
% All 256 sync words are swept on one configuration, because the sync target
% is where the DUT and the reference could most easily disagree: the DUT
% masks with N-1 where the reference uses mod().
%
% Comparison is exact equality. Nothing here rounds, so any difference is a
% defect rather than a tolerance question.

arguments
    options.Configurations (:,2) double = [7, 8; 5, 8; 9, 6]
    options.RandomSymbols (1,1) double = 400
    options.RandomSeed (1,1) double = 20260809
    options.SyncWord (1,1) double = hex2dec("12")
    options.SweepSyncWords (1,1) logical = true
    options.OutputDirectory string = string.empty
    options.WriteCsv (1,1) logical = true
    options.Verbose (1,1) logical = true
end

simulinkRoot = fileparts(mfilename("fullpath"));
repositoryRoot = fileparts(fileparts(simulinkRoot));
addpath(simulinkRoot);
addpath(fullfile(repositoryRoot, "model", "matlab"));
if isempty(options.OutputDirectory)
    options.OutputDirectory = string(fullfile(repositoryRoot, "docs", "data"));
end

rows = {};
failures = strings(0, 1);
info = struct.empty;

for k = 1:size(options.Configurations, 1)
    spreadingFactor = options.Configurations(k, 1);
    preambleSymbols = options.Configurations(k, 2);
    config = lora_phy.css_config(spreadingFactor, 1);
    runLength = preambleSymbols+2;

    [bins, packetRanges] = buildBinStream(spreadingFactor, ...
        preambleSymbols, options.SyncWord, options.RandomSymbols, ...
        options.RandomSeed+spreadingFactor);
    total = numel(bins);

    closeGeneratedModel(info);
    info = build_blind_detector_model(SpreadingFactor=spreadingFactor, ...
        PreambleSymbols=preambleSymbols, ...
        ModelName="lora_blind_detector_check");

    [actual, expected] = compareOnStream(info, bins, ...
        options.SyncWord*ones(total, 1), config, preambleSymbols);

    detectedMismatch = sum(actual.detected ~= expected.detected) ...
        +sum(actual.preambleDetected ~= expected.preambleDetected) ...
        +sum(actual.syncValid ~= expected.syncValid);
    binMismatch = sum(actual.preambleBin ~= expected.preambleBin);
    chipMismatch = sum(actual.chipsToBoundary ~= expected.chipsToBoundary);
    detections = sum(expected.detected);

    % A regression that compares two always-false vectors proves nothing:
    % every placed packet must actually be found by the DUT itself. The
    % requirement is on the preamble, which is what this stage is for. Sync
    % on the free-running grid is measured, not required, because a window
    % straddling the preamble-to-sync boundary can lose the first sync
    % symbol to the stronger half of its own window.
    packetsFound = 0;
    packetsSynced = 0;
    for p = 1:size(packetRanges, 1)
        span = packetRanges(p, 1):packetRanges(p, 2);
        packetsFound = packetsFound+any(actual.preambleDetected(span));
        packetsSynced = packetsSynced+any(actual.detected(span));
    end
    if packetsFound < size(packetRanges, 1)
        failures(end+1, 1) = sprintf( ...
            "SF%d: preamble found in %d of %d placed packets", ...
            spreadingFactor, packetsFound, size(packetRanges, 1)); %#ok<AGROW>
    end

    syncMismatch = 0;
    syncWordsSwept = 0;
    if options.SweepSyncWords && k == 1
        [syncMismatch, syncWordsSwept] = sweepSyncWords(info, config, ...
            preambleSymbols, options.RandomSeed);
    end

    rows{end+1} = table(spreadingFactor, preambleSymbols, ...
        config.symbolCount, total, runLength, ...
        size(packetRanges, 1), packetsFound, packetsSynced, detections, ...
        detectedMismatch, binMismatch, chipMismatch, syncWordsSwept, ...
        syncMismatch, ...
        VariableNames=["SF", "PreambleSymbols", "N", "Symbols", ...
        "RunLength", "PlacedPackets", "PreambleFound", ...
        "SyncOnFreeGrid", "Detections", "DecisionMismatches", ...
        "PreambleBinMismatches", "ChipsToBoundaryMismatches", ...
        "SyncWordsSwept", "SyncWordMismatches"]); %#ok<AGROW>

    mismatches = detectedMismatch+binMismatch+chipMismatch+syncMismatch;
    if mismatches > 0
        failures(end+1, 1) = sprintf( ...
            "SF%d preamble=%d: %d mismatching outputs over %d symbols", ...
            spreadingFactor, preambleSymbols, mismatches, total); %#ok<AGROW>
    end
    if options.Verbose
        fprintf("SF%-2d preamble=%-2d symbols=%-5d preamble=%d/%d " + ...
            "sync=%d/%d mismatches=%d\n", spreadingFactor, ...
            preambleSymbols, total, packetsFound, size(packetRanges, 1), ...
            packetsSynced, size(packetRanges, 1), mismatches);
    end
end

closeGeneratedModel(info);

report = struct;
report.summary = vertcat(rows{:});
report.offsets = sweepOffsets(options.SyncWord);
report.failures = failures;
report.passed = isempty(failures);
report.totalSymbols = sum(report.summary.Symbols);
report.totalDetections = sum(report.summary.Detections);
report.preambleRate = mean(report.offsets.PreambleDetected);
report.syncRate = mean(report.offsets.SyncOnFreeGrid);

% The sweep is noiseless, so a preamble miss there would mean the detector
% is alignment-dependent in a way the derivation says it must not be.
if report.preambleRate < 1
    failures(end+1, 1) = sprintf( ...
        "offset sweep: preamble found at only %.0f%% of alignments", ...
        100*report.preambleRate);
    report.failures = failures;
    report.passed = false;
end
if any(report.offsets.ChipsToBoundaryError > 1)
    failures(end+1, 1) = sprintf( ...
        "offset sweep: chipsToBoundary off by up to %d chips", ...
        max(report.offsets.ChipsToBoundaryError));
    report.failures = failures;
    report.passed = false;
end

if options.WriteCsv
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(report.summary, fullfile(options.OutputDirectory, ...
        "simulink-m2-blind-detector.csv"));
    writetable(report.offsets, fullfile(options.OutputDirectory, ...
        "simulink-m2-blind-detector-offsets.csv"));
end

if options.Verbose
    fprintf("\n");
    disp(report.summary);
    fprintf("Alignment sweep over one symbol (%d offsets, noiseless): " + ...
        "preamble %.0f%%, sync on the free-running grid %.0f%%.\n", ...
        height(report.offsets), 100*report.preambleRate, ...
        100*report.syncRate);
    if report.passed
        fprintf("Blind detector matches MATLAB over %d symbols " + ...
            "(%d detections).\n", report.totalSymbols, ...
            report.totalDetections);
    else
        fprintf("FAILURES:\n  %s\n", strjoin(report.failures, ...
            newline+"  "));
    end
end
end

function [actual, expected] = compareOnStream(info, bins, syncWords, ...
    config, preambleSymbols)
%COMPAREONSTREAM Run the DUT over a bin stream and evaluate the reference.
total = numel(bins);
runLength = preambleSymbols+2;
timeAxis = (0:total-1).';

assignin("base", "stimulusSymbolIndex", timeseries(uint16(bins), timeAxis));
assignin("base", "stimulusSymbolValid", timeseries(true(total, 1), timeAxis));
assignin("base", "stimulusSyncWord", ...
    timeseries(uint8(syncWords), timeAxis));
assignin("base", "stimulusReset", timeseries(false(total, 1), timeAxis));

if ~bdIsLoaded(info.modelName)
    load_system(info.modelPath);
end
set_param(info.modelName, StopTime=num2str(total-1));
out = sim(info.modelName);

actual = struct;
actual.detected = logical(out.detected(:));
actual.preambleDetected = logical(out.preambleDetected(:));
actual.syncValid = logical(out.syncValid(:));
actual.preambleBin = double(out.preambleBin(:));
actual.chipsToBoundary = double(out.chipsToBoundary(:));
actual.binsSeen = double(out.binsSeen(:));

expected = struct;
expected.detected = false(total, 1);
expected.preambleDetected = false(total, 1);
expected.syncValid = false(total, 1);
expected.preambleBin = zeros(total, 1);
expected.chipsToBoundary = zeros(total, 1);
for t = runLength:total
    window = bins(t-runLength+1:t);
    result = lora_phy.detect_preamble_run(window, syncWords(t), config, ...
        PreambleSymbols=preambleSymbols);
    expected.detected(t) = result.valid;
    expected.preambleDetected(t) = result.preambleValid;
    expected.syncValid(t) = result.syncValid;
    expected.preambleBin(t) = result.preambleBin;
    expected.chipsToBoundary(t) = result.chipsToBoundary;
end
end

function sweep = sweepOffsets(syncWord, spreadingFactor, samplesPerChip, ...
    preambleSymbols, steps)
%SWEEPOFFSETS Detection against alignment, over one whole symbol.
%
% This quantifies the split between the two decisions. The stream is
% noiseless, so alignment is the only variable: a preamble miss here would
% contradict the derivation, while a sync miss is the straddle case and is
% expected near half a symbol. Evaluated against the MATLAB reference, which
% the Simulink comparison above has already shown to be bit-exact.
arguments
    syncWord (1,1) double
    spreadingFactor (1,1) double = 7
    samplesPerChip (1,1) double = 4
    preambleSymbols (1,1) double = 8
    steps (1,1) double = 32
end

phy = lora_phy.phy_config(spreadingFactor, samplesPerChip, 1);
css = lora_phy.css_config(spreadingFactor, samplesPerChip);
m = css.samplesPerSymbol;
n = css.symbolCount;
runLength = preambleSymbols+2;
packet = lora_phy.build_lora_packet(uint8((1:16).'), phy, ...
    PreambleSymbols=preambleSymbols, SyncWord=syncWord);

offsets = round(linspace(0, m-1, steps)).';
rows = cell(numel(offsets), 1);
for k = 1:numel(offsets)
    lead = 3*m+offsets(k);
    stream = [complex(zeros(lead, 1)); packet; complex(zeros(4*m, 1))];
    windows = floor(numel(stream)/m);
    stages = lora_phy.fft_correlator_stages(stream(1:windows*m), css);
    bins = double(stages.symbols(:));

    preambleHit = false;
    syncHit = false;
    chipError = NaN;
    for s = 1:numel(bins)-runLength+1
        result = lora_phy.detect_preamble_run(bins(s+(0:runLength-1)), ...
            syncWord, css, PreambleSymbols=preambleSymbols);
        if result.preambleValid && ~preambleHit
            preambleHit = true;
            % Chips the window grid must advance to reach the boundary.
            windowStart = (s-1)*m;
            trueChips = mod(lead-windowStart, m)/samplesPerChip;
            delta = mod(result.chipsToBoundary-trueChips+n/2, n)-n/2;
            chipError = abs(delta);
        end
        syncHit = syncHit || result.valid;
    end

    rows{k} = table(spreadingFactor, samplesPerChip, offsets(k), ...
        offsets(k)/samplesPerChip, preambleHit, syncHit, chipError, ...
        VariableNames=["SF", "SamplesPerChip", "OffsetSamples", ...
        "OffsetChips", "PreambleDetected", "SyncOnFreeGrid", ...
        "ChipsToBoundaryError"]);
end
sweep = vertcat(rows{:});
end

function [mismatches, syncWordsSwept] = sweepSyncWords(info, config, ...
    preambleSymbols, seed)
%SWEEPSYNCWORDS Every sync word against a preamble bin that forces a wrap.
% The DUT reduces the sync target with a bitmask and the reference uses
% mod(); a disagreement would show up as an accepted word being rejected.
n = config.symbolCount;
rng(seed, "twister");
bins = [];
syncWords = [];
for syncWord = 0:255
    preambleBin = randi([0, n-1]);
    nibbles = [floor(syncWord/16); mod(syncWord, 16)];
    block = [repmat(preambleBin, preambleSymbols, 1); ...
        mod(preambleBin+8*nibbles, n)];
    bins = [bins; block]; %#ok<AGROW>
    syncWords = [syncWords; repmat(syncWord, numel(block), 1)]; %#ok<AGROW>
end

[actual, expected] = compareOnStream(info, bins, syncWords, config, ...
    preambleSymbols);
mismatches = sum(actual.detected ~= expected.detected) ...
    +sum(actual.preambleBin ~= expected.preambleBin) ...
    +sum(actual.chipsToBoundary ~= expected.chipsToBoundary);
syncWordsSwept = 256;
end

function [bins, packetRanges] = buildBinStream(spreadingFactor, ...
    preambleSymbols, syncWord, randomSymbols, seed)
%BUILDBINSTREAM Correlator bins from placed packets, plus adversarial bins.
samplesPerChip = 4;
phy = lora_phy.phy_config(spreadingFactor, samplesPerChip, 1);
css = lora_phy.css_config(spreadingFactor, samplesPerChip);
m = css.samplesPerSymbol;
n = css.symbolCount;

% Offsets are deliberately not multiples of samplesPerChip: blind detection
% must not quietly assume chip alignment.
placements = struct( ...
    "offset", {0, 137, m/2+3, m-1}, ...
    "cfoBins", {0, 0, 3, 1}, ...
    "snr", {Inf, -5, 0, -10});

segments = {};
packetRanges = zeros(numel(placements), 2);
cursor = 0;
for k = 1:numel(placements)
    packet = lora_phy.build_lora_packet(uint8(mod((1:16).'+k, 256)), phy, ...
        PreambleSymbols=preambleSymbols, SyncWord=syncWord);
    lead = 3*m+placements(k).offset;
    stream = [complex(zeros(lead, 1)); packet; complex(zeros(4*m, 1))];
    if placements(k).cfoBins ~= 0
        index = (0:numel(stream)-1).';
        stream = stream.*exp(1j*2*pi*placements(k).cfoBins*index/m);
    end
    if isfinite(placements(k).snr)
        stream = lora_phy.add_awgn(stream, placements(k).snr, 100+k);
    end
    windows = floor(numel(stream)/m);
    stages = lora_phy.fft_correlator_stages(stream(1:windows*m), css);
    segment = double(stages.symbols(:));
    segments{end+1} = segment; %#ok<AGROW>
    packetRanges(k, :) = [cursor+1, cursor+numel(segment)];
    cursor = cursor+numel(segment);
end

% Edge cases the placed packets are unlikely to produce on their own.
nibbles = [floor(syncWord/16); mod(syncWord, 16)];
for preambleBin = [0, 1, n-1, n-8]
    segments{end+1} = [repmat(preambleBin, preambleSymbols, 1); ...
        mod(preambleBin+8*nibbles, n)]; %#ok<AGROW>
end

rng(seed, "twister");
segments{end+1} = randi([0, n-1], randomSymbols, 1);

bins = double(cat(1, segments{:}));
end

function closeGeneratedModel(info)
if isempty(info) || ~isfield(info, "modelName")
    return;
end
if bdIsLoaded(info.modelName)
    set_param(info.modelName, Dirty="off");
    close_system(info.modelName, 0);
end
end
