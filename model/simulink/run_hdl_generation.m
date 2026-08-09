function report = run_hdl_generation(options)
%RUN_HDL_GENERATION Generate Verilog for the M2 DUTs and report resources.
%
% This is the first M3 step and it stops where the installed toolchain
% stops. It generates Verilog with HDL Coder and collects the resource
% utilization report that HDL Coder derives from the generated code.
%
% It does NOT synthesize and it does NOT cosimulate. Neither is a design
% limitation: no Vivado and no HDL simulator are installed on this host, so
% `Fmax`, timing, and power cannot be measured here and are not claimed.
% The resource numbers below are HDL Coder's count of inferred operators,
% not a synthesis result.
%
%   report = run_hdl_generation;
%   report = run_hdl_generation(WordLength=16, SpreadingFactor=7);

arguments
    options.WordLength (1,1) double {mustBeInteger, mustBePositive} = 16
    options.SpreadingFactor (1,1) double = 7
    options.SamplesPerChip (1,1) double = 8
    options.TargetDirectory string = string.empty
    options.OutputDirectory string = string.empty
    options.WriteCsv (1,1) logical = true
    options.Verbose (1,1) logical = true
end

simulinkRoot = fileparts(mfilename("fullpath"));
repositoryRoot = fileparts(fileparts(simulinkRoot));
addpath(simulinkRoot);
addpath(fullfile(repositoryRoot, "model", "matlab"));
if isempty(options.TargetDirectory)
    options.TargetDirectory = string(fullfile(repositoryRoot, "fpga", ...
        "generated"));
end
if isempty(options.OutputDirectory)
    options.OutputDirectory = string(fullfile(repositoryRoot, "docs", "data"));
end

if ~license("test", "Simulink_HDL_Coder")
    error("lora_sim:NoHdlCoderLicense", ...
        "HDL Coder is licensed as Simulink_HDL_Coder and is not available");
end

targets = struct([]);
entry = struct;
entry.name = "fft-correlator-fixed";
entry.builder = @() build_fft_correlator_model( ...
    SpreadingFactor=options.SpreadingFactor, ...
    SamplesPerChip=options.SamplesPerChip, DataType="fixed", ...
    WordLength=options.WordLength, IncludeVerificationTaps=false, ...
    ModelName="lora_fft_correlator_gen");
targets = [targets; entry];

entry = struct;
entry.name = "joint-timing-cfo";
entry.builder = @() build_joint_sync_model( ...
    SpreadingFactor=options.SpreadingFactor, ...
    SamplesPerChip=options.SamplesPerChip, ...
    ModelName="lora_joint_sync_gen");
targets = [targets; entry];

rows = {};
failures = strings(0, 1);

for k = 1:numel(targets)
    target = targets(k);
    info = target.builder();
    cleanup = onCleanup(@() closeGeneratedModel(info.modelName));
    if ~bdIsLoaded(info.modelName)
        load_system(info.modelPath);
    end
    assignStimulus(info);

    targetDirectory = fullfile(options.TargetDirectory, target.name);
    if isfolder(targetDirectory)
        rmdir(targetDirectory, "s");
    end
    mkdir(targetDirectory);

    hdlset_param(char(info.modelName), "TargetLanguage", "Verilog");
    hdlset_param(char(info.modelName), "TargetDirectory", ...
        char(targetDirectory));
    hdlset_param(char(info.modelName), "ResourceReport", "on");
    hdlset_param(char(info.modelName), "GenerateHDLTestBench", "off");

    generated = 0;
    failure = "";
    try
        makehdl(char(info.dutPath));
        files = dir(fullfile(targetDirectory, "**", "*.v"));
        generated = numel(files);
    catch err
        failure = string(err.identifier)+": "+string(err.message);
    end

    resources = readResourceReport(targetDirectory);
    rows{end+1} = table(string(target.name), string(info.dutPath), ...
        options.SpreadingFactor, options.SamplesPerChip, ...
        options.WordLength, generated, resources.multipliers, ...
        resources.adders, resources.registers, resources.registerBits, ...
        resources.rams, resources.multiplexers, resources.ioBits, ...
        resources.pipelineLatency, failure, ...
        VariableNames=["Target", "Dut", "SF", "L", "WordLength", ...
        "VerilogFiles", "Multipliers", "AddersSubtractors", "Registers", ...
        "RegisterBits", "RAMs", "Multiplexers", "IoBits", ...
        "AddedPipelineLatency", "Failure"]); %#ok<AGROW>

    if failure ~= ""
        failures(end+1, 1) = target.name+": "+failure; %#ok<AGROW>
    elseif generated == 0
        failures(end+1, 1) = target.name+": no Verilog produced"; %#ok<AGROW>
    end
    if options.Verbose
        fprintf("%-22s files=%-3d mult=%-5s add=%-5s reg=%-6s ram=%-5s latency=%-4s %s\n", ...
            target.name, generated, num2str(resources.multipliers), ...
            num2str(resources.adders), num2str(resources.registers), ...
            num2str(resources.rams), num2str(resources.pipelineLatency), ...
            failure);
    end
    clear cleanup;
end

report = struct;
report.summary = vertcat(rows{:});
report.failures = failures;
report.passed = isempty(failures);
report.targetDirectory = options.TargetDirectory;
report.synthesized = false;
report.cosimulated = false;

if options.WriteCsv
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(report.summary, fullfile(options.OutputDirectory, ...
        "simulink-m3-hdl-generation.csv"));
end

if options.Verbose
    fprintf("\n");
    disp(report.summary);
    if report.passed
        fprintf("Verilog generated. Not synthesized and not cosimulated: " + ...
            "no Vivado and no HDL simulator on this host.\n");
    else
        fprintf("FAILURES:\n  %s\n", strjoin(failures, newline+"  "));
    end
end
end

function resources = readResourceReport(targetDirectory)
%READRESOURCEREPORT Operator counts and added pipeline latency from HDL Coder.
%
% These come from HDL Coder's generic resource report ("bill of materials"),
% which counts operators inferred from the generated code. They are NOT
% synthesis results and must never be reported as LUT/FF/DSP/BRAM.
%
% PipelineLatency is the extra latency HDL Coder's delay balancing adds on
% top of the model, so hardware latency is the model latency plus this.
resources = struct("multipliers", NaN, "adders", NaN, "registers", NaN, ...
    "registerBits", NaN, "rams", NaN, "multiplexers", NaN, ...
    "ioBits", NaN, "pipelineLatency", NaN);

bom = dir(fullfile(targetDirectory, "**", "*bill_of_materials.html"));
if ~isempty(bom)
    text = flattenReport(fullfile(bom(1).folder, bom(1).name));
    summary = extractBetween(text, "Summary", "Detailed Report");
    if isempty(summary)
        summary = string(text);
    else
        summary = summary(1);
    end
    resources.multipliers = scalarAfter(summary, "Multipliers");
    resources.adders = scalarAfter(summary, "Adders/Subtractors");
    resources.registers = scalarAfter(summary, "Registers");
    resources.registerBits = scalarAfter(summary, "Total 1-Bit Registers");
    resources.rams = scalarAfter(summary, "RAMs");
    resources.multiplexers = scalarAfter(summary, "Multiplexers");
    resources.ioBits = scalarAfter(summary, "I/O Bits");
end

delays = dir(fullfile(targetDirectory, "**", "*delay_balancing.html"));
if ~isempty(delays)
    text = flattenReport(fullfile(delays(1).folder, delays(1).name));
    tokens = regexp(text, "/DUT/\w+\s+(\d+)\s+\d+", "tokens");
    if ~isempty(tokens)
        values = cellfun(@(c) str2double(c{1}), tokens);
        resources.pipelineLatency = max(values);
    end
end
end

function text = flattenReport(path)
text = fileread(path);
text = regexprep(text, "<[^>]*>", " ");
text = string(regexprep(text, "\s+", " "));
end

function value = scalarAfter(text, label)
value = NaN;
pattern = regexptranslate("escape", label)+"\s+([0-9]+)";
token = regexp(text, pattern, "tokens", "once");
if ~isempty(token)
    value = str2double(token{1});
end
end

function assignStimulus(info)
%ASSIGNSTIMULUS Minimal base-workspace stimulus so the model can compile.
samples = 8;
timeAxis = (0:samples-1).';
assignin("base", "stimulusIq", ...
    timeseries(complex(zeros(samples, 1)), timeAxis));
assignin("base", "stimulusValid", timeseries(false(samples, 1), timeAxis));
assignin("base", "stimulusReset", timeseries(false(samples, 1), timeAxis));
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
