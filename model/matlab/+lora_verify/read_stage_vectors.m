function stages = read_stage_vectors(filePath, layout)
%READ_STAGE_VECTORS Read a `.f64` case payload back into MATLAB arrays.
%
% LAYOUT is the per-case `stages` array stored in the manifest. Reading is
% driven entirely by the manifest, so the binary payload never has to be
% self-describing.

arguments
    filePath (1,1) string
    layout struct
end

file = fopen(filePath, "r", "ieee-le");
if file < 0
    error("lora_verify:StageVectorFile", "Cannot open %s", filePath);
end
cleanup = onCleanup(@() fclose(file));

stages = struct;
for k = 1:numel(layout)
    entry = layout(k);
    if fseek(file, entry.offsetBytes, "bof") ~= 0
        error("lora_verify:StageVectorSeek", ...
            "Cannot seek to stage %s", string(entry.name));
    end
    elementCount = double(entry.rows)*double(entry.cols);
    if logical(entry.complex)
        raw = fread(file, 2*elementCount, "double");
        if numel(raw) ~= 2*elementCount
            error("lora_verify:StageVectorRead", ...
                "Truncated stage %s", string(entry.name));
        end
        value = complex(raw(1:2:end), raw(2:2:end));
    else
        value = fread(file, elementCount, "double");
        if numel(value) ~= elementCount
            error("lora_verify:StageVectorRead", ...
                "Truncated stage %s", string(entry.name));
        end
    end
    stages.(string(entry.name)) = reshape(value, ...
        double(entry.rows), double(entry.cols));
end
end
