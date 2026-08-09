function info = build_blind_detector_model(options)
%BUILD_BLIND_DETECTOR_MODEL Generate the blind packet-start detector.
%
% Fourth M2 subsystem, and the one that finds packets rather than checking
% a candidate someone else found.
%
%   info = build_blind_detector_model(SpreadingFactor=7, PreambleSymbols=8);
%
% There is no search over sample offsets here, and that is the point. The
% preamble repeats one upchirp, so it is periodic with a symbol; a window
% starting d chips after a boundary dechirps to bin d whatever d is, and
% consecutive windows repeat that bin. The free-running correlator already
% emits one symbol per M samples, so detection is a predicate over the last
% PreambleSymbols+2 bins and costs no multipliers at all. See
% LORA_PHY.DETECT_PREAMBLE_RUN for the derivation.
%
% Two differences from BUILD_ACQUISITION_MODEL, which this supersedes for
% blind operation:
%
% * It slides. The acquisition FSM frames the stream into groups of
%   PreambleSymbols+2 and so only works when something already knows where a
%   group starts. This one keeps a shift register and re-evaluates on every
%   symbol, which is what "blind" means.
% * Its targets are relative. The acquisition FSM compares against bin 0 and
%   absolute sync bins, which is correct only after timing correction. Here
%   the preamble bin is whatever the alignment makes it, and the sync bins
%   are checked at preambleBin + 8*nibble. That also makes the check immune
%   to carrier frequency offset, which displaces preamble and sync equally.
%
% Preamble and sync are reported on separate outputs, and that split is not
% cosmetic. On the free-running grid a window can straddle two symbols. Deep
% inside the preamble that costs nothing, because both halves are the same
% chirp and the bin is unchanged. At the preamble-to-sync boundary it does
% cost: the window carries half a preamble symbol and half a sync symbol,
% the N-point spectrum holds two comparable peaks, and the peak tracker
% returns whichever is larger. Measured at an offset near M/2, the first
% sync symbol is skipped entirely and the run reads as one extra preamble
% bin followed by the second sync bin.
%
% So preambleDetected is usable as it stands, and syncValid on this grid is
% not. The intended use is to detect the preamble here, realign the window
% grid by chipsToBoundary, and validate sync on the aligned grid, where the
% straddle no longer exists. RUN_BLIND_DETECTOR_REGRESSION measures both
% rates against offset so the gap is a number rather than a caveat.
%
% Everything is integer, so the DUT is bit-exact against the MATLAB function
% rather than close, and no fixed-point type is involved. As in the
% acquisition FSM the circular wrap is done by comparison: mod() on a signed
% value is a division with Floor rounding that HDL Coder refuses to
% generate, and makehdl rather than checkhdl is what catches it.

arguments
    options.SpreadingFactor (1,1) double {mustBeInteger} = 7
    options.PreambleSymbols (1,1) double {mustBeInteger, mustBePositive} = 8
    options.BinTolerance (1,1) double {mustBeInteger, mustBeNonnegative} = 1
    options.ModelName (1,1) string = "lora_blind_detector"
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
runLength = preambleSymbols+2;

dut = modelName+"/DUT";
add_block("simulink/Ports & Subsystems/Subsystem", dut, ...
    Position=[240 80 440 340]);
delete_line(dut, "In1/1", "Out1/1");
delete_block(dut+"/In1");
delete_block(dut+"/Out1");

addPort(dut, "symbolIndex", 1, [40 60]);
addPort(dut, "symbolValid", 2, [40 120]);
addPort(dut, "syncWord", 3, [40 180]);
addPort(dut, "resetIn", 4, [40 240]);

add_block("simulink/User-Defined Functions/MATLAB Function", ...
    dut+"/BlindDetector", Position=[180 40 420 300]);
lora_sim.set_function_script(dut+"/BlindDetector", [
    "function [detected, preambleDetected, syncValid, preambleBin, chipsToBoundary, binsSeen] = fcn(symbolIndex, symbolValid, syncWord, resetIn)"
    "%#codegen"
    "% Sliding blind detector. History holds the last " + runLength + " bins,"
    "% oldest first; the predicate is evaluated on every valid symbol once"
    "% the register has filled. Bit-exact against"
    "% lora_phy.detect_preamble_run, which takes the same window."
    "persistent history filled"
    "if isempty(history)"
    "    history = zeros(1, " + runLength + ", 'uint16');"
    "    filled = uint8(0);"
    "end"
    "if resetIn"
    "    history = zeros(1, " + runLength + ", 'uint16');"
    "    filled = uint8(0);"
    "end"
    ""
    "detected = false;"
    "preambleDetected = false;"
    "syncValid = false;"
    "preambleBin = uint16(0);"
    "chipsToBoundary = uint16(0);"
    ""
    "if symbolValid"
    "    for k = 1:" + (runLength-1)
    "        history(k) = history(k+1);"
    "    end"
    "    history(" + runLength + ") = uint16(symbolIndex);"
    "    if filled < uint8(" + runLength + ")"
    "        filled = filled + uint8(1);"
    "    end"
    ""
    "    if filled == uint8(" + runLength + ")"
    "        % Everything is measured against the oldest bin in the window,"
    "        % matching the MATLAB reference, so slow drift cannot"
    "        % accumulate the way a pairwise-adjacent check would allow."
    "        reference = history(1);"
    "        preambleOk = true;"
    "        for k = 1:" + preambleSymbols
    "            preambleOk = preambleOk && withinTolerance(history(k), reference);"
    "        end"
    "        highNibble = uint16(bitshift(uint8(syncWord), -4));"
    "        lowNibble = uint16(bitand(uint8(syncWord), uint8(15)));"
    "        syncOk = withinTolerance(history(" + (preambleSymbols+1) + "), wrapBin(reference + wrapBin(uint16(8)*highNibble)));"
    "        syncOk = syncOk && withinTolerance(history(" + (preambleSymbols+2) + "), wrapBin(reference + wrapBin(uint16(8)*lowNibble)));"
    "        preambleDetected = preambleOk;"
    "        syncValid = syncOk;"
    "        detected = preambleOk && syncOk;"
    "        preambleBin = reference;"
    "        % mod(-bin, N): N is a power of two, so the wrap is a mask and"
    "        % bin 0 needs no special case (N & (N-1) == 0)."
    "        chipsToBoundary = wrapBin(uint16(" + n + ") - reference);"
    "    end"
    "end"
    "binsSeen = filled;"
    "end"
    ""
    "function wrapped = wrapBin(value)"
    "%#codegen"
    "% mod(value, N) for unsigned value. N is 2^SF, so this is a mask and"
    "% costs nothing. Doing it with mod() would emit a division, and on a"
    "% signed operand HDL Coder refuses to generate one at all."
    "wrapped = bitand(value, uint16(" + (n-1) + "));"
    "end"
    ""
    "function within = withinTolerance(bin, target)"
    "%#codegen"
    "% Circular distance by comparison. Both arguments are already wrapped"
    "% into [0, N), so delta is in (-N, N) and a single correction on each"
    "% side is enough."
    "delta = int32(bin) - int32(target);"
    "if delta >= int32(" + (n/2) + ")"
    "    delta = delta - int32(" + n + ");"
    "elseif delta < -int32(" + (n/2) + ")"
    "    delta = delta + int32(" + n + ");"
    "end"
    "within = abs(delta) <= int32(" + options.BinTolerance + ");"
    "end"]);

add_line(dut, "symbolIndex/1", "BlindDetector/1", autorouting="on");
add_line(dut, "symbolValid/1", "BlindDetector/2", autorouting="on");
add_line(dut, "syncWord/1", "BlindDetector/3", autorouting="on");
add_line(dut, "resetIn/1", "BlindDetector/4", autorouting="on");

outputs = ["detected", "preambleDetected", "syncValid", "preambleBin", ...
    "chipsToBoundary", "binsSeen"];
for k = 1:numel(outputs)
    addOutport(dut, outputs(k), k, [560 20+(k-1)*55], ...
        sprintf("BlindDetector/%d", k));
end
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
info.runLength = runLength;
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
