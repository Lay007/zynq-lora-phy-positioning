function report = run_frontend_regression(options)
%RUN_FRONTEND_REGRESSION Correlator, detector, and realignment as one loop.
%
% Every subsystem was already exact against MATLAB on its own. What this
% checks is the property that only exists once they are wired together: a
% packet placed at a sample offset the receiver is never told must end up
% demodulating to the same payload symbols as an aligned one.
%
% That is a stronger statement than "the blocks agree with MATLAB". It fails
% if the detector is right but too late, if the skip is computed with the
% wrong sign, or if realignment moves the timestamp without moving the FFT
% framing -- three things that per-block regressions all pass.
%
% Offsets are deliberately not multiples of the oversampling factor, so
% alignment is only ever recovered to within a chip and the payload has to
% survive the sub-chip remainder.

arguments
    options.SpreadingFactor (1,1) double = 7
    options.SamplesPerChip (1,1) double = 4
    options.PreambleSymbols (1,1) double = 8
    options.Offsets (1,:) double = [0, 137, 259, 511]
    options.PayloadSymbols (1,1) double = 10
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

phy = lora_phy.phy_config(options.SpreadingFactor, options.SamplesPerChip, 1);
config = lora_phy.css_config(options.SpreadingFactor, options.SamplesPerChip);
m = config.samplesPerSymbol;

info = build_receiver_frontend_model( ...
    SpreadingFactor=options.SpreadingFactor, ...
    SamplesPerChip=options.SamplesPerChip, ...
    PreambleSymbols=options.PreambleSymbols, ...
    ModelName="lora_receiver_frontend_check");
cleanup = onCleanup(@() closeIfLoaded(info.modelName));

packet = lora_phy.build_lora_packet(uint8((1:16).'), phy, ...
    PreambleSymbols=options.PreambleSymbols, SyncWord=options.SyncWord);

rows = {};
failures = strings(0, 1);
runs = struct([]);

for offset = options.Offsets
    run = simulateOffset(info, packet, m, offset, options.SyncWord);
    run.offset = offset;
    run.expectedSkip = mod(-run.preambleBin, config.symbolCount) ...
        *options.SamplesPerChip;
    runs = [runs; run]; %#ok<AGROW>
end

% The property is that every offset agrees on the payload, so it is stated
% directly rather than by indexing into an assumed packet layout: find the
% longest run of symbols common to all four and require it to be long.
% Symbols around the SFD are excluded automatically, which is correct --
% those windows are consumed by the realignment transition and are expected
% to differ.
referencePayload = longestCommonRun({runs.bins});

for k = 1:numel(runs)
    run = runs(k);
    matched = ~isnan(subsequenceIndex(run.bins, referencePayload)) ...
        && numel(referencePayload) >= options.PayloadSymbols;
    skipOk = run.skip == run.expectedSkip;

    rows{end+1} = table(options.SpreadingFactor, options.SamplesPerChip, ...
        run.offset, run.skip, run.expectedSkip, run.detectSymbol, ...
        numel(run.bins), numel(referencePayload), matched, ...
        VariableNames=["SF", "L", "OffsetSamples", "SkipSamples", ...
        "ExpectedSkip", "DetectedAtSymbol", "Symbols", ...
        "CommonPayloadSymbols", "PayloadMatchesAligned"]); %#ok<AGROW>

    if ~matched
        failures(end+1, 1) = sprintf( ...
            "offset %d: only %d payload symbols common to every offset", ...
            run.offset, numel(referencePayload)); %#ok<AGROW>
    end
    if ~skipOk
        failures(end+1, 1) = sprintf( ...
            "offset %d: skip %d does not match chipsToBoundary*L = %d", ...
            run.offset, run.skip, run.expectedSkip); %#ok<AGROW>
    end
    if options.Verbose
        fprintf("offset=%-5d skip=%-5d detect@%-4s common payload " + ...
            "symbols: %d\n", run.offset, run.skip, ...
            num2str(run.detectSymbol), numel(referencePayload));
    end
end

report = struct;
report.summary = vertcat(rows{:});
report.failures = failures;
report.passed = isempty(failures);
report.referencePayload = referencePayload(:).';

if options.WriteCsv
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(report.summary, fullfile(options.OutputDirectory, ...
        "simulink-m2-frontend.csv"));
end

if options.Verbose
    fprintf("\n");
    disp(report.summary);
    fprintf("reference payload: %s\n", mat2str(report.referencePayload));
    if report.passed
        fprintf("Front-end recovers the same payload from every offset.\n");
    else
        fprintf("FAILURES:\n  %s\n", strjoin(failures, newline+"  "));
    end
end
end

function run = simulateOffset(info, packet, m, offset, syncWord)
%SIMULATEOFFSET Drive one placed packet through the composed front-end.
lead = 3*m+offset;
waveform = [complex(zeros(lead, 1)); packet; complex(zeros(6*m, 1))];
stimulus = [0; double(waveform)];
valid = [false; true(numel(waveform), 1)];
resetVector = false(numel(stimulus), 1);
resetVector(1) = true;
timeAxis = (0:numel(stimulus)-1).';

assignin("base", "stimulusIq", timeseries(complex(stimulus), timeAxis));
assignin("base", "stimulusValid", timeseries(valid, timeAxis));
assignin("base", "stimulusReset", timeseries(resetVector, timeAxis));
assignin("base", "stimulusSyncWord", ...
    timeseries(uint8(syncWord)*ones(numel(stimulus), 1, "uint8"), timeAxis));

if ~bdIsLoaded(info.modelName)
    load_system(info.modelPath);
end
set_param(info.modelName, StopTime=num2str(numel(stimulus)-1));
out = sim(info.modelName);

symbolValid = logical(out.symbolValid(:));
run = struct;
run.bins = double(out.symbolIndex(symbolValid));
skipStep = find(logical(out.resyncValid(:)), 1);
run.skip = 0;
run.preambleBin = 0;
run.detectSymbol = NaN;
if ~isempty(skipStep)
    run.skip = double(out.resyncSkip(skipStep));
    run.preambleBin = double(out.preambleBin(skipStep));
    symbolSteps = find(symbolValid);
    idx = find(symbolSteps > skipStep, 1);
    if ~isempty(idx)
        run.detectSymbol = idx;
    end
end
end

function best = longestCommonRun(sequences)
%LONGESTCOMMONRUN Longest contiguous run present in every sequence.
best = [];
first = sequences{1}(:);
for start = 1:numel(first)
    for stop = numel(first):-1:start
        span = stop-start+1;
        if span <= numel(best)
            break;
        end
        candidate = first(start:stop);
        inAll = true;
        for k = 2:numel(sequences)
            if isnan(subsequenceIndex(sequences{k}(:), candidate))
                inAll = false;
                break;
            end
        end
        if inAll
            best = candidate;
            break;
        end
    end
end
end

function index = subsequenceIndex(haystack, needle)
%SUBSEQUENCEINDEX First contiguous occurrence of needle in haystack.
index = NaN;
span = numel(needle);
for k = 1:numel(haystack)-span+1
    if isequal(haystack(k:k+span-1), needle)
        index = k;
        return;
    end
end
end

function closeIfLoaded(modelName)
if bdIsLoaded(modelName)
    set_param(modelName, Dirty="off");
    close_system(modelName, 0);
end
end
