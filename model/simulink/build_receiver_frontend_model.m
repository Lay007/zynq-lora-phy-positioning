function info = build_receiver_frontend_model(options)
%BUILD_RECEIVER_FRONTEND_MODEL Correlator, blind detector, and realignment.
%
% The first model in which the M2 subsystems run together rather than one at
% a time. Each of them was already exact against MATLAB in isolation; what
% this adds is the loop between them, which no per-block regression can see.
%
%   info = build_receiver_frontend_model(SpreadingFactor=7, SamplesPerChip=4);
%
% Structure:
%
%   iqIn/validIn -> Correlator -> symbolIndex/symbolValid -> BlindDetector
%                        ^                                        |
%                        +---- ResyncPolicy <- chipsToBoundary ----+
%
% The Correlator and BlindDetector subsystems are copied from
% BUILD_FFT_CORRELATOR_MODEL and BUILD_BLIND_DETECTOR_MODEL rather than
% rebuilt here, so there is exactly one definition of each and this model
% cannot drift away from the versions the regressions check.
%
% ResyncPolicy is the only new logic, and it is deliberately thin. The
% correlator exposes a mechanism -- withhold s samples, and the window grid
% advances by s -- while the policy decides s and when. For a preamble found
% at bin d the required advance is chipsToBoundary*L = mod(-d, N)*L.
%
% Why realignment matters: on the free-running grid a window can straddle
% the preamble-to-sync boundary, which loses the first sync symbol to the
% stronger half of its own window and caps sync validation at 97% of
% alignments. After realignment the preamble sits at bin 0 and the sync word
% at the absolute bins 8*nibble, which is the domain where
% LORA_PHY.VALIDATE_ACQUISITION_BINS is the correct check.
%
% The policy fires once per reset. Re-arming after the end of a packet
% belongs to the framing state machine, which is not built.

arguments
    options.SpreadingFactor (1,1) double {mustBeInteger} = 7
    options.SamplesPerChip (1,1) double {mustBeInteger} = 4
    options.PreambleSymbols (1,1) double {mustBeInteger, mustBePositive} = 8
    options.BinTolerance (1,1) double {mustBeInteger, mustBeNonnegative} = 1
    options.DataType (1,1) string {mustBeMember(options.DataType, ...
        ["double", "fixed"])} = "double"
    options.WordLength (1,1) double {mustBeInteger, mustBePositive} = 16
    options.ModelName (1,1) string = "lora_receiver_frontend"
    options.OutputDirectory (1,1) string = lora_sim.generated_directory
    options.Save (1,1) logical = true
end

config = lora_phy.css_config(options.SpreadingFactor, options.SamplesPerChip);
modelName = options.ModelName;
modelPath = fullfile(options.OutputDirectory, modelName+".slx");

sourceModels = ["", ""];
if bdIsLoaded(modelName)
    set_param(modelName, Dirty="off");
    close_system(modelName, 0);
end
if isfile(modelPath)
    delete(modelPath);
end

new_system(modelName);
try
    [info, sourceModels] = populateModel(modelName, config, options, ...
        modelPath);
catch err
    closeIfLoaded(modelName);
    closeSources(sourceModels);
    rethrow(err);
end
closeSources(sourceModels);
end

function [info, sourceModels] = populateModel(modelName, config, options, ...
    modelPath)
n = config.symbolCount;
samplesPerChip = options.SamplesPerChip;

% Build the two verified subsystems in their own models and copy them in.
correlatorInfo = build_fft_correlator_model( ...
    SpreadingFactor=options.SpreadingFactor, ...
    SamplesPerChip=options.SamplesPerChip, DataType=options.DataType, ...
    WordLength=options.WordLength, IncludeVerificationTaps=false, ...
    ModelName=modelName+"_correlator_src", Save=false);
detectorInfo = build_blind_detector_model( ...
    SpreadingFactor=options.SpreadingFactor, ...
    PreambleSymbols=options.PreambleSymbols, ...
    BinTolerance=options.BinTolerance, ...
    ModelName=modelName+"_detector_src", Save=false);
sourceModels = [correlatorInfo.modelName, detectorInfo.modelName];

dut = modelName+"/DUT";
add_block("simulink/Ports & Subsystems/Subsystem", dut, ...
    Position=[260 80 520 520]);
delete_line(dut, "In1/1", "Out1/1");
delete_block(dut+"/In1");
delete_block(dut+"/Out1");

addInport(dut, "iqIn", 1, [40 80]);
addInport(dut, "validIn", 2, [40 150]);
addInport(dut, "resetIn", 3, [40 220]);
addInport(dut, "syncWord", 4, [40 290]);

add_block(correlatorInfo.dutPath, dut+"/Correlator", Position=[200 60 340 260]);
add_block(detectorInfo.dutPath, dut+"/BlindDetector", ...
    Position=[440 60 580 220]);

% The reference ROMs address model-workspace variables, and copying a
% subsystem does not carry the workspace with it. Copy the values across
% rather than recomputing them here: a second derivation of the reference
% chirp is exactly the kind of duplicate that drifts.
sourceWorkspace = get_param(correlatorInfo.modelName, "ModelWorkspace");
targetWorkspace = get_param(modelName, "ModelWorkspace");
for name = ["SF", "L", "N", "M", "refConjReal", "refConjImag"]
    assignin(targetWorkspace, name, ...
        sourceWorkspace.getVariable(char(name)));
end

add_block("simulink/User-Defined Functions/MATLAB Function", ...
    dut+"/ResyncPolicy", Position=[440 300 620 420]);
lora_sim.set_function_script(dut+"/ResyncPolicy", [
    "function [resyncValid, resyncSkip, aligned] = fcn(preambleDetected, chipsToBoundary, resetIn)"
    "%#codegen"
    "% Turn a detected preamble into a window-grid advance."
    "%"
    "% The correlator supplies the mechanism: withholding s samples moves"
    "% the grid by s relative to the stream. For a preamble at bin d the"
    "% advance needed to reach the next symbol boundary is"
    "% chipsToBoundary*L, and chipsToBoundary = mod(-d, N) is already what"
    "% the detector reports."
    "%"
    "% Whole-chip only. The sub-chip remainder is invisible to a bin index"
    "% and is left to the joint timing/CFO estimator, so alignment lands"
    "% within one chip rather than one sample."
    "%"
    "% One shot per reset. Re-arming after a packet ends is the framing"
    "% state machine's job and that does not exist yet; firing repeatedly"
    "% here would drag the grid off a packet it had already acquired."
    "persistent done"
    "if isempty(done)"
    "    done = false;"
    "end"
    "if resetIn"
    "    done = false;"
    "end"
    "resyncValid = false;"
    "resyncSkip = uint32(0);"
    "if preambleDetected && ~done"
    "    resyncValid = true;"
    "    resyncSkip = uint32(chipsToBoundary)*uint32(" + samplesPerChip + ");"
    "    done = true;"
    "end"
    "aligned = done;"
    "end"]);

% The feedback is registered. Without a delay in it the loop is algebraic
% for type propagation as well as for data: the correlator's resync input
% type resolves through the policy, which resolves through the detector,
% which resolves back through the correlator. A one-cycle delay is also what
% the hardware does -- the policy cannot act on a symbol in the same cycle
% it is decided.
add_block("simulink/Discrete/Delay", dut+"/ResyncValidDelay", ...
    Position=[660 300 700 330]);
set_param(dut+"/ResyncValidDelay", DelayLength="1", InitialCondition="0");
add_block("simulink/Discrete/Delay", dut+"/ResyncSkipDelay", ...
    Position=[660 360 700 390]);
set_param(dut+"/ResyncSkipDelay", DelayLength="1", InitialCondition="0");

add_line(dut, "iqIn/1", "Correlator/1", autorouting="on");
add_line(dut, "validIn/1", "Correlator/2", autorouting="on");
add_line(dut, "resetIn/1", "Correlator/3", autorouting="on");
add_line(dut, "ResyncPolicy/1", "ResyncValidDelay/1", autorouting="on");
add_line(dut, "ResyncPolicy/2", "ResyncSkipDelay/1", autorouting="on");
% Types are pinned rather than inherited. Inference around the loop reaches
% the correlator's resync inputs by a different route than in the standalone
% model, and leaving it implicit fails to propagate uint32 into InputFraming.
add_block("simulink/Signal Attributes/Data Type Conversion", ...
    dut+"/ResyncValidType", Position=[720 300 770 330]);
set_param(dut+"/ResyncValidType", OutDataTypeStr="boolean");
add_block("simulink/Signal Attributes/Data Type Conversion", ...
    dut+"/ResyncSkipType", Position=[720 360 770 390]);
set_param(dut+"/ResyncSkipType", OutDataTypeStr="uint32");

add_line(dut, "ResyncValidDelay/1", "ResyncValidType/1", autorouting="on");
add_line(dut, "ResyncSkipDelay/1", "ResyncSkipType/1", autorouting="on");
add_line(dut, "ResyncValidType/1", "Correlator/4", autorouting="on");
add_line(dut, "ResyncSkipType/1", "Correlator/5", autorouting="on");

add_line(dut, "Correlator/1", "BlindDetector/1", autorouting="on");
add_line(dut, "Correlator/2", "BlindDetector/2", autorouting="on");
add_line(dut, "syncWord/1", "BlindDetector/3", autorouting="on");
add_line(dut, "resetIn/1", "BlindDetector/4", autorouting="on");

add_line(dut, "BlindDetector/2", "ResyncPolicy/1", autorouting="on");
add_line(dut, "BlindDetector/5", "ResyncPolicy/2", autorouting="on");
add_line(dut, "resetIn/1", "ResyncPolicy/3", autorouting="on");

outputs = struct( ...
    "name", {"symbolIndex", "symbolValid", "symbolSampleCount", ...
        "timestampValid", "detected", "preambleDetected", "syncValid", ...
        "preambleBin", "chipsToBoundary", "resyncValid", "resyncSkip", ...
        "aligned"}, ...
    "source", {"Correlator/1", "Correlator/2", "Correlator/7", ...
        "Correlator/8", "BlindDetector/1", "BlindDetector/2", ...
        "BlindDetector/3", "BlindDetector/4", "BlindDetector/5", ...
        "ResyncPolicy/1", "ResyncPolicy/2", "ResyncPolicy/3"});
for k = 1:numel(outputs)
    addOutport(dut, outputs(k).name, k, [700 40+(k-1)*45], outputs(k).source);
end
set_param(dut, TreatAsAtomicUnit="on");

buildHarness(modelName, options, string({outputs.name}));

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
info.samplesPerChip = samplesPerChip;
info.samplesPerSymbol = config.samplesPerSymbol;
info.symbolCount = n;
info.preambleSymbols = options.PreambleSymbols;
info.outputVariables = string({outputs.name});
end

function buildHarness(modelName, options, names)
%BUILDHARNESS Stimulus and logging outside the DUT.
sources = ["Iq", "Valid", "Reset", "SyncWord"];
variables = ["stimulusIq", "stimulusValid", "stimulusReset", ...
    "stimulusSyncWord"];
for k = 1:numel(sources)
    block = modelName+"/Stimulus"+sources(k);
    top = 60+(k-1)*70;
    add_block("simulink/Sources/From Workspace", block, ...
        Position=[40 top 160 top+40]);
    set_param(block, VariableName=variables(k), SampleTime="1", ...
        Interpolate="off", OutputAfterFinalValue="Setting to zero");
end

if options.DataType == "fixed"
    % Quantize outside the DUT, as in the correlator harness: a
    % float-to-fixed conversion inside the DUT is rejected by checkhdl.
    types = lora_sim.fixed_point_types(WordLength=options.WordLength);
    add_block("simulink/Signal Attributes/Data Type Conversion", ...
        modelName+"/QuantizeInput", Position=[190 60 250 100]);
    set_param(modelName+"/QuantizeInput", OutDataTypeStr=char(types.input));
    add_line(modelName, "StimulusIq/1", "QuantizeInput/1", autorouting="on");
    add_line(modelName, "QuantizeInput/1", "DUT/1", autorouting="on");
else
    add_line(modelName, "StimulusIq/1", "DUT/1", autorouting="on");
end
add_line(modelName, "StimulusValid/1", "DUT/2", autorouting="on");
add_line(modelName, "StimulusReset/1", "DUT/3", autorouting="on");
add_line(modelName, "StimulusSyncWord/1", "DUT/4", autorouting="on");

for k = 1:numel(names)
    block = modelName+"/Log_"+names(k);
    top = 40+(k-1)*45;
    add_block("simulink/Sinks/To Workspace", block, ...
        Position=[700 top 820 top+35]);
    set_param(block, VariableName=char(names(k)), SaveFormat="Array", ...
        SampleTime="-1", MaxDataPoints="inf");
    add_line(modelName, sprintf("DUT/%d", k), "Log_"+names(k)+"/1", ...
        autorouting="on");
end
end

function closeIfLoaded(modelName)
if bdIsLoaded(modelName)
    set_param(modelName, Dirty="off");
    close_system(modelName, 0);
end
end

function closeSources(sourceModels)
for k = 1:numel(sourceModels)
    if strlength(sourceModels(k)) > 0
        closeIfLoaded(sourceModels(k));
    end
end
end

function addInport(parent, name, portNumber, position)
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
