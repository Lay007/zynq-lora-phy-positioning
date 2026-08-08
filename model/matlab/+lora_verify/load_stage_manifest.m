function manifest = load_stage_manifest(directory)
%LOAD_STAGE_MANIFEST Read the exported stage-vector manifest.
%
% Also verifies that every committed payload still matches the SHA-256 it
% was exported with, so a silent change in either the model or the files is
% reported as a checksum failure rather than as a tolerance failure.

arguments
    directory (1,1) string = lora_verify.stage_vector_directory
end

manifestPath = fullfile(directory, "manifest.json");
if ~isfile(manifestPath)
    error("lora_verify:MissingManifest", ...
        "No stage-vector manifest at %s. Run export_correlator_stage_vectors.", ...
        manifestPath);
end

manifest = jsondecode(fileread(manifestPath));
manifest.directory = directory;
if ~isfield(manifest, "schema") || ...
        manifest.schema ~= "zynq-lora-phy-stage-vectors-v1"
    error("lora_verify:UnsupportedSchema", ...
        "Unsupported stage-vector schema in %s", manifestPath);
end

for k = 1:numel(manifest.cases)
    entry = manifest.cases(k);
    dataPath = fullfile(directory, string(entry.dataFile));
    if ~isfile(dataPath)
        error("lora_verify:MissingStagePayload", ...
            "Missing payload %s", dataPath);
    end
    actual = lora_verify.sha256_file(dataPath);
    if actual ~= string(entry.sha256)
        error("lora_verify:StagePayloadChecksum", ...
            "Checksum mismatch for %s: manifest %s, file %s", ...
            string(entry.id), string(entry.sha256), actual);
    end
end
end
