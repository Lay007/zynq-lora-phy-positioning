function report = run_sfd_regression(options)
%RUN_SFD_REGRESSION Check the SFD acceptance DUT against MATLAB.
%
% Exact equality per SFD group against LORA_PHY.VALIDATE_SFD_BINS.
%
% The stimulus is dominated by cases that must be rejected. A checker that
% accepts everything passes any test fed only valid input, and this stage
% exists precisely to reject signals that already got past preamble and sync.

arguments
    options.SpreadingFactors (1,:) double = [7 5 9]
    options.RandomGroups (1,1) double = 200
    options.RandomSeed (1,1) double = 20260813
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

for spreadingFactor = options.SpreadingFactors
    config = lora_phy.css_config(spreadingFactor, 1);
    n = config.symbolCount;
    [downBins, preambleBins] = buildGroups(n, options);
    groups = size(downBins, 2);

    expectedValid = false(groups, 1);
    expectedAgree = false(groups, 1);
    expectedBin = zeros(groups, 1);
    for g = 1:groups
        result = lora_phy.validate_sfd_bins(downBins(:, g), ...
            preambleBins(g), config);
        expectedValid(g) = result.valid;
        expectedAgree(g) = result.agree;
        expectedBin(g) = result.expectedBin;
    end

    closeIfLoaded(info);
    info = build_sfd_model(SpreadingFactor=spreadingFactor, ...
        ModelName="lora_sfd_check");

    stream = downBins(:);
    total = numel(stream);
    timeAxis = (0:total-1).';
    assignin("base", "stimulusDownBin", timeseries(uint16(stream), timeAxis));
    assignin("base", "stimulusBinValid", timeseries(true(total, 1), timeAxis));
    assignin("base", "stimulusPreambleBin", ...
        timeseries(uint16(repelem(preambleBins(:), 2)), timeAxis));
    assignin("base", "stimulusReset", timeseries(false(total, 1), timeAxis));

    if ~bdIsLoaded(info.modelName)
        load_system(info.modelPath);
    end
    set_param(info.modelName, StopTime=num2str(total-1));
    out = sim(info.modelName);

    decisionSteps = (2:2:total).';
    validMismatch = sum(logical(out.sfdValid(decisionSteps)) ~= expectedValid);
    agreeMismatch = sum(logical(out.agree(decisionSteps)) ~= expectedAgree);
    binMismatch = sum(double(out.expectedBin(decisionSteps)) ~= expectedBin);

    rows{end+1} = table(spreadingFactor, n, groups, sum(expectedValid), ...
        validMismatch, agreeMismatch, binMismatch, ...
        VariableNames=["SF", "N", "Groups", "AcceptedByMatlab", ...
        "ValidMismatches", "AgreeMismatches", "MirrorMismatches"]); %#ok<AGROW>

    mismatches = validMismatch+agreeMismatch+binMismatch;
    if mismatches > 0
        failures(end+1, 1) = sprintf( ...
            "SF%d: %d mismatching decisions over %d groups", ...
            spreadingFactor, mismatches, groups); %#ok<AGROW>
    end
    % Both answers have to occur, or the comparison proves nothing.
    if sum(expectedValid) == 0 || sum(expectedValid) == groups
        failures(end+1, 1) = sprintf( ...
            "SF%d: stimulus must contain accepted and rejected groups", ...
            spreadingFactor); %#ok<AGROW>
    end
    if options.Verbose
        fprintf("SF%-2d N=%-5d groups=%-4d accepted=%-4d mismatches=%d\n", ...
            spreadingFactor, n, groups, sum(expectedValid), mismatches);
    end
end

closeIfLoaded(info);

report = struct;
report.summary = vertcat(rows{:});
report.failures = failures;
report.passed = isempty(failures);
report.totalGroups = sum(report.summary.Groups);

if options.WriteCsv
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(report.summary, fullfile(options.OutputDirectory, ...
        "simulink-m2-sfd.csv"));
end

if options.Verbose
    disp(report.summary);
    if report.passed
        fprintf("SFD acceptance matches MATLAB over %d groups.\n", ...
            report.totalGroups);
    else
        fprintf("FAILURES:\n  %s\n", strjoin(failures, newline+"  "));
    end
end
end

function [downBins, preambleBins] = buildGroups(n, options)
%BUILDGROUPS Accepted mirrors, near misses, and seeded random rejections.
preambleList = [0; 1; n-1; n/2; 7];
mirrored = mod(-preambleList, n);

blocks = {};
preambles = [];
% Exact mirror, and one bin of drift, which the tolerance must accept.
blocks{end+1} = [mirrored.'; mirrored.'];
preambles = [preambles; preambleList];
blocks{end+1} = [mod(mirrored+1, n).'; mod(mirrored-1, n).'];
preambles = [preambles; preambleList];
% Two bins off: agrees with itself, wrong target. The impostor case.
blocks{end+1} = [mod(mirrored+2, n).'; mod(mirrored+2, n).'];
preambles = [preambles; preambleList];
% Windows that disagree with each other.
blocks{end+1} = [mirrored.'; mod(mirrored+n/4, n).'];
preambles = [preambles; preambleList];

rng(options.RandomSeed, "twister");
randomBins = randi([0, n-1], 2, options.RandomGroups);
blocks{end+1} = randomBins;
preambles = [preambles; randi([0, n-1], options.RandomGroups, 1)];

downBins = double(cat(2, blocks{:}));
preambleBins = double(preambles);
end

function closeIfLoaded(info)
if isempty(info) || ~isfield(info, "modelName")
    return;
end
if bdIsLoaded(info.modelName)
    set_param(info.modelName, Dirty="off");
    close_system(info.modelName, 0);
end
end
