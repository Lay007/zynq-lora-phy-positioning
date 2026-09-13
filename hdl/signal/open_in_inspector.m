function [app, metadata] = open_in_inspector(fileName, options)
%OPEN_IN_INSPECTOR Open an HDL IQ recording in LoRa PHY Inspector.
%
% HDL recordings must follow:
%   hdl_sf<SF>_bw<BW_KHZ>k_fs<FS_KHZ>k_<TAG>.pcm
%
% File format is conventional complex int16 little-endian:
%   I0, Q0, I1, Q1, ...
%
%   open_in_inspector()                          English interface
%   open_in_inspector("<name>.pcm", Language="ru")  Russian interface
%
% Language selects the interface language only. Error messages stay in
% English, matching the rest of the project's diagnostics.

arguments
    fileName (1,1) string = ""
    options.Language (1,1) string {mustBeMember(options.Language, ["en", "ru"])} = "en"
end

signalDir = fileparts(mfilename("fullpath"));
repoRoot = fileparts(fileparts(signalDir));
matlabRoot = fullfile(repoRoot, "model", "matlab");
addpath(matlabRoot);
addpath(fullfile(matlabRoot, "apps"));

if strlength(fileName) == 0
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
strings = lora_phy.inspector_strings(options.Language);

app = lora_phy_inspector("on", Language=options.Language);
app.FileField.Value = char(metadata.filePath);
app.FormatDropDown.Value = "ci16";
app.SampleRateField.Value = metadata.sampleRateHz;
app.CentreFrequencyField.Value = 0;
app.ExpectedFrequencyField.Value = 0;

fprintf("%s\n", strings.consoleLoaded);
fprintf(strings.consoleFile, metadata.filePath);
fprintf("%s\n", strings.consoleFormat);
fprintf(strings.consoleSf, metadata.spreadingFactor);
fprintf(strings.consoleBw, metadata.bandwidthHz/1e3);
fprintf(strings.consoleFs, metadata.sampleRateHz/1e6);
fprintf(strings.consoleGolden, lora_phy.describe_reference(metadata, strings));
fprintf("%s\n", strings.consoleHint);
end
