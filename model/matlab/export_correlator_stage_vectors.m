function manifest = export_correlator_stage_vectors(outputDirectory)
%EXPORT_CORRELATOR_STAGE_VECTORS Write stage-level FFT-correlator vectors.
%
% Regenerates every committed acceptance case from
% LORA_VERIFY.STAGE_CASE_DEFINITIONS and writes:
%
%   <id>.f64       little-endian float64 payload, stages concatenated in
%                  LORA_VERIFY.STAGE_ORDER, column-major, complex
%                  interleaved as (real, imag)
%   manifest.json  schema version, per-case configuration, per-stage shape,
%                  byte offset, scale summary, expected decisions, SHA-256
%
% The numerical definition comes from LORA_PHY.FFT_CORRELATOR_STAGES, which
% also backs LORA_PHY.FFT_CORRELATOR_METRICS, so the vectors cannot drift
% away from the receiver.
%
% Usage:
%   manifest = export_correlator_stage_vectors;

rootDirectory = fileparts(mfilename("fullpath"));
addpath(rootDirectory);
if nargin < 1
    outputDirectory = lora_verify.stage_vector_directory;
end
outputDirectory = string(outputDirectory);
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end

definitions = lora_verify.stage_case_definitions;
[stageNames, stageComplex] = lora_verify.stage_order;

manifest = struct;
manifest.schema = "zynq-lora-phy-stage-vectors-v1";
manifest.description = "Stage-level golden vectors for the CSS FFT correlator";
manifest.generator = "export_correlator_stage_vectors";
manifest.numericalSource = "lora_phy.fft_correlator_stages";
manifest.matlabRelease = string(version("-release"));
manifest.byteOrder = "ieee-le";
manifest.elementOrder = "column-major; complex interleaved (real,imag)";
manifest.stageOrder = stageNames(:).';
manifest.stageComplex = stageComplex(:).';
manifest.cases = struct([]);

for k = 1:numel(definitions)
    definition = definitions(k);
    [window, info] = lora_verify.build_stage_case(definition);
    stages = lora_phy.fft_correlator_stages(window, info.config);

    dataFile = definition.id+".f64";
    dataPath = fullfile(outputDirectory, dataFile);
    layout = lora_verify.write_stage_vectors(dataPath, stages);

    entry = struct;
    entry.id = definition.id;
    entry.note = definition.note;
    entry.dataFile = dataFile;
    entry.sha256 = lora_verify.sha256_file(dataPath);
    entry.spreadingFactor = info.config.spreadingFactor;
    entry.samplesPerChip = info.config.samplesPerChip;
    entry.symbolCount = info.config.symbolCount;
    entry.samplesPerSymbol = info.config.samplesPerSymbol;
    entry.windowSymbols = numel(definition.symbols);
    entry.bandwidthHz = definition.bandwidthHz;
    entry.sampleRateHz = info.sampleRateHz;
    entry.frequencyOffsetHz = definition.frequencyOffsetHz;
    entry.fractionalDelaySamples = definition.fractionalDelaySamples;
    entry.integerOffsetSamples = definition.integerOffsetSamples;
    entry.snrDb = definition.snrDb;
    entry.randomSeed = definition.randomSeed;
    entry.transmittedSymbols = info.transmittedSymbols;
    entry.expectedSymbols = stages.symbols(:).';
    entry.expectedConfidence = stages.confidence(:).';
    entry.expectedPeak = stages.peak(:).';
    entry.stages = layout;
    manifest.cases = [manifest.cases; entry]; %#ok<AGROW>
end

manifestPath = fullfile(outputDirectory, "manifest.json");
file = fopen(manifestPath, "w");
if file < 0
    error("lora_verify:StageManifestFile", ...
        "Cannot open %s", manifestPath);
end
cleanup = onCleanup(@() fclose(file));
fprintf(file, "%s\n", jsonencode(manifest, "PrettyPrint", true));

if nargout == 0
    fprintf("Exported %d cases to %s\n", numel(manifest.cases), ...
        outputDirectory);
    clear manifest;
end
end
