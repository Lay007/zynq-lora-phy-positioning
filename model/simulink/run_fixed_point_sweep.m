function report = run_fixed_point_sweep(options)
%RUN_FIXED_POINT_SWEEP Find the smallest word length that keeps decisions.
%
% For every word length in the sweep the fixed-point DUT is rebuilt for
% each SF/L configuration and driven with the committed golden `input`
% stage. The pass criterion is the one from the M2 plan:
%
%   1. every acceptance case decides the same symbol as MATLAB, and
%   2. the numerical error of every stage is recorded, not merely bounded.
%
% Criterion 1 alone is not sufficient and the sweep says so. At 8 bits every
% acceptance case still decides the same symbol while the relative RMS error
% reaches 118%: the decision survives only because the gap between the
% winning bin and the runner-up is large in these vectors. A demodulator
% that wrong is useless to the soft-decision path, so the selection also
% requires the numerical error to stay within MaxRelativeRms. The report
% carries both answers, and DecisionMargin says whether a passing point
% cleared the bar comfortably or by luck.
%
% Integer bits come from measured range analysis, so the word length only
% trades fraction bits. Rounding is Floor and overflow saturates at every
% chosen boundary; those policies are held constant so the sweep changes
% one variable at a time.
%
%   report = run_fixed_point_sweep;
%   report = run_fixed_point_sweep(WordLengths=[12 16]);

arguments
    options.WordLengths (1,:) double = [10, 12, 14, 16, 18, 20]
    options.Cases string = string.empty
    options.GuardBits (1,1) double = 1
    options.Rounding (1,1) string = "Floor"
    options.Overflow (1,1) string = "Saturate"
    options.MaxRelativeRms (1,1) double = 1e-2
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
order = caseOrder(manifest, options.Cases);
stageNames = ["fftM"; "product"; "partition"; "fftN"; "magnitudeSquared"];

stageBlocks = {};
summaryBlocks = {};
info = struct.empty;

for wordLength = options.WordLengths
    if options.Verbose
        fprintf("\n--- word length %d ---\n", wordLength);
    end
    builtConfiguration = [NaN, NaN];
    for index = order
        entry = manifest.cases(index);
        caseId = string(entry.id);
        configuration = [entry.spreadingFactor, entry.samplesPerChip];
        if ~isequal(configuration, builtConfiguration)
            closeGeneratedModel(info);
            info = build_fft_correlator_model( ...
                SpreadingFactor=configuration(1), ...
                SamplesPerChip=configuration(2), ...
                DataType="fixed", WordLength=wordLength, ...
                GuardBits=options.GuardBits, Rounding=options.Rounding, ...
                Overflow=options.Overflow, ...
                ModelName="lora_fft_correlator_fixed");
            builtConfiguration = configuration;
        end

        stored = lora_verify.read_stage_vectors( ...
            fullfile(manifest.directory, string(entry.dataFile)), ...
            entry.stages);
        result = lora_sim.simulate_correlator(info, stored.input(:));

        comparison = lora_verify.compare_stages(stored, result, stageNames);
        comparison.WordLength = repmat(wordLength, height(comparison), 1);
        comparison.Case = repmat(caseId, height(comparison), 1);
        comparison = movevars(comparison, ["WordLength", "Case"], Before=1);
        stageBlocks{end+1} = comparison; %#ok<AGROW>

        matlabSymbols = double(entry.expectedSymbols(:).');
        fixedSymbols = result.symbols(:).';
        symbolsMatch = isequal(matlabSymbols, fixedSymbols);
        confidenceAbsError = max(abs(result.confidence(:).'- ...
            double(entry.expectedConfidence(:).')));

        margin = decisionMargin(result.magnitudeSquared);

        summaryBlocks{end+1} = table(wordLength, caseId, ...
            entry.spreadingFactor, entry.samplesPerChip, ...
            entry.samplesPerSymbol, symbolsMatch, ...
            string(mat2str(matlabSymbols)), string(mat2str(fixedSymbols)), ...
            confidenceAbsError, max(comparison.RelativeRms), ...
            max(comparison.MaxAbsError), margin, ...
            string(info.types.input.name), ...
            string(info.types.reference.name), ...
            string(info.types.product.name), ...
            string(info.types.accumulator.name), ...
            string(info.types.fftN.name), ...
            string(info.types.magnitudeSquared.name), ...
            info.types.fftMOutputWordLength, ...
            info.types.fftNOutputWordLength, ...
            VariableNames=["WordLength", "Case", "SF", "L", "M", ...
            "SymbolsMatch", "MatlabSymbols", "FixedSymbols", ...
            "ConfidenceAbsError", "WorstRelativeRms", "WorstMaxAbsError", ...
            "DecisionMargin", "InputType", "ReferenceType", "ProductType", ...
            "AccumulatorType", "FftNType", "MagnitudeType", ...
            "FftMOutputWordLength", "FftNOutputWordLength"]); %#ok<AGROW>

        if options.Verbose
            fprintf("  %-18s SF%-2d L=%d match=%-5s worstRel=%.3e margin=%.3f\n", ...
                caseId, entry.spreadingFactor, entry.samplesPerChip, ...
                string(symbolsMatch), max(comparison.RelativeRms), margin);
        end
    end
    closeGeneratedModel(info);
    info = struct.empty;
    builtConfiguration = [NaN, NaN]; %#ok<NASGU>
end

stageRows = vertcat(stageBlocks{:});
summaryRows = vertcat(summaryBlocks{:});

wordLengths = unique(summaryRows.WordLength);
matches = zeros(numel(wordLengths), 1);
worstRelative = zeros(numel(wordLengths), 1);
worstConfidence = zeros(numel(wordLengths), 1);
worstMargin = zeros(numel(wordLengths), 1);
for k = 1:numel(wordLengths)
    rows = summaryRows.WordLength == wordLengths(k);
    matches(k) = sum(summaryRows.SymbolsMatch(rows));
    worstRelative(k) = max(summaryRows.WorstRelativeRms(rows));
    worstConfidence(k) = max(summaryRows.ConfidenceAbsError(rows));
    worstMargin(k) = min(summaryRows.DecisionMargin(rows));
end
caseCount = numel(order);
byWordLength = table(wordLengths, repmat(caseCount, numel(wordLengths), 1), ...
    matches, worstRelative, worstConfidence, worstMargin, ...
    VariableNames=["WordLength", "Cases", "SymbolMatches", ...
    "WorstRelativeRms", "WorstConfidenceAbsError", "SmallestDecisionMargin"]);

decisionOnly = byWordLength.WordLength( ...
    byWordLength.SymbolMatches == caseCount);
passing = byWordLength.WordLength( ...
    byWordLength.SymbolMatches == caseCount & ...
    byWordLength.WorstRelativeRms <= options.MaxRelativeRms);
report = struct;
report.stages = stageRows;
report.summary = summaryRows;
report.byWordLength = byWordLength;
report.caseCount = caseCount;
report.guardBits = options.GuardBits;
report.rounding = options.Rounding;
report.overflow = options.Overflow;
report.maxRelativeRms = options.MaxRelativeRms;
if isempty(decisionOnly)
    report.decisionOnlyWordLength = NaN;
else
    report.decisionOnlyWordLength = min(decisionOnly);
end
if isempty(passing)
    report.selectedWordLength = NaN;
else
    report.selectedWordLength = min(passing);
end
report.passed = ~isnan(report.selectedWordLength);

if options.WriteCsv
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(stageRows, fullfile(options.OutputDirectory, ...
        "simulink-m2-fixed-point-stages.csv"));
    writetable(summaryRows, fullfile(options.OutputDirectory, ...
        "simulink-m2-fixed-point-cases.csv"));
    writetable(byWordLength, fullfile(options.OutputDirectory, ...
        "simulink-m2-fixed-point-sweep.csv"));
end

if options.Verbose
    fprintf("\n");
    disp(byWordLength);
    fprintf("Smallest word length keeping every decision : %d bits\n", ...
        report.decisionOnlyWordLength);
    if report.passed
        fprintf("Smallest word length also within %.0e error : %d bits\n", ...
            options.MaxRelativeRms, report.selectedWordLength);
    else
        fprintf("No swept word length met both criteria over %d cases\n", ...
            caseCount);
    end
end
end

function order = caseOrder(manifest, requested)
%CASEORDER Group cases by SF/L so each model is built once per sweep point.
count = numel(manifest.cases);
keys = zeros(count, 2);
keep = true(count, 1);
for k = 1:count
    keys(k, :) = [manifest.cases(k).spreadingFactor, ...
        manifest.cases(k).samplesPerChip];
    if ~isempty(requested)
        keep(k) = any(string(manifest.cases(k).id) == requested);
    end
end
indices = find(keep);
[~, sorted] = sortrows(keys(indices, :));
order = reshape(indices(sorted), 1, []);
end

function margin = decisionMargin(magnitudeSquared)
%DECISIONMARGIN Relative gap between the winning bin and the runner-up.
%
% A margin near zero means quantization could flip the argmax; it is the
% number that says whether a passing sweep point is comfortable or lucky.
margin = Inf;
for column = 1:size(magnitudeSquared, 2)
    values = sort(magnitudeSquared(:, column), "descend");
    if numel(values) < 2 || values(1) <= 0
        continue;
    end
    margin = min(margin, (values(1)-values(2))/values(1));
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
