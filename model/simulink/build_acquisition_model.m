function info = build_acquisition_model(options)
%BUILD_ACQUISITION_MODEL Generate the preamble/sync acceptance state machine.
%
% Third M2 subsystem. It consumes the correlator's symbol stream and decides
% whether the symbols seen so far look like a LoRa acquisition sequence:
%
%   PreambleSymbols upchirps near bin 0, then two sync symbols near the bins
%   the sync word encodes, each within BinTolerance on a circular metric.
%
%   info = build_acquisition_model(SpreadingFactor=7, PreambleSymbols=8);
%
% Like the joint timing/CFO estimator this is integer arithmetic on bins, so
% the DUT is bit-exact against LORA_PHY.VALIDATE_ACQUISITION_BINS rather than
% close, and no fixed-point type is involved.
%
% The circular distance is computed by comparison rather than with mod().
% mod() on a signed value is a division with Floor rounding, which HDL Coder
% refuses to generate. checkhdl accepted it; makehdl did not, which is why
% generation and not the compatibility checker is the real gate.
%
% What this is not: it does not search for the packet start. It validates a
% symbol-aligned candidate. The blind search over sample offsets is the
% expensive part of acquisition and is not built.

arguments
    options.SpreadingFactor (1,1) double {mustBeInteger} = 7
    options.PreambleSymbols (1,1) double {mustBeInteger, mustBePositive} = 8
    options.BinTolerance (1,1) double {mustBeInteger, mustBeNonnegative} = 1
    options.ModelName (1,1) string = "lora_acquisition"
    options.OutputDirectory (1,1) string = lora_sim.generated_directory
    options.Save (1,1) logical = true
end

config = lora_phy.css_config(options.SpreadingFactor, 1);
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
preambleSymbols = options.PreambleSymbols;

dut = modelName+"/DUT";
add_block("simulink/Ports & Subsystems/Subsystem", dut, ...
    Position=[240 80 440 320]);
delete_line(dut, "In1/1", "Out1/1");
delete_block(dut+"/In1");
delete_block(dut+"/Out1");

addPort(dut, "symbolIndex", 1, [40 60]);
addPort(dut, "symbolValid", 2, [40 120]);
addPort(dut, "syncWord", 3, [40 180]);
addPort(dut, "resetIn", 4, [40 240]);

add_block("simulink/User-Defined Functions/MATLAB Function", ...
    dut+"/AcquisitionFsm", Position=[180 40 420 280]);
lora_sim.set_function_script(dut+"/AcquisitionFsm", [
    "function [preambleDetected, syncValid, acquisitionFailed, symbolsSeen] = fcn(symbolIndex, symbolValid, syncWord, resetIn)"
    "%#codegen"
    "% Circular distance of a bin from a target, in bins."
    "%   d = |mod(bin - target + N/2, N) - N/2|"
    "% Everything here is integer, so the DUT is bit-exact against"
    "% lora_phy.validate_acquisition_bins."
    "persistent counter preambleOk syncOk"
    "if isempty(counter)"
    "    counter = uint32(0);"
    "    preambleOk = true;"
    "    syncOk = true;"
    "end"
    "if resetIn"
    "    counter = uint32(0);"
    "    preambleOk = true;"
    "    syncOk = true;"
    "end"
    ""
    "preambleDetected = false;"
    "syncValid = false;"
    "acquisitionFailed = false;"
    ""
    "if symbolValid"
    "    bin = int32(symbolIndex);"
    "    if counter < uint32(" + preambleSymbols + ")"
    "        target = int32(0);"
    "    elseif counter == uint32(" + preambleSymbols + ")"
    "        target = int32(8)*int32(bitshift(uint8(syncWord), -4));"
    "    else"
    "        target = int32(8)*int32(bitand(uint8(syncWord), uint8(15)));"
    "    end"
    "    % Circular wrap by comparison, not by mod. mod() on a signed value"
    "    % becomes a division with Floor rounding, which HDL Coder rejects."
    "    % Both bins are in [0, N), so delta is in (-N, N) and one correction"
    "    % is enough."
    "    delta = bin - target;"
    "    if delta >= int32(" + (n/2) + ")"
    "        delta = delta - int32(" + n + ");"
    "    elseif delta < -int32(" + (n/2) + ")"
    "        delta = delta + int32(" + n + ");"
    "    end"
    "    distance = abs(delta);"
    "    within = distance <= int32(" + options.BinTolerance + ");"
    "    if counter < uint32(" + preambleSymbols + ")"
    "        preambleOk = preambleOk && within;"
    "    else"
    "        syncOk = syncOk && within;"
    "    end"
    ""
    "    if counter == uint32(" + (preambleSymbols-1) + ")"
    "        preambleDetected = preambleOk;"
    "    end"
    "    if counter == uint32(" + (preambleSymbols+1) + ")"
    "        syncValid = preambleOk && syncOk;"
    "        acquisitionFailed = ~(preambleOk && syncOk);"
    "        counter = uint32(0);"
    "        preambleOk = true;"
    "        syncOk = true;"
    "    else"
    "        counter = counter + uint32(1);"
    "    end"
    "end"
    "symbolsSeen = counter;"
    "end"]);

add_line(dut, "symbolIndex/1", "AcquisitionFsm/1", autorouting="on");
add_line(dut, "symbolValid/1", "AcquisitionFsm/2", autorouting="on");
add_line(dut, "syncWord/1", "AcquisitionFsm/3", autorouting="on");
add_line(dut, "resetIn/1", "AcquisitionFsm/4", autorouting="on");

addOutport(dut, "preambleDetected", 1, [560 60], "AcquisitionFsm/1");
addOutport(dut, "syncValid", 2, [560 120], "AcquisitionFsm/2");
addOutport(dut, "acquisitionFailed", 3, [560 180], "AcquisitionFsm/3");
addOutport(dut, "symbolsSeen", 4, [560 240], "AcquisitionFsm/4");
set_param(dut, TreatAsAtomicUnit="on");

sources = ["stimulusSymbolIndex", "stimulusSymbolValid", ...
    "stimulusSyncWord", "stimulusReset"];
for k = 1:numel(sources)
    block = modelName+"/Source_"+sources(k);
    top = 60+(k-1)*60;
    add_block("simulink/Sources/From Workspace", block, ...
        Position=[40 top 160 top+35]);
    set_param(block, VariableName=sources(k), SampleTime="1", ...
        Interpolate="off", OutputAfterFinalValue="Setting to zero");
    add_line(modelName, "Source_"+sources(k)+"/1", ...
        sprintf("DUT/%d", k), autorouting="on");
end

outputs = ["preambleDetected", "syncValid", "acquisitionFailed", ...
    "symbolsSeen"];
for k = 1:numel(outputs)
    block = modelName+"/Log_"+outputs(k);
    top = 60+(k-1)*55;
    add_block("simulink/Sinks/To Workspace", block, ...
        Position=[560 top 680 top+35]);
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
info.symbolCount = n;
info.preambleSymbols = preambleSymbols;
info.binTolerance = options.BinTolerance;
info.outputVariables = outputs;
end

function closeIfLoaded(modelName)
if bdIsLoaded(modelName)
    set_param(modelName, Dirty="off");
    close_system(modelName, 0);
end
end

function addPort(parent, name, portNumber, position)
block = parent+"/"+name;
add_block("simulink/Sources/In1", block, ...
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
