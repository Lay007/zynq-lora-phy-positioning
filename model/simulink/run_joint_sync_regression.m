function report = run_joint_sync_regression(options)
%RUN_JOINT_SYNC_REGRESSION Exhaustively check the joint timing/CFO DUT.
%
% The estimator has a finite input domain: N x N pairs of dechirped bins.
% For the smaller spreading factors every pair is enumerated, so the result
% is not a sample but a proof over the whole domain. For large N a seeded
% random subset plus every boundary pair is used, and the report says which
% mode ran.
%
% The comparison is exact equality, not a tolerance: the estimator is
% integer arithmetic in units of half a bin.

arguments
    options.Configurations (:,2) double = [5, 8; 7, 8; 7, 1; 9, 2]
    options.MaxExhaustivePairs (1,1) double = 300000
    options.RandomPairs (1,1) double = 200000
    options.RandomSeed (1,1) double = 20260809
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
info = struct.empty;
failures = strings(0, 1);

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
        downBin = [downGrid(:); randi([0, n-1], options.RandomPairs, 1)];
        coverage = "boundary+random";
    end

    expected = lora_phy.joint_timing_cfo_from_bins(upBin, downBin, config);

    closeGeneratedModel(info);
    info = build_joint_sync_model(SpreadingFactor=spreadingFactor, ...
        SamplesPerChip=samplesPerChip);

    pairCount = numel(upBin);
    timeAxis = (0:pairCount-1).';
    assignin("base", "stimulusUpBin", ...
        timeseries(uint16(upBin), timeAxis));
    assignin("base", "stimulusDownBin", ...
        timeseries(uint16(downBin), timeAxis));
    assignin("base", "stimulusBinValid", ...
        timeseries(true(pairCount, 1), timeAxis));
    set_param(info.modelName, StopTime=num2str(pairCount-1));
    simulationOutput = sim(info.modelName);

    actualCorrection = double(simulationOutput.correctionSamples(1:pairCount));
    actualCfo = double(simulationOutput.cfoHalfBins(1:pairCount));
    actualTiming = double(simulationOutput.timingHalfChips(1:pairCount));
    actualRejected = logical(simulationOutput.timingRejected(1:pairCount));
    actualValid = logical(simulationOutput.estimateValid(1:pairCount));

    correctionMismatch = sum(actualCorrection(:) ~= ...
        expected.correctionSamples(:));
    cfoMismatch = sum(actualCfo(:) ~= expected.cfoHalfBins(:));
    timingMismatch = sum(actualTiming(:) ~= expected.timingHalfChips(:));
    rejectedMismatch = sum(actualRejected(:) ~= expected.rejected(:));
    validMismatch = sum(~actualValid);
    total = correctionMismatch+cfoMismatch+timingMismatch+ ...
        rejectedMismatch+validMismatch;

    rows{end+1} = table(spreadingFactor, samplesPerChip, n, pairCount, ...
        string(coverage), correctionMismatch, cfoMismatch, timingMismatch, ...
        rejectedMismatch, validMismatch, sum(expected.rejected), ...
        VariableNames=["SF", "L", "N", "Pairs", "Coverage", ...
        "CorrectionMismatches", "CfoMismatches", "TimingMismatches", ...
        "RejectionMismatches", "ValidMismatches", ...
        "RejectedPairs"]); %#ok<AGROW>

    if total > 0
        failures(end+1, 1) = sprintf( ...
            "SF%d L=%d: %d mismatching outputs over %d pairs", ...
            spreadingFactor, samplesPerChip, total, pairCount); %#ok<AGROW>
    end
    if options.Verbose
        fprintf("SF%-2d L=%d N=%-5d pairs=%-7d %-16s mismatches=%d\n", ...
            spreadingFactor, samplesPerChip, n, pairCount, coverage, total);
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
        "simulink-m2-joint-sync.csv"));
end

if options.Verbose
    fprintf("\n");
    disp(report.summary);
    if report.passed
        fprintf("Joint timing/CFO DUT is bit-exact over %d bin pairs.\n", ...
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
