function [app, metadata] = run_inspector(fileName, options)
%RUN_INSPECTOR Open an HDL IQ recording from this folder in LoRa PHY Inspector.
%
% Scratch wrapper around hdl/signal/open_in_inspector for recordings dropped
% next to this script, so naming rules, CI16 format and golden reference
% selection stay identical to the ones the project CI uses:
%   hdl_sf<SF>_bw<BW_KHZ>k_fs<FS_KHZ>k_<TAG>.pcm
%
%   run_inspector                          the only recording here, Russian UI
%   run_inspector("<name>.pcm")            that recording, Russian UI
%   run_inspector("", Language="en")       English UI
%
% Language selects the interface language only; every measurement and golden
% verdict is identical either way. Press Analyze in the app to run the DSP
% analysis and golden verification.

arguments
    fileName (1,1) string = ""
    options.Language (1,1) string {mustBeMember(options.Language, ["en", "ru"])} = "ru"
end

testModDir = fileparts(mfilename("fullpath"));
repoRoot = fileparts(fileparts(testModDir));
addpath(fullfile(repoRoot, "hdl", "signal"));

if strlength(fileName) == 0
    recordings = dir(fullfile(testModDir, "hdl_sf*_bw*k_fs*k_*.pcm"));
    if isempty(recordings)
        error("lora_phy:HdlRecordingNotFound", ...
            ["No HDL PCM recording matching the required naming convention " ...
             "was found in %s"], testModDir);
    elseif numel(recordings) > 1
        error("lora_phy:MultipleHdlRecordings", ...
            "Several HDL recordings are present. Pass one explicitly:\n%s", ...
            strjoin(string({recordings.name}), newline));
    end
    filePath = fullfile(recordings(1).folder, recordings(1).name);
else
    filePath = fileName;
    if ~isfile(filePath)
        filePath = string(fullfile(testModDir, char(filePath)));
    end
end

[app, metadata] = open_in_inspector(filePath, Language=options.Language);
end
