function metadata = parse_hdl_recording_name(filePath)
%PARSE_HDL_RECORDING_NAME Parse SF/BW/Fs metadata from an HDL IQ filename.
%
% Required naming convention:
%   hdl_sf<SF>_bw<BW_KHZ>k_fs<FS_KHZ>k_<TAG>.pcm
%
% Supported tags and TX checkpoints:
%   chirp-h<SYMBOL>-up/down  -> stage 1, one chirp at 2.000 MS/s
%   package                  -> stage 2, current package stream at 2.000 MS/s
%   resampler                -> stage 3, after 24/25 resampler at 1.920 MS/s
%   cic                      -> stage 4, after CIC x32 at 61.440 MS/s
%   mixer                    -> stage 5, after frequency shift at 61.440 MS/s
%
% Examples:
%   hdl_sf7_bw125k_fs2000k_chirp-h17-up.pcm
%   hdl_sf7_bw125k_fs2000k_package.pcm
%   hdl_sf7_bw125k_fs1920k_resampler.pcm
%   hdl_sf7_bw125k_fs61440k_cic.pcm
%   hdl_sf7_bw125k_fs61440k_mixer.pcm

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

metadata.referenceSymbol = 0;
metadata.referenceDirection = "up";
metadata.referenceDescription = "first preamble h=0 upchirp";
metadata.stageNumber = NaN;
metadata.stageName = "";
metadata.expectedSampleRateHz = NaN;

if metadata.tag == "package"
    metadata.stageNumber = 2;
    metadata.stageName = "Package";
    metadata.expectedSampleRateHz = 2e6;
elseif metadata.tag == "resampler"
    metadata.stageNumber = 3;
    metadata.stageName = "Resampler 24/25";
    metadata.expectedSampleRateHz = 1.92e6;
    metadata.referenceSymbol = NaN;
    metadata.referenceDirection = "";
    metadata.referenceDescription = "TX stage 3 after 24/25 resampler";
elseif metadata.tag == "cic"
    metadata.stageNumber = 4;
    metadata.stageName = "CIC x32";
    metadata.expectedSampleRateHz = 61.44e6;
    metadata.referenceSymbol = NaN;
    metadata.referenceDirection = "";
    metadata.referenceDescription = "TX stage 4 after CIC x32";
elseif metadata.tag == "mixer"
    metadata.stageNumber = 5;
    metadata.stageName = "Frequency shift";
    metadata.expectedSampleRateHz = 61.44e6;
    metadata.referenceSymbol = NaN;
    metadata.referenceDirection = "";
    metadata.referenceDescription = "TX stage 5 after frequency shift";
else
    chirpTag = regexp(metadata.tag, ...
        "^chirp-h(?<symbol>[0-9]+)-(?<direction>up|down)$", ...
        "names", "once");
    if isempty(chirpTag)
        error("lora_phy:InvalidHdlRecordingTag", ...
            "HDL PCM tag must be package, resampler, cic, mixer or chirp-h<SYMBOL>-up/down; ambiguous tags such as chirp are not allowed");
    end
    metadata.stageNumber = 1;
    metadata.stageName = "Chirp";
    metadata.expectedSampleRateHz = 2e6;
    metadata.referenceSymbol = str2double(chirpTag.symbol);
    metadata.referenceDirection = string(chirpTag.direction);
    metadata.referenceDescription = sprintf("h=%d %schirp", ...
        metadata.referenceSymbol, metadata.referenceDirection);
end

metadata.sampleRateMatchesStage = ...
    abs(metadata.sampleRateHz-metadata.expectedSampleRateHz) <= 0.5;

if metadata.stageNumber == 1 && ...
        metadata.referenceSymbol >= 2^metadata.spreadingFactor
    error("lora_phy:InvalidHdlRecordingName", ...
        "Symbol encoded in filename is outside the selected SF range");
end
end
