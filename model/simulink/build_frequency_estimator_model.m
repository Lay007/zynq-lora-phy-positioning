function info = build_frequency_estimator_model(options)
%BUILD_FREQUENCY_ESTIMATOR_MODEL Build the frequency-only estimator DUT.
%
% The block consumes the dechirped peak bins of one preamble upchirp and
% one SFD downchirp. Whole-chip timing moves those bins in opposite
% directions, while carrier offset moves both in the same direction. Their
% signed sum is therefore exactly twice the carrier offset in FFT bins:
%
%   cfoHalfBins = signed(upBin) + signed(downBin)
%
% Inputs and outputs are registered so out-of-context synthesis has a real
% register-to-register timing path. The resulting latency is two clocks.

arguments
    options.SpreadingFactor (1,1) double {mustBeInteger} = 7
    options.SamplesPerChip (1,1) double {mustBeInteger} = 8
    options.ModelName (1,1) string = "lora_frequency_estimator"
    options.OutputDirectory (1,1) string = lora_sim.generated_directory
    options.Save (1,1) logical = true
end

config = lora_phy.css_config(options.SpreadingFactor, ...
    options.SamplesPerChip);
modelName = options.ModelName;
modelPath = fullfile(options.OutputDirectory, modelName+".slx");

if bdIsLoaded(modelName)
    set_param(modelName, Dirty="off");
    close_system(modelName, 0);
end
if isfile(modelPath)
    delete(modelPath);
end

new_system(modelName);
try
    info = populateModel(modelName, config, options, modelPath);
catch err
    closeIfLoaded(modelName);
    rethrow(err);
end
end

function info = populateModel(modelName, config, options, modelPath)
n = config.symbolCount;

dut = modelName+"/DUT";
add_block("simulink/Ports & Subsystems/Subsystem", dut, ...
    Position=[230 80 470 290]);
delete_line(dut, "In1/1", "Out1/1");
delete_block(dut+"/In1");
delete_block(dut+"/Out1");

addPort(dut, "simulink/Sources/In1", "upBin", 1, [30 50]);
addPort(dut, "simulink/Sources/In1", "downBin", 2, [30 110]);
addPort(dut, "simulink/Sources/In1", "binValid", 3, [30 170]);
if n <= double(intmax("uint8"))+1
    binDataType = "uint8";
else
    binDataType = "uint16";
end
set_param(dut+"/upBin", OutDataTypeStr=binDataType);
set_param(dut+"/downBin", OutDataTypeStr=binDataType);

add_block("simulink/Discrete/Unit Delay", dut+"/UpBinRegister", ...
    Position=[100 45 140 75], InitialCondition="0");
add_block("simulink/Discrete/Unit Delay", dut+"/DownBinRegister", ...
    Position=[100 105 140 135], InitialCondition="0");
add_block("simulink/Discrete/Unit Delay", dut+"/ValidInputRegister", ...
    Position=[100 165 140 195], InitialCondition="0");

add_block("simulink/User-Defined Functions/MATLAB Function", ...
    dut+"/FrequencyEstimator", Position=[190 55 370 175]);
lora_sim.set_function_script(dut+"/FrequencyEstimator", [
    "function [cfoHalfBins, estimateValid] = fcn(upBin, downBin, binValid)"
    "%#codegen"
    "% Map [0,N) bins to [-N/2,N/2), then add. The sum is exactly"
    "% twice the CFO in bins, so no divider or rounding is required."
    "% int16 covers the full SF12 sum range [-4096,4094]."
    "upSigned = int16(upBin);"
    "if upSigned >= int16(" + (n/2) + ")"
    "    upSigned = upSigned - int16(" + n + ");"
    "end"
    "downSigned = int16(downBin);"
    "if downSigned >= int16(" + (n/2) + ")"
    "    downSigned = downSigned - int16(" + n + ");"
    "end"
    ""
    "cfoHalfBins = upSigned + downSigned;"
    "estimateValid = binValid;"
    "if ~binValid"
    "    cfoHalfBins = int16(0);"
    "end"
    "end"]);

add_block("simulink/Discrete/Unit Delay", dut+"/CfoOutputRegister", ...
    Position=[410 75 450 105], InitialCondition="0");
add_block("simulink/Discrete/Unit Delay", dut+"/ValidOutputRegister", ...
    Position=[410 135 450 165], InitialCondition="0");

add_line(dut, "upBin/1", "UpBinRegister/1", autorouting="on");
add_line(dut, "downBin/1", "DownBinRegister/1", autorouting="on");
add_line(dut, "binValid/1", "ValidInputRegister/1", autorouting="on");
add_line(dut, "UpBinRegister/1", "FrequencyEstimator/1", ...
    autorouting="on");
add_line(dut, "DownBinRegister/1", "FrequencyEstimator/2", ...
    autorouting="on");
add_line(dut, "ValidInputRegister/1", "FrequencyEstimator/3", ...
    autorouting="on");
add_line(dut, "FrequencyEstimator/1", "CfoOutputRegister/1", ...
    autorouting="on");
add_line(dut, "FrequencyEstimator/2", "ValidOutputRegister/1", ...
    autorouting="on");

addOutport(dut, "cfoHalfBins", 1, [500 80], "CfoOutputRegister/1");
addOutport(dut, "estimateValid", 2, [500 140], ...
    "ValidOutputRegister/1");
set_param(dut, TreatAsAtomicUnit="on");

sources = ["stimulusUpBin", "stimulusDownBin", "stimulusBinValid"];
for k = 1:numel(sources)
    block = modelName+"/Source_"+sources(k);
    top = 60+(k-1)*70;
    add_block("simulink/Sources/From Workspace", block, ...
        Position=[30 top 155 top+40]);
    set_param(block, VariableName=sources(k), SampleTime="1", ...
        Interpolate="off", OutputAfterFinalValue="Setting to zero");
    add_line(modelName, "Source_"+sources(k)+"/1", ...
        sprintf("DUT/%d", k), autorouting="on");
end

outputs = ["cfoHalfBins", "estimateValid"];
for k = 1:numel(outputs)
    block = modelName+"/Log_"+outputs(k);
    top = 80+(k-1)*80;
    add_block("simulink/Sinks/To Workspace", block, ...
        Position=[540 top 665 top+35]);
    set_param(block, VariableName=outputs(k), SaveFormat="Array", ...
        SampleTime="-1", MaxDataPoints="inf");
    add_line(modelName, sprintf("DUT/%d", k), "Log_"+outputs(k)+"/1", ...
        autorouting="on");
end

set_param(modelName, SolverType="Fixed-step", Solver="FixedStepDiscrete", ...
    FixedStep="1", StartTime="0", StopTime="100", SaveOutput="off", ...
    SaveTime="off", SignalLogging="off", ReturnWorkspaceOutputs="on");

if options.Save
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    save_system(modelName, modelPath);
end

info = struct;
info.modelName = modelName;
info.modelPath = string(modelPath);
info.dutPath = dut;
info.spreadingFactor = config.spreadingFactor;
info.samplesPerChip = config.samplesPerChip;
info.symbolCount = n;
info.samplesPerSymbol = config.samplesPerSymbol;
info.latencyCycles = 2;
info.binDataType = binDataType;
info.outputVariables = outputs;
end

function closeIfLoaded(modelName)
if bdIsLoaded(modelName)
    set_param(modelName, Dirty="off");
    close_system(modelName, 0);
end
end

function addPort(parent, library, name, portNumber, position)
block = parent+"/"+name;
add_block(library, block, ...
    Position=[position(1) position(2) position(1)+30 position(2)+20]);
set_param(block, Port=num2str(portNumber));
end

function addOutport(parent, name, portNumber, position, sourcePort)
block = parent+"/"+name;
add_block("simulink/Sinks/Out1", block, ...
    Position=[position(1) position(2) position(1)+30 position(2)+20]);
set_param(block, Port=num2str(portNumber));
add_line(parent, sourcePort, name+"/1", autorouting="on");
end
