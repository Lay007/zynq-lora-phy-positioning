function info = build_joint_sync_model(options)
%BUILD_JOINT_SYNC_MODEL Generate the joint timing/CFO estimator model.
%
% This is the second M2 subsystem. It consumes the dechirped peak bin of
% one preamble upchirp and one SFD downchirp and separates whole-chip
% timing from carrier offset, which is the M1 result that made the coherent
% branch deterministic on real captures.
%
%   info = build_joint_sync_model(SpreadingFactor=7, SamplesPerChip=8);
%
% Everything is integer arithmetic in units of half a bin, so the DUT is
% bit-exact against LORA_PHY.JOINT_TIMING_CFO_FROM_BINS rather than merely
% close. No fixed-point tolerance applies here and none is claimed.

arguments
    options.SpreadingFactor (1,1) double {mustBeInteger} = 7
    options.SamplesPerChip (1,1) double {mustBeInteger} = 8
    options.ModelName (1,1) string = "lora_joint_sync"
    options.OutputDirectory (1,1) string = lora_sim.generated_directory
    options.Save (1,1) logical = true
end

config = lora_phy.css_config(options.SpreadingFactor, options.SamplesPerChip);
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
% A plain try/catch rather than onCleanup: an onCleanup guard would have to
% be cleared at the end of the function, and clearing it runs the cleanup,
% which would close the very model the caller is about to simulate.
try
    info = populateModel(modelName, config, options, modelPath);
catch err
    closeIfLoaded(modelName);
    rethrow(err);
end
end

function info = populateModel(modelName, config, options, modelPath)
n = config.symbolCount;
m = config.samplesPerSymbol;
l = config.samplesPerChip;

workspace = get_param(modelName, "ModelWorkspace");
assignin(workspace, "N", n);
assignin(workspace, "M", m);
assignin(workspace, "L", l);

dut = modelName+"/DUT";
add_block("simulink/Ports & Subsystems/Subsystem", dut, ...
    Position=[240 80 420 300]);
delete_line(dut, "In1/1", "Out1/1");
delete_block(dut+"/In1");
delete_block(dut+"/Out1");

addPort(dut, "simulink/Sources/In1", "upBin", 1, [40 60]);
addPort(dut, "simulink/Sources/In1", "downBin", 2, [40 120]);
addPort(dut, "simulink/Sources/In1", "binValid", 3, [40 180]);

add_block("simulink/User-Defined Functions/MATLAB Function", ...
    dut+"/JointEstimator", Position=[180 50 380 200]);
lora_sim.set_function_script(dut+"/JointEstimator", [
    "function [correctionSamples, cfoHalfBins, timingHalfChips, estimateValid, timingRejected] = fcn(upBin, downBin, binValid)"
    "%#codegen"
    "% Signed bin: [0, N) mapped to [-N/2, N/2)."
    "% cfoHalfBins     = 2*(upSigned + downSigned)/2 = upSigned + downSigned"
    "% timingHalfChips = 2*(upSigned - downSigned)/2 = upSigned - downSigned"
    "% Both are exact integers, so nothing here rounds."
    "upSigned = int32(upBin);"
    "if upSigned >= int32(" + (n/2) + ")"
    "    upSigned = upSigned - int32(" + n + ");"
    "end"
    "downSigned = int32(downBin);"
    "if downSigned >= int32(" + (n/2) + ")"
    "    downSigned = downSigned - int32(" + n + ");"
    "end"
    ""
    "cfoHalfBins = upSigned + downSigned;"
    "timingHalfChips = upSigned - downSigned;"
    ""
    "% round(-timingChips*L) with ties away from zero, on integers."
    "scaled = -timingHalfChips*int32(" + l + ");"
    "magnitude = abs(scaled);"
    "rounded = idivide(magnitude + int32(1), int32(2), 'floor');"
    "correctionSamples = rounded;"
    "if scaled < int32(0)"
    "    correctionSamples = -rounded;"
    "end"
    ""
    "timingRejected = abs(correctionSamples) > int32(" + (m/2+l) + ");"
    "if timingRejected"
    "    correctionSamples = int32(0);"
    "end"
    ""
    "estimateValid = binValid;"
    "if ~binValid"
    "    correctionSamples = int32(0);"
    "    cfoHalfBins = int32(0);"
    "    timingHalfChips = int32(0);"
    "    timingRejected = false;"
    "end"
    "end"]);

add_line(dut, "upBin/1", "JointEstimator/1", autorouting="on");
add_line(dut, "downBin/1", "JointEstimator/2", autorouting="on");
add_line(dut, "binValid/1", "JointEstimator/3", autorouting="on");

addOutport(dut, "correctionSamples", 1, [520 50], "JointEstimator/1");
addOutport(dut, "cfoHalfBins", 2, [520 100], "JointEstimator/2");
addOutport(dut, "timingHalfChips", 3, [520 150], "JointEstimator/3");
addOutport(dut, "estimateValid", 4, [520 200], "JointEstimator/4");
addOutport(dut, "timingRejected", 5, [520 250], "JointEstimator/5");
set_param(dut, TreatAsAtomicUnit="on");

% --- harness ---------------------------------------------------------------
sources = ["stimulusUpBin", "stimulusDownBin", "stimulusBinValid"];
for k = 1:numel(sources)
    block = modelName+"/Source_"+sources(k);
    top = 60+(k-1)*70;
    add_block("simulink/Sources/From Workspace", block, ...
        Position=[40 top 160 top+40]);
    set_param(block, VariableName=sources(k), SampleTime="1", ...
        Interpolate="off", OutputAfterFinalValue="Setting to zero");
    add_line(modelName, "Source_"+sources(k)+"/1", ...
        sprintf("DUT/%d", k), autorouting="on");
end

outputs = ["correctionSamples", "cfoHalfBins", "timingHalfChips", ...
    "estimateValid", "timingRejected"];
for k = 1:numel(outputs)
    block = modelName+"/Log_"+outputs(k);
    top = 60+(k-1)*60;
    add_block("simulink/Sinks/To Workspace", block, ...
        Position=[520 top 640 top+35]);
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
info.samplesPerChip = l;
info.symbolCount = n;
info.samplesPerSymbol = m;
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
