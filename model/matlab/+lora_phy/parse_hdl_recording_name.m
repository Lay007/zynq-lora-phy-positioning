function metadata = parse_hdl_recording_name(filePath)
%PARSE_HDL_RECORDING_NAME Parse SF/BW/Fs metadata from an HDL IQ filename.
%
% Required naming convention:
%   hdl_sf<SF>_bw<BW_KHZ>k_fs<FS_KHZ>k_<TAG>.pcm
%
% Examples:
%   hdl_sf7_bw125k_fs2000k_package.pcm
%   hdl_sf7_bw125k_fs2000k_chirp-h17-up.pcm

filePath = string(filePath);
[~, baseName, extension] = fileparts(filePath);
fullName = lower(string(baseName) + string(extension));
expression = "^hdl_sf(?<sf>[0-9]+)_bw(?<bw>[0-9]+)k_fs(?<fs>[0-9]+)k_(?<tag>[a-z0-9-]+)\.pcm$";
parsed = regexp(fullName, expression, "names", "once");

if isempty(parsed)
    error("lora_phy:InvalidHdlRecordingName", ...
        ["HDL PCM filename must match " ...
         "hdl_sf<SF>_bw<BW_KHZ>k_fs<FS_KHZ>k_<TAG>.pcm"]);
end

metadata = struct;
metadata.filePath = filePath;
metadata.fileName = fullName;
metadata.format = "ci16";
metadata.spreadingFactor = str2double(parsed.sf);
metadata.bandwidthHz = 1e3 * str2double(parsed.bw);
metadata.sampleRateHz = 1e3 * str2double(parsed.fs);
metadata.tag = string(parsed.tag);

if metadata.spreadingFactor < 5 || metadata.spreadingFactor > 12
    error("lora_phy:InvalidHdlRecordingName", ...
        "SF encoded in filename must be in the range 5..12");
end
if metadata.bandwidthHz <= 0 || metadata.sampleRateHz <= 0
    error("lora_phy:InvalidHdlRecordingName", ...
        "BW and Fs encoded in filename must be positive");
end

samplesPerChip = metadata.sampleRateHz / metadata.bandwidthHz;
metadata.samplesPerChip = samplesPerChip;
metadata.integerSamplesPerChip = abs(samplesPerChip-round(samplesPerChip)) < 1e-9;
metadata.symbolSamples = 2^metadata.spreadingFactor * samplesPerChip;

% A package capture starts with the LoRa/CSS preamble, so the first golden
% comparison uses the reference h=0 upchirp. A single-chirp filename can
% encode a different symbol and direction explicitly.
metadata.referenceSymbol = 0;
metadata.referenceDirection = "up";
metadata.referenceDescription = "first preamble h=0 upchirp";
chirpTag = regexp(metadata.tag, ...
    "^chirp-h(?<symbol>[0-9]+)-(?<direction>up|down)$", ...
    "names", "once");
if ~isempty(chirpTag)
    metadata.referenceSymbol = str2double(chirpTag.symbol);
    metadata.referenceDirection = string(chirpTag.direction);
    metadata.referenceDescription = sprintf("h=%d %schirp", ...
        metadata.referenceSymbol, metadata.referenceDirection);
end

if metadata.referenceSymbol >= 2^metadata.spreadingFactor
    error("lora_phy:InvalidHdlRecordingName", ...
        "Symbol encoded in filename is outside the selected SF range");
end
end
