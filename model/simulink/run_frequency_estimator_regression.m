function report = run_frequency_estimator_regression(options)
%RUN_FREQUENCY_ESTIMATOR_REGRESSION Check the frequency-only DUT exactly.
%
% The finite bin-pair domain is exhaustive when practical. Expected CFO is
% taken from the unchanged MATLAB joint timing/CFO golden model; only its
% CFO output is compared. Invalid inputs are interleaved to verify that the
% registered valid contract and output zeroing survive the two-cycle delay.

arguments
    options.Configurations (:,2) double = [5, 8; 7, 8; 7, 1; 9, 2]
    options.MaxExhaustivePairs (1,1) double = 300000
    options.RandomPairs (1,1) double = 200000
    options.RandomSeed (1,1) double = 20260816
    options.ReferenceBandwidthHz (1,1) double {mustBePositive} = 125000
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
    n = config.symbolCount;

    if n*n <= options.MaxExhaustivePairs
        [upGrid, downGrid] = ndgrid(0:n-1, 0:n-1);
        upBin = upGrid(:);
        downBin = downGrid(:);
        coverage = "exhaustive";
    else
        rng(options.RandomSeed+spreadingFactor, "twister");
        edges = [0; 1; n/2-1; n/2; n/2+1; n-1];
        [upGrid, downGrid] = ndgrid(edges, edges);
        upBin = [upGrid(:); randi([0, n-1], options.RandomPairs, 1)];
        downBin = [downGrid(:); randi([0, n-1], ...
            options.RandomPairs, 1)];
        coverage = "boundary+random";
    end

    expected = lora_phy.joint_timing_cfo_from_bins(upBin, downBin, config);
    pairCount = numel(upBin);
    binValid = mod((0:pairCount-1).', 17) ~= 0;
    expectedCfo = expected.cfoHalfBins;
    expectedCfo(~binValid) = 0;

    closeGeneratedModel(info);
    info = build_frequency_estimator_model( ...
        SpreadingFactor=spreadingFactor, SamplesPerChip=samplesPerChip);
    latency = info.latencyCycles;
    samples = pairCount+latency;
    timeAxis = (0:samples-1).';
    upStimulus = cast([upBin; zeros(latency, 1)], info.binDataType);
    downStimulus = cast([downBin; zeros(latency, 1)], info.binDataType);
    assignin("base", "stimulusUpBin", timeseries(upStimulus, timeAxis));
    assignin("base", "stimulusDownBin", timeseries(downStimulus, timeAxis));
    assignin("base", "stimulusBinValid", timeseries( ...
        [binValid; false(latency, 1)], timeAxis));
    set_param(info.modelName, StopTime=num2str(samples-1));
    simulationOutput = sim(info.modelName);

    indices = latency+(1:pairCount);
    actualCfo = double(simulationOutput.cfoHalfBins(indices));
    actualValid = logical(simulationOutput.estimateValid(indices));
    cfoMismatch = sum(actualCfo(:) ~= expectedCfo(:));
    validMismatch = sum(actualValid(:) ~= binValid(:));
    total = cfoMismatch+validMismatch;

    resolutionHz = options.ReferenceBandwidthHz/(2*n);
    maximumQuantizationErrorHz = resolutionHz/2;
    rows{end+1} = table(spreadingFactor, samplesPerChip, n, pairCount, ...
        string(coverage), latency, cfoMismatch, validMismatch, ...
        options.ReferenceBandwidthHz, resolutionHz, ...
        maximumQuantizationErrorHz, ...
        VariableNames=["SF", "L", "N", "Pairs", "Coverage", ...
        "LatencyCycles", "CfoMismatches", "ValidMismatches", ...
        "ReferenceBandwidthHz", "ResolutionHz", ...
        "MaxQuantizationErrorHz"]); %#ok<AGROW>

    if total > 0
        failures(end+1, 1) = sprintf( ...
            "SF%d L=%d: %d mismatches over %d pairs", ...
            spreadingFactor, samplesPerChip, total, pairCount); %#ok<AGROW>
    end
    if options.Verbose
        fprintf("SF%-2d L=%d pairs=%-7d %-16s mismatches=%d " + ...
            "resolution@%.0fkHz=%.3f Hz\n", spreadingFactor, ...
            samplesPerChip, pairCount, coverage, total, ...
            options.ReferenceBandwidthHz/1000, resolutionHz);
    end
end

closeGeneratedModel(info);

report = struct;
report.summary = vertcat(rows{:});
report.failures = failures;
report.passed = isempty(failures);
report.totalPairs = sum(report.summary.Pairs);

if options.WriteCsv
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(report.summary, fullfile(options.OutputDirectory, ...
        "simulink-m2-frequency-estimator.csv"));
end

if options.Verbose
    fprintf("\n");
    disp(report.summary);
    if report.passed
        fprintf("Frequency-only DUT is bit-exact over %d bin pairs.\n", ...
            report.totalPairs);
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
