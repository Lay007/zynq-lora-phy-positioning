function report = run_reset_regression(options)
%RUN_RESET_REGRESSION Prove that resetIn returns the DUT to a known state.
%
% A reset port is only meaningful if asserting it mid-stream makes the next
% packet behave exactly as if the DUT had just powered up. This drives one
% waveform, asserts reset, drives a second waveform in the same simulation,
% and requires the second half to match a standalone run of that waveform
% bit for bit.
%
% It also checks the timestamp counter, which is the other thing reset owns:
% after reset the sample count restarts at zero, so a packet's symbols carry
% sample indices relative to the reset rather than to the start of time.

arguments
    options.Configurations (:,2) double = [5, 2; 7, 8]
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
    samplesPerChip = options.Configurations(k, 2);
    config = lora_phy.css_config(spreadingFactor, samplesPerChip);
    m = config.samplesPerSymbol;

    first = lora_phy.modulate(mod((1:3).'*11, config.symbolCount), config);
    second = lora_phy.modulate(mod((1:2).'*29+5, config.symbolCount), config);
    secondCount = numel(second)/m;

    closeGeneratedModel(info);
    info = build_fft_correlator_model(SpreadingFactor=spreadingFactor, ...
        SamplesPerChip=samplesPerChip, ModelName="lora_fft_correlator_reset");

    % Reference: the second waveform on a freshly built model.
    reference = lora_sim.simulate_correlator(info, second);

    % Combined: first waveform, drain, reset pulse, second waveform.
    drain = 2*m+3*config.symbolCount+512;
    tail = 2*m+3*config.symbolCount+512;
    iq = [0; first; zeros(drain, 1); 0; second; zeros(tail, 1)];
    valid = [false; true(numel(first), 1); false(drain, 1); false; ...
        true(numel(second), 1); false(tail, 1)];
    resetVector = false(numel(iq), 1);
    resetVector(1) = true;
    resetStep = 1+numel(first)+drain+1;
    resetVector(resetStep) = true;

    timeAxis = (0:numel(iq)-1).';
    assignin("base", "stimulusIq", timeseries(complex(iq), timeAxis));
    assignin("base", "stimulusValid", timeseries(valid, timeAxis));
    assignin("base", "stimulusReset", timeseries(resetVector, timeAxis));
    if ~bdIsLoaded(info.modelName)
        load_system(info.modelPath);
    end
    set_param(info.modelName, StopTime=num2str(numel(iq)-1));
    out = sim(info.modelName);

    symbolValid = logical(out.symbolValid(:));
    symbols = double(out.symbolIndex(symbolValid));
    timestamps = double(out.symbolSampleCount(logical(out.timestampValid(:))));

    afterReset = symbols(end-secondCount+1:end);
    afterResetTimestamps = timestamps(end-secondCount+1:end);
    expectedTimestamps = ((0:secondCount-1).')*m;

    symbolsMatch = isequal(afterReset(:), reference.symbols(:));
    timestampsMatch = isequal(afterResetTimestamps(:), expectedTimestamps);

    rows{end+1} = table(spreadingFactor, samplesPerChip, m, ...
        numel(first)/m, secondCount, numel(symbols), symbolsMatch, ...
        timestampsMatch, ...
        VariableNames=["SF", "L", "M", "SymbolsBeforeReset", ...
        "SymbolsAfterReset", "SymbolsDecoded", "SymbolsMatchStandalone", ...
        "TimestampsRestart"]); %#ok<AGROW>

    if ~symbolsMatch
        failures(end+1, 1) = sprintf( ...
            "SF%d L=%d: symbols after reset differ from a standalone run", ...
            spreadingFactor, samplesPerChip); %#ok<AGROW>
    end
    if ~timestampsMatch
        failures(end+1, 1) = sprintf( ...
            "SF%d L=%d: sample counter did not restart at zero", ...
            spreadingFactor, samplesPerChip); %#ok<AGROW>
    end
    if options.Verbose
        fprintf("SF%-2d L=%d decoded=%d after-reset symbols match=%s " + ...
            "timestamps restart=%s\n", spreadingFactor, samplesPerChip, ...
            numel(symbols), string(symbolsMatch), string(timestampsMatch));
    end
end

closeGeneratedModel(info);

report = struct;
report.summary = vertcat(rows{:});
report.failures = failures;
report.passed = isempty(failures);

if options.WriteCsv
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(report.summary, fullfile(options.OutputDirectory, ...
        "simulink-m2-reset.csv"));
end

if options.Verbose
    fprintf("\n");
    disp(report.summary);
    if report.passed
        fprintf("resetIn returns the DUT to its power-up state.\n");
    else
        fprintf("FAILURES:\n  %s\n", strjoin(failures, newline+"  "));
    end
end
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
