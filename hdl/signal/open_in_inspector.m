function [app, metadata] = open_in_inspector(fileName)
%OPEN_IN_INSPECTOR Open an HDL IQ recording in LoRa PHY Inspector.
%
% HDL recordings must follow:
%   hdl_sf<SF>_bw<BW_KHZ>k_fs<FS_KHZ>k_<TAG>.pcm
%
% File format is conventional complex int16 little-endian:
%   I0, Q0, I1, Q1, ...
%
% Example:
%   open_in_inspector("hdl_sf7_bw125k_fs2000k_package.pcm")

signalDir = fileparts(mfilename("fullpath"));
repoRoot = fileparts(fileparts(signalDir));
matlabRoot = fullfile(repoRoot, "model", "matlab");
addpath(matlabRoot);
addpath(fullfile(matlabRoot, "apps"));

if nargin < 1 || strlength(string(fileName)) == 0
    recordings = dir(fullfile(signalDir, "hdl_sf*_bw*k_fs*k_*.pcm"));
    if numel(recordings) == 1
        filePath = fullfile(recordings(1).folder, recordings(1).name);
    elseif numel(recordings) > 1
        names = string({recordings.name});
        error("lora_phy:MultipleHdlRecordings", ...
            "Several HDL recordings are present. Pass one explicitly:\n%s", ...
            strjoin(names, newline));
    else
        error("lora_phy:HdlRecordingNotFound", ...
            ["No HDL PCM recording matching the required naming convention " ...
             "was found in %s"], signalDir);
    end
else
    fileName = string(fileName);
    if isfile(fileName)
        filePath = char(fileName);
    else
        filePath = fullfile(signalDir, char(fileName));
    end
    if ~isfile(filePath)
        error("lora_phy:HdlRecordingNotFound", ...
            "HDL PCM recording does not exist: %s", filePath);
    end
end

[~, baseName, extension] = fileparts(filePath);
fullName = string(baseName) + string(extension);
expression = "^hdl_sf(?<sf>[0-9]+)_bw(?<bw>[0-9]+)k_fs(?<fs>[0-9]+)k_(?<tag>[a-z0-9-]+)\.pcm$";
parsed = regexp(fullName, expression, "names", "once");

if isempty(parsed)
    error("lora_phy:InvalidHdlRecordingName", ...
        ["HDL PCM filename must match " ...
         "hdl_sf<SF>_bw<BW_KHZ>k_fs<FS_KHZ>k_<TAG>.pcm"]);
end

metadata = struct;
metadata.filePath = string(filePath);
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

app = lora_phy_inspector;
app.FileField.Value = char(metadata.filePath);
app.FormatDropDown.Value = "ci16";
app.SampleRateField.Value = metadata.sampleRateHz;
app.CentreFrequencyField.Value = 0;
app.ExpectedFrequencyField.Value = 0;

fprintf("Loaded HDL recording into LoRa PHY Inspector:\n");
fprintf("  file: %s\n", metadata.filePath);
fprintf("  format: ci16 (little-endian I,Q interleaved)\n");
fprintf("  SF: %d\n", metadata.spreadingFactor);
fprintf("  BW: %.0f kHz\n", metadata.bandwidthHz/1e3);
fprintf("  Fs: %.3f MHz\n", metadata.sampleRateHz/1e6);
fprintf("Press Analyze in the Inspector window to run the DSP analysis.\n");
end
