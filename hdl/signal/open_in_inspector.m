function [app, metadata] = open_in_inspector(fileName)
%OPEN_IN_INSPECTOR Open an HDL IQ recording in LoRa PHY Inspector.
%
% HDL recordings must follow:
%   hdl_sf<SF>_bw<BW_KHZ>k_fs<FS_KHZ>k_<TAG>.pcm
%
% File format is conventional complex int16 little-endian:
%   I0, Q0, I1, Q1, ...

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

metadata = lora_phy.parse_hdl_recording_name(filePath);

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
fprintf("  golden reference: %s\n", metadata.referenceDescription);
fprintf("Press Analyze to run DSP analysis and MATLAB golden verification.\n");
end
