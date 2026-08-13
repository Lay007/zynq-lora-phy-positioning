function info = build_framing_model(options)
%BUILD_FRAMING_MODEL Generate the packet framing state machine.
%
% Fifth M2 subsystem: the one that routes symbols and re-arms.
%
%   info = build_framing_model(HeaderSymbols=8);
%
% Mirrors LORA_PHY.PACKET_FRAME_STEP, which is why that reference keeps its
% state in arguments rather than persistent variables -- the two have to be
% the same machine, and a shape that only works in one of them invites
% divergence.
%
% Phase is carried as a uint8 rather than a string: 0 idle, 1 sync, 2 sfd,
% 3 header, 4 payload. The MATLAB reference uses names because it is read by
% people; the DUT uses numbers because it is read by HDL Coder. The
% regression maps between them in one place.
%
% headerSymbols and payloadSymbols are input ports, not compile-time
% constants. LoRa derives the payload symbol count from the decoded header,
% which lives in software, so the count has to be able to arrive at run
% time even though nothing supplies it yet.
%
% Integer and boolean throughout, so the DUT is bit-exact against the
% reference rather than close, and no fixed-point type is involved.

arguments
    options.HeaderSymbols (1,1) double {mustBeInteger, mustBeNonnegative} = 8
    options.ModelName (1,1) string = "lora_framing"
    options.OutputDirectory (1,1) string = lora_sim.generated_directory
    options.Save (1,1) logical = true
end

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
    info = populateModel(modelName, options, modelPath);
catch err
    if bdIsLoaded(modelName)
        set_param(modelName, Dirty="off");
        close_system(modelName, 0);
    end
    rethrow(err);
end
end

function info = populateModel(modelName, options, modelPath)
dut = modelName+"/DUT";
add_block("simulink/Ports & Subsystems/Subsystem", dut, ...
    Position=[240 80 460 420]);
delete_line(dut, "In1/1", "Out1/1");
delete_block(dut+"/In1");
delete_block(dut+"/Out1");

inputs = ["symbolIndex", "symbolValid", "preambleDetected", ...
    "syncValid", "sfdValid", "headerSymbols", "payloadSymbols", "resetIn"];
for k = 1:numel(inputs)
    block = dut+"/"+inputs(k);
    add_block("simulink/Sources/In1", block, ...
        Position=[40 40+(k-1)*45 70 60+(k-1)*45]);
    set_param(block, Port=num2str(k));
end

add_block("simulink/User-Defined Functions/MATLAB Function", ...
    dut+"/FramingFsm", Position=[180 40 440 380]);
lora_sim.set_function_script(dut+"/FramingFsm", [
    "function [phase, headerValid, payloadValid, symbolOut, packetDone, framingFailed] = fcn(symbolIndex, symbolValid, preambleDetected, syncValid, sfdValid, headerSymbols, payloadSymbols, resetIn)"
    "%#codegen"
    "% Phase: 0 idle, 1 sync, 2 sfd, 3 header, 4 payload."
    "% Bit-exact against lora_phy.packet_frame_step."
    "persistent state remaining"
    "if isempty(state)"
    "    state = uint8(0);"
    "    remaining = uint16(0);"
    "end"
    "if resetIn"
    "    state = uint8(0);"
    "    remaining = uint16(0);"
    "end"
    ""
    "headerValid = false;"
    "payloadValid = false;"
    "symbolOut = uint16(0);"
    "packetDone = false;"
    "framingFailed = false;"
    ""
    "if symbolValid"
    "    if state == uint8(0)"
    "        if preambleDetected"
    "            state = uint8(1);"
    "            remaining = uint16(2);"
    "        end"
    "    elseif state == uint8(1)"
    "        remaining = remaining - uint16(1);"
    "        if remaining == uint16(0)"
    "            if syncValid"
    "                state = uint8(2);"
    "                remaining = uint16(2);"
    "            else"
    "                % Re-arm rather than stall: the radio keeps running"
    "                % whether or not this candidate was real."
    "                state = uint8(0);"
    "                framingFailed = true;"
    "            end"
    "        end"
    "    elseif state == uint8(2)"
    "        remaining = remaining - uint16(1);"
    "        if remaining == uint16(0)"
    "            if sfdValid"
    "                state = uint8(3);"
    "                remaining = uint16(headerSymbols);"
    "            else"
    "                state = uint8(0);"
    "                framingFailed = true;"
    "            end"
    "        end"
    "    elseif state == uint8(3)"
    "        headerValid = true;"
    "        symbolOut = uint16(symbolIndex);"
    "        remaining = remaining - uint16(1);"
    "        if remaining == uint16(0)"
    "            state = uint8(4);"
    "            remaining = uint16(payloadSymbols);"
    "            if remaining == uint16(0)"
    "                state = uint8(0);"
    "                packetDone = true;"
    "            end"
    "        end"
    "    else"
    "        payloadValid = true;"
    "        symbolOut = uint16(symbolIndex);"
    "        remaining = remaining - uint16(1);"
    "        if remaining == uint16(0)"
    "            state = uint8(0);"
    "            packetDone = true;"
    "        end"
    "    end"
    "end"
    "phase = state;"
    "end"]);

for k = 1:numel(inputs)
    add_line(dut, inputs(k)+"/1", sprintf("FramingFsm/%d", k), ...
        autorouting="on");
end

outputs = ["phase", "headerValid", "payloadValid", "symbolOut", ...
    "packetDone", "framingFailed"];
for k = 1:numel(outputs)
    block = dut+"/"+outputs(k);
    add_block("simulink/Sinks/Out1", block, ...
        Position=[560 40+(k-1)*55 590 60+(k-1)*55]);
    set_param(block, Port=num2str(k));
    add_line(dut, sprintf("FramingFsm/%d", k), outputs(k)+"/1", ...
        autorouting="on");
end
set_param(dut, TreatAsAtomicUnit="on");

variables = "stimulus"+["SymbolIndex", "SymbolValid", "PreambleDetected", ...
    "SyncValid", "SfdValid", "HeaderSymbols", "PayloadSymbols", "Reset"];
for k = 1:numel(variables)
    block = modelName+"/Source_"+variables(k);
    top = 40+(k-1)*50;
    add_block("simulink/Sources/From Workspace", block, ...
        Position=[40 top 160 top+35]);
    set_param(block, VariableName=variables(k), SampleTime="1", ...
        Interpolate="off", OutputAfterFinalValue="Holding final value");
    add_line(modelName, "Source_"+variables(k)+"/1", ...
        sprintf("DUT/%d", k), autorouting="on");
end

for k = 1:numel(outputs)
    block = modelName+"/Log_"+outputs(k);
    top = 40+(k-1)*55;
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
info.headerSymbols = options.HeaderSymbols;
info.inputVariables = variables;
info.outputVariables = outputs;
end
