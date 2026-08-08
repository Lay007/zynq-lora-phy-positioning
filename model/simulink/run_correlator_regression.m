function report = run_correlator_regression(options)
%RUN_CORRELATOR_REGRESSION Compare the Simulink DUT with MATLAB stage by stage.
%
% The committed golden `input` stage is the stimulus, so the comparison
% exercises only the Simulink path and never re-runs waveform generation.
% Every case reports maximum absolute error, RMS error, relative RMS error,
% the symbol decision, confidence, and measured latency.
%
%   report = run_correlator_regression;
%   report = run_correlator_regression(Cases="sf7-l8-clean");
%
% REPORT.passed is false if any stage exceeds the tolerance, any symbol
% decision differs, or any confidence differs beyond tolerance.

arguments
    options.Cases string = string.empty
    options.RelativeTolerance (1,1) double = 1e-12
    options.ConfidenceTolerance (1,1) double = 1e-12
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

manifest = lora_verify.load_stage_manifest;
definitions = lora_verify.stage_case_definitions;

selected = 1:numel(manifest.cases);
if ~isempty(options.Cases)
    keep = arrayfun(@(k) any(string(manifest.cases(k).id) == options.Cases), ...
        selected);
    selected = selected(keep);
    if isempty(selected)
        error("lora_sim:NoMatchingCase", ...
            "No committed case matches %s", strjoin(options.Cases, ", "));
    end
end

stageBlocks = {};
summaryBlocks = {};
info = struct.empty;
builtConfiguration = [NaN, NaN];
failures = strings(0, 1);

modelCleanup = onCleanup(@() closeGeneratedModel(info));

for index = selected
    entry = manifest.cases(index);
    caseId = string(entry.id);
    definition = definitions(arrayfun(@(d) d.id == caseId, definitions));

    stored = lora_verify.read_stage_vectors( ...
        fullfile(manifest.directory, string(entry.dataFile)), entry.stages);

    configuration = [entry.spreadingFactor, entry.samplesPerChip];
    if ~isequal(configuration, builtConfiguration)
        closeGeneratedModel(info);
        info = build_fft_correlator_model( ...
            SpreadingFactor=configuration(1), ...
            SamplesPerChip=configuration(2));
        builtConfiguration = configuration;
    end

    romError = max(abs(info.conjReferenceSpectrum(:)- ...
        stored.conjReferenceSpectrum(:)));

    waveform = stored.input(:);
    result = lora_sim.simulate_correlator(info, waveform);

    stageNames = ["fftM"; "product"; "partition"; "fftN"; "magnitudeSquared"];
    comparison = lora_verify.compare_stages(stored, result, stageNames);
    comparison.Case = repmat(caseId, height(comparison), 1);
    comparison = movevars(comparison, "Case", Before=1);
    stageBlocks{end+1} = comparison; %#ok<AGROW>

    matlabSymbols = double(entry.expectedSymbols(:).');
    simulinkSymbols = result.symbols(:).';
    symbolsMatch = isequal(matlabSymbols, simulinkSymbols);

    matlabConfidence = double(entry.expectedConfidence(:).');
    confidenceAbsError = max(abs(result.confidence(:).'-matlabConfidence));
    confidenceRelError = confidenceAbsError/max(abs(matlabConfidence), [], "all");

    [worstRelative, worstIndex] = max(comparison.RelativeRms);
    worstStage = comparison.Stage(worstIndex);

    summary = table(caseId, entry.spreadingFactor, entry.samplesPerChip, ...
        entry.symbolCount, entry.samplesPerSymbol, entry.windowSymbols, ...
        string(mat2str(matlabSymbols)), string(mat2str(simulinkSymbols)), ...
        symbolsMatch, confidenceAbsError, confidenceRelError, ...
        worstStage, worstRelative, max(comparison.MaxAbsError), romError, ...
        result.fftMLatencySamples, result.symbolLatencySamples, ...
        string(mat2str(result.symbolIntervalSamples(:).')), ...
        result.throughputSymbolsPerSample, ...
        VariableNames=["Case", "SF", "L", "N", "M", "Windows", ...
        "MatlabSymbols", "SimulinkSymbols", "SymbolsMatch", ...
        "ConfidenceAbsError", "ConfidenceRelError", "WorstStage", ...
        "WorstRelativeRms", "WorstMaxAbsError", "ReferenceRomMaxAbsError", ...
        "FftMLatencySamples", "SymbolLatencySamples", ...
        "SymbolIntervalSamples", "ThroughputSymbolsPerSample"]);
    summaryBlocks{end+1} = summary; %#ok<AGROW>

    if ~symbolsMatch
        failures(end+1, 1) = caseId+": symbol decisions differ"; %#ok<AGROW>
    end
    if confidenceRelError > options.ConfidenceTolerance
        failures(end+1, 1) = sprintf("%s: confidence relative error %.3e", ...
            caseId, confidenceRelError); %#ok<AGROW>
    end
    if worstRelative > options.RelativeTolerance
        failures(end+1, 1) = sprintf("%s: stage %s relative RMS %.3e", ...
            caseId, worstStage, worstRelative); %#ok<AGROW>
    end
    if romError > 0
        failures(end+1, 1) = sprintf( ...
            "%s: reference ROM differs from the golden spectrum by %.3e", ...
            caseId, romError); %#ok<AGROW>
    end

    if options.Verbose
        fprintf("%-18s SF%-2d L=%d M=%-5d symbols %s worst %.3e (%s)\n", ...
            caseId, entry.spreadingFactor, entry.samplesPerChip, ...
            entry.samplesPerSymbol, string(symbolsMatch), worstRelative, ...
            worstStage);
    end
end

closeGeneratedModel(info);
clear modelCleanup;

stageRows = vertcat(stageBlocks{:});
summaryRows = vertcat(summaryBlocks{:});

report = struct;
report.dataType = "double";
report.relativeTolerance = options.RelativeTolerance;
report.confidenceTolerance = options.ConfidenceTolerance;
report.stages = stageRows;
report.summary = summaryRows;
report.failures = failures;
report.passed = isempty(failures);
report.worstRelativeRms = max(stageRows.RelativeRms);
report.worstMaxAbsError = max(stageRows.MaxAbsError);

if options.WriteCsv
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(stageRows, fullfile(options.OutputDirectory, ...
        "simulink-m2-stage-comparison.csv"));
    writetable(summaryRows, fullfile(options.OutputDirectory, ...
        "simulink-m2-case-summary.csv"));
end

if options.Verbose
    fprintf("\ncases=%d worst relative RMS=%.3e worst abs=%.3e\n", ...
        height(summaryRows), report.worstRelativeRms, ...
        report.worstMaxAbsError);
    if report.passed
        fprintf("Simulink double model matches MATLAB within %.0e.\n", ...
            options.RelativeTolerance);
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
