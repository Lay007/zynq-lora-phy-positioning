function report = compare_stages(reference, actual, stageNames)
%COMPARE_STAGES Absolute, RMS, and relative error per comparison point.
%
% REPORT is a table with one row per stage. RelativeRms is the RMS error
% divided by the RMS magnitude of the reference stage, which keeps the
% number meaningful across stages whose scales differ by orders of
% magnitude (the M-point FFT grows with M, the final FFT is scaled by 1/M).

arguments
    reference (1,1) struct
    actual (1,1) struct
    stageNames string = lora_verify.stage_order
end

stageNames = stageNames(:);
rows = numel(stageNames);
maxAbsError = zeros(rows, 1);
rmsError = zeros(rows, 1);
relativeRms = zeros(rows, 1);
referenceRms = zeros(rows, 1);
elementCount = zeros(rows, 1);

for k = 1:rows
    name = stageNames(k);
    if ~isfield(reference, name)
        error("lora_verify:MissingReferenceStage", ...
            "Reference has no stage %s", name);
    end
    if ~isfield(actual, name)
        error("lora_verify:MissingActualStage", ...
            "Actual has no stage %s", name);
    end
    expected = reference.(name);
    measured = actual.(name);
    if ~isequal(size(expected), size(measured))
        error("lora_verify:StageSizeMismatch", ...
            "Stage %s is %s in the reference and %s in the comparison", ...
            name, mat2str(size(expected)), mat2str(size(measured)));
    end
    difference = double(measured(:))-double(expected(:));
    maxAbsError(k) = max([abs(difference); 0]);
    rmsError(k) = sqrt(mean([abs(difference).^2; zeros(0, 1)]));
    referenceRms(k) = sqrt(mean([abs(double(expected(:))).^2; zeros(0, 1)]));
    if referenceRms(k) > 0
        relativeRms(k) = rmsError(k)/referenceRms(k);
    else
        relativeRms(k) = 0;
    end
    elementCount(k) = numel(expected);
end

report = table(stageNames, elementCount, maxAbsError, rmsError, ...
    referenceRms, relativeRms, ...
    VariableNames=["Stage", "Elements", "MaxAbsError", "RmsError", ...
    "ReferenceRms", "RelativeRms"]);
end
