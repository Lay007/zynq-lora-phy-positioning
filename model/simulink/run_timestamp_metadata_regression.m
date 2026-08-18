function report = run_timestamp_metadata_regression(options)
%RUN_TIMESTAMP_METADATA_REGRESSION Verify the atomic timestamp contract.
%
% Exercises the property missing from the separate front-end and ToA tests:
% coarseSampleCount and fractionalToaSamples must emerge as one qualified
% record even when the two source pipelines complete on different cycles.
%
% Covered cases:
%   - coarse fragment first;
%   - fractional fragment first;
%   - both fragments in the same cycle;
%   - duplicate fragment detection without overwriting the original value;
%   - reset discarding a partial record;
%   - back-to-back records after the previous record is emitted.

arguments
    options.OutputDirectory string = string.empty
    options.WriteCsv (1,1) logical = true
    options.Verbose (1,1) logical = true
end

simulinkRoot = fileparts(mfilename("fullpath"));
repositoryRoot = fileparts(fileparts(simulinkRoot));
addpath(simulinkRoot);
if isempty(options.OutputDirectory)
    options.OutputDirectory = string(fullfile(repositoryRoot, "docs", "data"));
end

info = build_timestamp_metadata_model(ModelName="lora_timestamp_metadata_check");
cleanup = onCleanup(@() closeIfLoaded(info.modelName)); %#ok<NASGU>

sampleCount = 30;
timeAxis = (0:sampleCount-1).';
coarse = zeros(sampleCount, 1, "uint64");
coarseValid = false(sampleCount, 1);
fractional = zeros(sampleCount, 1, "int32");
fractionalValid = false(sampleCount, 1);
resetVector = false(sampleCount, 1);
resetVector(1) = true;

% Pair 1: coarse first.
coarse(3) = uint64(1000); coarseValid(3) = true;
fractional(5) = int32(-512); fractionalValid(5) = true;
% Pair 2: fractional first.
fractional(8) = int32(1024); fractionalValid(8) = true;
coarse(10) = uint64(2000); coarseValid(10) = true;
% Pair 3: same cycle.
coarse(13) = uint64(3000); coarseValid(13) = true;
fractional(13) = int32(0); fractionalValid(13) = true;
% Pair 4: duplicate coarse must not overwrite the first value.
coarse(16) = uint64(4000); coarseValid(16) = true;
coarse(17) = uint64(9999); coarseValid(17) = true;
fractional(18) = int32(256); fractionalValid(18) = true;
% Partial pair is discarded by reset. The fractional half that follows reset
% must wait for a new coarse half rather than pairing with the discarded one.
coarse(21) = uint64(5000); coarseValid(21) = true;
resetVector(22) = true;
fractional(23) = int32(-256); fractionalValid(23) = true;
coarse(24) = uint64(6000); coarseValid(24) = true;

assignin("base", "stimulusCoarseSampleCount", timeseries(coarse, timeAxis));
assignin("base", "stimulusCoarseValid", timeseries(coarseValid, timeAxis));
assignin("base", "stimulusFractionalToaSamples", timeseries(fractional, timeAxis));
assignin("base", "stimulusFractionalValid", timeseries(fractionalValid, timeAxis));
assignin("base", "stimulusReset", timeseries(resetVector, timeAxis));

if ~bdIsLoaded(info.modelName)
    load_system(info.modelPath);
end
set_param(info.modelName, StopTime=num2str(sampleCount-1));
out = sim(info.modelName);

valid = logical(out.timestampValid(:));
overflow = logical(out.metadataOverflow(:));
emitIndices = find(valid).';
overflowIndices = find(overflow).';
expectedEmitIndices = [6 11 14 19 25];
expectedOverflowIndices = 17;
expectedCoarse = uint64([1000 2000 3000 4000 6000]);
expectedFractional = int32([-512 1024 0 256 -256]);

failures = strings(0, 1);
if ~isequal(emitIndices, expectedEmitIndices)
    failures(end+1, 1) = sprintf("timestampValid at %s, expected %s", ...
        mat2str(emitIndices), mat2str(expectedEmitIndices)); %#ok<AGROW>
end
if ~isequal(overflowIndices, expectedOverflowIndices)
    failures(end+1, 1) = sprintf("metadataOverflow at %s, expected %s", ...
        mat2str(overflowIndices), mat2str(expectedOverflowIndices)); %#ok<AGROW>
end

actualCoarse = uint64(out.coarseSampleCountOut(valid));
actualFractional = int32(out.fractionalToaSamplesOut(valid));
if ~isequal(actualCoarse(:).', expectedCoarse)
    failures(end+1, 1) = sprintf("coarse records %s, expected %s", ...
        mat2str(actualCoarse(:).'), mat2str(expectedCoarse)); %#ok<AGROW>
end
if ~isequal(actualFractional(:).', expectedFractional)
    failures(end+1, 1) = sprintf("fractional records %s, expected %s", ...
        mat2str(actualFractional(:).'), mat2str(expectedFractional)); %#ok<AGROW>
end

packet = (1:numel(expectedCoarse)).';
emitCycle = expectedEmitIndices(:)-1;
summary = table(packet, emitCycle, expectedCoarse(:), expectedFractional(:), ...
    VariableNames=["Packet", "EmitCycle", "CoarseSampleCount", ...
    "FractionalToaQ12"]);

report = struct;
report.summary = summary;
report.failures = failures;
report.passed = isempty(failures);
report.overflowCycle = expectedOverflowIndices-1;
report.outputLatencyAfterPairComplete = info.outputLatencyAfterPairComplete;

if options.WriteCsv
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(summary, fullfile(options.OutputDirectory, ...
        "simulink-m2-timestamp-metadata.csv"));
end

if options.Verbose
    disp(summary);
    fprintf("duplicate-fragment overflow cycle: %d\n", report.overflowCycle);
    if report.passed
        fprintf("Timestamp metadata contract passed all ordering/reset cases.\n");
    else
        fprintf("FAILURES:\n  %s\n", strjoin(failures, newline+"  "));
    end
end
end

function closeIfLoaded(modelName)
if bdIsLoaded(modelName)
    set_param(modelName, Dirty="off");
    close_system(modelName, 0);
end
end
