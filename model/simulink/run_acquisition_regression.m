function report = run_acquisition_regression(options)
%RUN_ACQUISITION_REGRESSION Check the acquisition FSM against MATLAB.
%
% The DUT is a streaming state machine and the MATLAB reference is a
% one-shot function over the same bins, so the comparison is between the
% decision the FSM emits after the last sync symbol and the decision
% LORA_PHY.VALIDATE_ACQUISITION_BINS makes on the same sequence.
%
% Sequences cover the cases that matter: exact acquisition, drift inside
% tolerance, drift outside it on the preamble, drift outside it on the sync
% word, wrap-around at bin 0, and seeded random sequences that are almost
% always rejections. Comparison is exact equality; nothing here rounds.

arguments
    options.Configurations (:,2) double = [7, 8; 5, 8; 9, 6]
    options.RandomSequences (1,1) double = 200
    options.RandomSeed (1,1) double = 20260809
    options.SyncWord (1,1) double = hex2dec("12")
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
    n = config.symbolCount;
    sequenceLength = preambleSymbols+2;

    sequences = buildSequences(n, preambleSymbols, options.SyncWord, ...
        options.RandomSequences, options.RandomSeed+spreadingFactor);

    expectedValid = false(size(sequences, 2), 1);
    expectedPreamble = false(size(sequences, 2), 1);
    for s = 1:size(sequences, 2)
        check = lora_phy.validate_acquisition_bins( ...
            sequences(1:preambleSymbols, s), ...
            sequences(preambleSymbols+(1:2), s), options.SyncWord, config);
        expectedValid(s) = check.valid;
        expectedPreamble(s) = check.preambleValid;
    end

    closeGeneratedModel(info);
    info = build_acquisition_model(SpreadingFactor=spreadingFactor, ...
        PreambleSymbols=preambleSymbols, ModelName="lora_acquisition_check");

    stream = sequences(:);
    total = numel(stream);
    timeAxis = (0:total-1).';
    assignin("base", "stimulusSymbolIndex", ...
        timeseries(uint16(stream), timeAxis));
    assignin("base", "stimulusSymbolValid", ...
        timeseries(true(total, 1), timeAxis));
    assignin("base", "stimulusSyncWord", ...
        timeseries(uint8(options.SyncWord)*ones(total, 1, "uint8"), timeAxis));
    resetVector = false(total, 1);
    assignin("base", "stimulusReset", timeseries(resetVector, timeAxis));

    if ~bdIsLoaded(info.modelName)
        load_system(info.modelPath);
    end
    set_param(info.modelName, StopTime=num2str(total-1));
    out = sim(info.modelName);

    % One decision per sequence, emitted on its last symbol.
    decisionSteps = (sequenceLength:sequenceLength:total).';
    actualValid = logical(out.syncValid(decisionSteps));
    actualFailed = logical(out.acquisitionFailed(decisionSteps));
    preambleSteps = (preambleSymbols:sequenceLength:total).';
    actualPreamble = logical(out.preambleDetected(preambleSteps));

    validMismatch = sum(actualValid ~= expectedValid);
    preambleMismatch = sum(actualPreamble ~= expectedPreamble);
    complementMismatch = sum(actualFailed ~= ~expectedValid);

    rows{end+1} = table(spreadingFactor, preambleSymbols, n, ...
        size(sequences, 2), sum(expectedValid), validMismatch, ...
        preambleMismatch, complementMismatch, ...
        VariableNames=["SF", "PreambleSymbols", "N", "Sequences", ...
        "AcceptedByMatlab", "SyncMismatches", "PreambleMismatches", ...
        "FailedFlagMismatches"]); %#ok<AGROW>

    total = validMismatch+preambleMismatch+complementMismatch;
    if total > 0
        failures(end+1, 1) = sprintf( ...
            "SF%d preamble=%d: %d mismatching decisions over %d sequences", ...
            spreadingFactor, preambleSymbols, total, ...
            size(sequences, 2)); %#ok<AGROW>
    end
    if options.Verbose
        fprintf("SF%-2d preamble=%-2d sequences=%-4d accepted=%-4d " + ...
            "mismatches=%d\n", spreadingFactor, preambleSymbols, ...
            size(sequences, 2), sum(expectedValid), total);
    end
end

closeGeneratedModel(info);

report = struct;
report.summary = vertcat(rows{:});
report.failures = failures;
report.passed = isempty(failures);
report.totalSequences = sum(report.summary.Sequences);

if options.WriteCsv
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(report.summary, fullfile(options.OutputDirectory, ...
        "simulink-m2-acquisition.csv"));
end

if options.Verbose
    fprintf("\n");
    disp(report.summary);
    if report.passed
        fprintf("Acquisition FSM matches MATLAB over %d sequences.\n", ...
            report.totalSequences);
    else
        fprintf("FAILURES:\n  %s\n", strjoin(failures, newline+"  "));
    end
end
end

function sequences = buildSequences(n, preambleSymbols, syncWord, ...
    randomCount, seed)
%BUILDSEQUENCES Deterministic acquisition sequences, accepted and rejected.
expectedSync = 8*[floor(syncWord/16); mod(syncWord, 16)];
blocks = {};

% Exact.
blocks{end+1} = [zeros(preambleSymbols, 1); expectedSync];
% Drift of one bin, inside tolerance, including wrap-around at bin 0.
drifted = [zeros(preambleSymbols, 1); expectedSync];
drifted(1) = 1;
drifted(2) = n-1;
drifted(end) = expectedSync(2)+1;
blocks{end+1} = drifted;
% Preamble outside tolerance.
bad = [zeros(preambleSymbols, 1); expectedSync];
bad(3) = 2;
blocks{end+1} = bad;
% Sync outside tolerance.
bad = [zeros(preambleSymbols, 1); expectedSync];
bad(end) = mod(expectedSync(2)+2, n);
blocks{end+1} = bad;
% Wrong sync word entirely.
blocks{end+1} = [zeros(preambleSymbols, 1); ...
    mod(expectedSync+n/2, n)];

rng(seed, "twister");
for k = 1:randomCount
    blocks{end+1} = randi([0, n-1], preambleSymbols+2, 1); %#ok<AGROW>
end

sequences = double(cat(2, blocks{:}));
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
