function layout = write_stage_vectors(filePath, stages)
%WRITE_STAGE_VECTORS Write one case payload as little-endian float64.
%
% Layout: the stages of LORA_VERIFY.STAGE_ORDER are concatenated with no
% padding. Elements follow MATLAB column-major order, so within one column
% the index is the streaming order and each column is one CSS symbol.
% Complex stages interleave real and imaginary parts per element.
%
% The format is deliberately raw so that MATLAB, Simulink, Python, and a
% future HDL testbench can all read it without a parser.

arguments
    filePath (1,1) string
    stages (1,1) struct
end

[names, isComplex] = lora_verify.stage_order;

file = fopen(filePath, "w", "ieee-le");
if file < 0
    error("lora_verify:StageVectorFile", "Cannot open %s", filePath);
end
cleanup = onCleanup(@() fclose(file));

layout = struct([]);
offsetBytes = 0;
for k = 1:numel(names)
    name = names(k);
    value = stages.(name);
    rows = size(value, 1);
    cols = size(value, 2);
    if isComplex(k)
        payload = [real(value(:)).'; imag(value(:)).'];
        elementBytes = 16;
    else
        if ~isreal(value)
            error("lora_verify:UnexpectedComplexStage", ...
                "Stage %s must be real", name);
        end
        payload = value(:).';
        elementBytes = 8;
    end
    written = fwrite(file, payload, "double");
    if written ~= numel(payload)
        error("lora_verify:StageVectorWrite", ...
            "Short write for stage %s", name);
    end

    entry = struct;
    entry.name = name;
    entry.rows = rows;
    entry.cols = cols;
    entry.complex = isComplex(k);
    entry.offsetBytes = offsetBytes;
    entry.lengthBytes = rows*cols*elementBytes;
    entry.maxAbs = max([abs(value(:)); 0]);
    entry.rms = sqrt(mean([abs(value(:)).^2; zeros(0, 1)]));
    layout = [layout; entry]; %#ok<AGROW>
    offsetBytes = offsetBytes+entry.lengthBytes;
end
end
