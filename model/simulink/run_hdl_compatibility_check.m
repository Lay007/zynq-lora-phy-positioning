function report = run_hdl_compatibility_check(options)
%RUN_HDL_COMPATIBILITY_CHECK Run checkhdl on the generated M2 subsystems.
%
% The M2 criterion is not only that Simulink matches MATLAB but that the
% design passes HDL Coder's compatibility checker. This runs `checkhdl` on
% each named DUT and records every message it produces.
%
% It deliberately stops at `checkhdl`. Generating Verilog, cosimulating it,
% and synthesizing it are M3 and are not attempted here.
%
%   report = run_hdl_compatibility_check;
%   report = run_hdl_compatibility_check(WordLength=14);

arguments
    options.WordLength (1,1) double {mustBeInteger, mustBePositive} = 14
    options.SpreadingFactor (1,1) double = 7
    options.SamplesPerChip (1,1) double = 8
    options.OutputDirectory string = string.empty
    options.WriteCsv (1,1) logical = true
    options.Verbose (1,1) logical = true
end

simulinkRoot = fileparts(mfilename("fullpath"));
repositoryRoot = fileparts(fileparts(simulinkRoot));
addpath(simulinkRoot);
addpath(fullfile(repositoryRoot, "model", "matlab"));
if isempty(options.OutputDirectory)
    options.OutputDirectory = string(fullfile(repositoryRoot, "docs", "data"));
end

if ~license("test", "Simulink_HDL_Coder")
    error("lora_sim:NoHdlCoderLicense", ...
        "HDL Coder is licensed as Simulink_HDL_Coder and is not available");
end

targets = struct([]);

entry = struct;
entry.name = "fft-correlator-double";
entry.builder = @() build_fft_correlator_model( ...
    SpreadingFactor=options.SpreadingFactor, ...
    SamplesPerChip=options.SamplesPerChip, ...
    ModelName="lora_fft_correlator_hdl");
targets = [targets; entry];

entry = struct;
entry.name = "fft-correlator-fixed";
entry.builder = @() build_fft_correlator_model( ...
    SpreadingFactor=options.SpreadingFactor, ...
    SamplesPerChip=options.SamplesPerChip, DataType="fixed", ...
    WordLength=options.WordLength, ModelName="lora_fft_correlator_hdl");
targets = [targets; entry];

entry = struct;
entry.name = "joint-timing-cfo";
entry.builder = @() build_joint_sync_model( ...
    SpreadingFactor=options.SpreadingFactor, ...
    SamplesPerChip=options.SamplesPerChip, ...
    ModelName="lora_joint_sync_hdl");
targets = [targets; entry];

rows = {};
messageRows = {};

for k = 1:numel(targets)
    target = targets(k);
    info = target.builder();
    cleanup = onCleanup(@() closeGeneratedModel(info.modelName));
    if ~bdIsLoaded(info.modelName)
        load_system(info.modelPath);
    end
    % checkhdl compiles the model, and compilation initializes the From
    % Workspace sources of the test harness. Without stimulus in the base
    % workspace the model fails to initialize before any check can run.
    assignStimulus(info);

    % HDL Coder settings go through hdlset_param. set_param's TargetLang is
    % Simulink Coder's C/C++ selector and rejects "Verilog".
    hdlset_param(char(info.modelName), "TargetLanguage", "Verilog");
    errorCount = 0;
    warningCount = 0;
    failure = "";
    try
        messages = checkhdl(char(info.dutPath), ...
            "TargetDirectory", char(lora_sim.generated_directory));
        if isstruct(messages)
            for j = 1:numel(messages)
                messageRows{end+1} = table(string(target.name), ...
                    string(messages(j).level), ...
                    string(messages(j).type), ...
                    string(messages(j).path), ...
                    string(messages(j).MessageID), ...
                    string(regexprep(strtrim(messages(j).message), ...
                    "<[^>]*>", "")), ...
                    VariableNames=["Target", "Level", "Scope", "Path", ...
                    "MessageId", "Message"]); %#ok<AGROW>
            end
            % Severity lives in `level`; `type` is only model versus block.
            errorCount = sum(arrayfun(@(msg) ...
                strcmpi(msg.level, "error"), messages));
            warningCount = sum(arrayfun(@(msg) ...
                strcmpi(msg.level, "warning"), messages));
        end
    catch err
        failure = string(err.identifier)+": "+string(err.message);
        errorCount = NaN;
    end

    rows{end+1} = table(string(target.name), string(info.dutPath), ...
        options.SpreadingFactor, options.SamplesPerChip, ...
        errorCount, warningCount, failure, ...
        VariableNames=["Target", "Dut", "SF", "L", "Errors", "Warnings", ...
        "Failure"]); %#ok<AGROW>

    if options.Verbose
        fprintf("%-24s errors=%s warnings=%d %s\n", target.name, ...
            num2str(errorCount), warningCount, failure);
    end
    clear cleanup;
end

report = struct;
report.summary = vertcat(rows{:});
if isempty(messageRows)
    report.messages = table.empty;
else
    report.messages = vertcat(messageRows{:});
end
report.passed = all(report.summary.Errors == 0) && ...
    all(report.summary.Failure == "");

if options.WriteCsv
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(report.summary, fullfile(options.OutputDirectory, ...
        "simulink-m2-hdl-compatibility.csv"));
    if ~isempty(report.messages)
        writetable(report.messages, fullfile(options.OutputDirectory, ...
            "simulink-m2-hdl-messages.csv"));
    end
end

if options.Verbose
    fprintf("\n");
    disp(report.summary);
    if report.passed
        fprintf("checkhdl reports no errors for any M2 DUT.\n");
    else
        fprintf("checkhdl reported errors; see the message table.\n");
    end
end
end

function assignStimulus(info)
%ASSIGNSTIMULUS Minimal base-workspace stimulus so the model can compile.
samples = 8;
timeAxis = (0:samples-1).';
assignin("base", "stimulusIq", ...
    timeseries(complex(zeros(samples, 1)), timeAxis));
assignin("base", "stimulusValid", timeseries(false(samples, 1), timeAxis));
assignin("base", "stimulusUpBin", ...
    timeseries(zeros(samples, 1, "uint16"), timeAxis));
assignin("base", "stimulusDownBin", ...
    timeseries(zeros(samples, 1, "uint16"), timeAxis));
assignin("base", "stimulusBinValid", timeseries(false(samples, 1), timeAxis));
set_param(info.modelName, StopTime=num2str(samples-1));
end

function closeGeneratedModel(modelName)
if bdIsLoaded(modelName)
    set_param(modelName, Dirty="off");
    close_system(modelName, 0);
end
end
