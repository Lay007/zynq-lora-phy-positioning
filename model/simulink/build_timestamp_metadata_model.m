function info = build_timestamp_metadata_model(options)
%BUILD_TIMESTAMP_METADATA_MODEL Join coarse and fractional ToA metadata.
%
% The coarse timestamp and the packet-rate fractional-ToA estimator are
% intentionally separate pipelines. This model freezes the hardware-facing
% contract that joins them into one atomic timestamp record.
%
% Exactly one coarse and one fractional fragment may be outstanding. The
% fragments may arrive in either order or in the same cycle. Once both have
% been captured, the pair is emitted on the following cycle with a one-cycle
% timestampValid pulse. Duplicate unmatched fragments pulse metadataOverflow
% and do not overwrite the first fragment. resetIn discards any partial pair.

arguments
    options.ModelName (1,1) string = "lora_timestamp_metadata"
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
    Position=[250 80 500 340]);
delete_line(dut, "In1/1", "Out1/1");
delete_block(dut+"/In1");
delete_block(dut+"/Out1");

inputs = ["coarseSampleCount", "coarseValid", "fractionalToaSamples", ...
    "fractionalValid", "resetIn"];
for k = 1:numel(inputs)
    block = dut+"/"+inputs(k);
    add_block("simulink/Sources/In1", block, ...
        Position=[35 50+(k-1)*50 65 70+(k-1)*50]);
    set_param(block, Port=num2str(k));
end

add_block("simulink/User-Defined Functions/MATLAB Function", ...
    dut+"/MetadataJoin", Position=[170 45 420 285]);
lora_sim.set_function_script(dut+"/MetadataJoin", [
    "function [coarseOut, fractionalOut, timestampValid, metadataOverflow] = fcn(coarseSampleCount, coarseValid, fractionalToaSamples, fractionalValid, resetIn)"
    "%#codegen"
    "% Join asynchronous coarse and fractional timestamp fragments."
    "persistent coarseReg fractionalReg coarsePending fractionalPending"
    "if isempty(coarsePending)"
    "    coarseReg = uint64(0);"
    "    fractionalReg = int32(0);"
    "    coarsePending = false;"
    "    fractionalPending = false;"
    "end"
    "coarseOut = uint64(0);"
    "fractionalOut = int32(0);"
    "timestampValid = false;"
    "metadataOverflow = false;"
    "if resetIn"
    "    coarseReg = uint64(0);"
    "    fractionalReg = int32(0);"
    "    coarsePending = false;"
    "    fractionalPending = false;"
    "    return;"
    "end"
    "% Emit only a pair that was already complete at the start of this cycle."
    "% That makes timestampValid registered and leaves this cycle free to"
    "% accept the first fragment of the next packet."
    "pairReady = coarsePending && fractionalPending;"
    "if pairReady"
    "    coarseOut = coarseReg;"
    "    fractionalOut = fractionalReg;"
    "    timestampValid = true;"
    "    coarsePending = false;"
    "    fractionalPending = false;"
    "end"
    "if coarseValid"
    "    if coarsePending && ~pairReady"
    "        metadataOverflow = true;"
    "    else"
    "        coarseReg = uint64(coarseSampleCount);"
    "        coarsePending = true;"
    "    end"
    "end"
    "if fractionalValid"
    "    if fractionalPending && ~pairReady"
    "        metadataOverflow = true;"
    "    else"
    "        fractionalReg = int32(fractionalToaSamples);"
    "        fractionalPending = true;"
    "    end"
    "end"
    "end"]);

for k = 1:numel(inputs)
    add_line(dut, inputs(k)+"/1", sprintf("MetadataJoin/%d", k), ...
        autorouting="on");
end

outputs = ["coarseSampleCountOut", "fractionalToaSamplesOut", ...
    "timestampValid", "metadataOverflow"];
for k = 1:numel(outputs)
    block = dut+"/"+outputs(k);
    add_block("simulink/Sinks/Out1", block, ...
        Position=[540 60+(k-1)*55 570 80+(k-1)*55]);
    set_param(block, Port=num2str(k));
    add_line(dut, sprintf("MetadataJoin/%d", k), outputs(k)+"/1", ...
        autorouting="on");
end
set_param(dut, TreatAsAtomicUnit="on");

variables = "stimulus"+["CoarseSampleCount", "CoarseValid", ...
    "FractionalToaSamples", "FractionalValid", "Reset"];
for k = 1:numel(variables)
    block = modelName+"/Source_"+variables(k);
    top = 50+(k-1)*55;
    add_block("simulink/Sources/From Workspace", block, ...
        Position=[35 top 165 top+35]);
    set_param(block, VariableName=variables(k), SampleTime="1", ...
        Interpolate="off", OutputAfterFinalValue="Setting to zero");
    add_line(modelName, "Source_"+variables(k)+"/1", ...
        sprintf("DUT/%d", k), autorouting="on");
end

for k = 1:numel(outputs)
    block = modelName+"/Log_"+outputs(k);
    top = 50+(k-1)*55;
    add_block("simulink/Sinks/To Workspace", block, ...
        Position=[610 top 750 top+35]);
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
info.outputVariables = outputs;
info.maxOutstandingPairs = 1;
info.outputLatencyAfterPairComplete = 1;
end
