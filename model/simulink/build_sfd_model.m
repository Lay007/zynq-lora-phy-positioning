function info = build_sfd_model(options)
%BUILD_SFD_MODEL Generate the SFD acceptance DUT.
%
% Sixth M2 subsystem, and the last piece of acquisition.
%
%   info = build_sfd_model(SpreadingFactor=7);
%
% Consumes downchirp-dechirped bins and the preamble bin, and checks the
% mirror LORA_PHY.VALIDATE_SFD_BINS measured: on a realigned grid the SFD
% sits at mod(-preambleBin, N). Whatever displaces the preamble upward
% displaces the SFD downward by the same amount.
%
% It does not dechirp anything itself. The downchirp reference costs no ROM
% of its own -- LORA_PHY.DOWNCHIRP_REFERENCE_SPECTRUM derives it from the
% upchirp table at a complemented address with the imaginary part negated --
% so the SFD path reuses the correlator rather than duplicating it, and this
% DUT only decides.
%
% Integer throughout, so it is bit-exact against the MATLAB reference. The
% mirror is computed by masking rather than mod(), because N is a power of
% two and because mod() on a signed value is a division HDL Coder refuses to
% generate.

arguments
    options.SpreadingFactor (1,1) double {mustBeInteger} = 7
    options.SfdSymbols (1,1) double {mustBeInteger, mustBePositive} = 2
    options.BinTolerance (1,1) double {mustBeInteger, mustBeNonnegative} = 1
    options.ModelName (1,1) string = "lora_sfd"
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
    if bdIsLoaded(modelName)
        set_param(modelName, Dirty="off");
        close_system(modelName, 0);
    end
    rethrow(err);
end
end

function info = populateModel(modelName, config, options, modelPath)
n = config.symbolCount;

dut = modelName+"/DUT";
add_block("simulink/Ports & Subsystems/Subsystem", dut, ...
    Position=[240 80 460 320]);
delete_line(dut, "In1/1", "Out1/1");
delete_block(dut+"/In1");
delete_block(dut+"/Out1");

inputs = ["downBin", "binValid", "preambleBin", "resetIn"];
for k = 1:numel(inputs)
    block = dut+"/"+inputs(k);
    add_block("simulink/Sources/In1", block, ...
        Position=[40 60+(k-1)*55 70 80+(k-1)*55]);
    set_param(block, Port=num2str(k));
end

add_block("simulink/User-Defined Functions/MATLAB Function", ...
    dut+"/SfdCheck", Position=[180 40 420 280]);
lora_sim.set_function_script(dut+"/SfdCheck", [
    "function [sfdValid, expectedBin, agree, binsSeen] = fcn(downBin, binValid, preambleBin, resetIn)"
    "%#codegen"
    "% Bit-exact against lora_phy.validate_sfd_bins."
    "persistent seen firstBin allOnTarget allAgree"
    "if isempty(seen)"
    "    seen = uint8(0);"
    "    firstBin = uint16(0);"
    "    allOnTarget = true;"
    "    allAgree = true;"
    "end"
    "if resetIn"
    "    seen = uint8(0);"
    "    firstBin = uint16(0);"
    "    allOnTarget = true;"
    "    allAgree = true;"
    "end"
    ""
    "sfdValid = false;"
    "agree = false;"
    "% mod(-preambleBin, N): N is a power of two, so the mirror is a mask"
    "% and bin 0 needs no special case (N & (N-1) == 0)."
    "expectedBin = bitand(uint16(" + n + ") - uint16(preambleBin), uint16(" + (n-1) + "));"
    ""
    "if binValid"
    "    if seen == uint8(0)"
    "        firstBin = uint16(downBin);"
    "        allOnTarget = true;"
    "        allAgree = true;"
    "    end"
    "    allOnTarget = allOnTarget && withinTolerance(uint16(downBin), expectedBin);"
    "    allAgree = allAgree && withinTolerance(uint16(downBin), firstBin);"
    "    if seen < uint8(" + options.SfdSymbols + ")"
    "        seen = seen + uint8(1);"
    "    end"
    "    if seen == uint8(" + options.SfdSymbols + ")"
    "        sfdValid = allOnTarget;"
    "        agree = allAgree;"
    "        seen = uint8(0);"
    "    end"
    "end"
    "binsSeen = seen;"
    "end"
    ""
    "function within = withinTolerance(bin, target)"
    "%#codegen"
    "% Circular distance by comparison. Both operands are already inside"
    "% [0, N), so one correction on each side is enough."
    "delta = int32(bin) - int32(target);"
    "if delta >= int32(" + (n/2) + ")"
    "    delta = delta - int32(" + n + ");"
    "elseif delta < -int32(" + (n/2) + ")"
    "    delta = delta + int32(" + n + ");"
    "end"
    "within = abs(delta) <= int32(" + options.BinTolerance + ");"
    "end"]);

for k = 1:numel(inputs)
    add_line(dut, inputs(k)+"/1", sprintf("SfdCheck/%d", k), ...
        autorouting="on");
end

outputs = ["sfdValid", "expectedBin", "agree", "binsSeen"];
for k = 1:numel(outputs)
    block = dut+"/"+outputs(k);
    add_block("simulink/Sinks/Out1", block, ...
        Position=[560 60+(k-1)*55 590 80+(k-1)*55]);
    set_param(block, Port=num2str(k));
    add_line(dut, sprintf("SfdCheck/%d", k), outputs(k)+"/1", ...
        autorouting="on");
end
set_param(dut, TreatAsAtomicUnit="on");

variables = "stimulus"+["DownBin", "BinValid", "PreambleBin", "Reset"];
for k = 1:numel(variables)
    block = modelName+"/Source_"+variables(k);
    top = 60+(k-1)*60;
    add_block("simulink/Sources/From Workspace", block, ...
        Position=[40 top 160 top+35]);
    set_param(block, VariableName=variables(k), SampleTime="1", ...
        Interpolate="off", OutputAfterFinalValue="Holding final value");
    add_line(modelName, "Source_"+variables(k)+"/1", ...
        sprintf("DUT/%d", k), autorouting="on");
end

for k = 1:numel(outputs)
    block = modelName+"/Log_"+outputs(k);
    top = 60+(k-1)*55;
    add_block("simulink/Sinks/To Workspace", block, ...
        Position=[560 top 680 top+35]);
    set_param(block, VariableName=char(outputs(k)), SaveFormat="Array", ...
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
info.sfdSymbols = options.SfdSymbols;
info.outputVariables = outputs;
end
