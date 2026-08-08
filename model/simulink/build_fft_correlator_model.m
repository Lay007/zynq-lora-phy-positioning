function info = build_fft_correlator_model(options)
%BUILD_FFT_CORRELATOR_MODEL Generate the streaming CSS FFT-correlator model.
%
% The `.slx` is never edited by hand and is never committed. This script is
% the source of the model: delete the file and call the function again to
% get a byte-for-byte equivalent design.
%
%   info = build_fft_correlator_model;
%   info = build_fft_correlator_model(SpreadingFactor=9, SamplesPerChip=2);
%
% Architecture inside the `DUT` subsystem, matching
% LORA_PHY.FFT_CORRELATOR_STAGES one comparison point at a time:
%
%   iqIn/validIn
%     -> InputFraming        symbol boundary from a mod-M sample counter
%     -> FFT_M               dsphdl.FFT, length M, natural order, unnormalized
%     -> BinCounter          frequency bin index q, 0..M-1
%     -> RomReal/RomImag     conj(fft(reference)) as two ROMs addressed by q
%     -> Multiply            product = fftM .* conjReferenceSpectrum
%     -> PartitionAccumulate y[q] = product[q] + y[q-N], an N-deep comb
%     -> FFT_N               dsphdl.FFT, length N, on the last N accumulator
%                            outputs of each symbol
%     -> ScaleByM            1/M, an exact power-of-two shift
%     -> MagnitudeSquared    |.|^2
%     -> PeakTracker         first-maximum bin, peak, and spectrum sum
%     -> Confidence          peak / max(spectrumSum, eps)
%
% SpreadingFactor and SamplesPerChip are compile-time, as frozen in
% docs/simulink-m2-interfaces.md: they set both FFT lengths and the ROM
% depth. A different configuration is a different generated model.

arguments
    options.SpreadingFactor (1,1) double {mustBeInteger} = 7
    options.SamplesPerChip (1,1) double {mustBeInteger} = 8
    options.ModelName (1,1) string = "lora_fft_correlator"
    options.OutputDirectory (1,1) string = lora_sim.generated_directory
    options.Save (1,1) logical = true
end

config = lora_phy.css_config(options.SpreadingFactor, options.SamplesPerChip);
n = config.symbolCount;
m = config.samplesPerSymbol;
modelName = options.ModelName;
modelPath = fullfile(options.OutputDirectory, modelName+".slx");

if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
if isfile(modelPath)
    delete(modelPath);
end

new_system(modelName);
cleanupOnFailure = onCleanup(@() closeIfLoaded(modelName));

referenceChirp = lora_phy.reference_chirp(config);
conjReferenceSpectrum = conj(fft(referenceChirp));

workspace = get_param(modelName, "ModelWorkspace");
assignin(workspace, "SF", config.spreadingFactor);
assignin(workspace, "L", config.samplesPerChip);
assignin(workspace, "N", n);
assignin(workspace, "M", m);
assignin(workspace, "refConjReal", real(conjReferenceSpectrum));
assignin(workspace, "refConjImag", imag(conjReferenceSpectrum));

buildDut(modelName, n, m);
buildHarness(modelName);

set_param(modelName, ...
    SolverType="Fixed-step", Solver="FixedStepDiscrete", ...
    FixedStep="1", StartTime="0", StopTime="1000", ...
    SaveOutput="off", SaveTime="off", SaveFormat="Array", ...
    SignalLogging="off", ...
    ReturnWorkspaceOutputs="on");

if options.Save
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    save_system(modelName, modelPath);
end

info = struct;
info.modelName = modelName;
info.modelPath = string(modelPath);
info.dutPath = modelName+"/DUT";
info.spreadingFactor = config.spreadingFactor;
info.samplesPerChip = config.samplesPerChip;
info.symbolCount = n;
info.samplesPerSymbol = m;
info.conjReferenceSpectrum = conjReferenceSpectrum;
info.dataType = "double";
info.outputVariables = harnessVariables;

clear cleanupOnFailure;
end

function closeIfLoaded(modelName)
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
end

function names = harnessVariables
names = [ ...
    "symbolIndex"; "symbolValid"; "confidence"; "peakMagnitudeSquared"; ...
    "spectrumSum"; "symbolBoundary"; ...
    "stageFftM"; "stageProduct"; "stagePartition"; "stageFftN"; ...
    "stageMagnitudeSquared"; ...
    "fftMValid"; "partitionValid"; "fftNValid"];
end

function buildHarness(modelName)
%BUILDHARNESS Stimulus sources and logging outside the DUT.

add_block("simulink/Sources/From Workspace", modelName+"/StimulusIq", ...
    Position=[40 100 160 140]);
set_param(modelName+"/StimulusIq", VariableName="stimulusIq", ...
    SampleTime="1", Interpolate="off", ...
    OutputAfterFinalValue="Setting to zero");

add_block("simulink/Sources/From Workspace", modelName+"/StimulusValid", ...
    Position=[40 170 160 210]);
set_param(modelName+"/StimulusValid", VariableName="stimulusValid", ...
    SampleTime="1", Interpolate="off", ...
    OutputAfterFinalValue="Setting to zero");

add_line(modelName, "StimulusIq/1", "DUT/1", autorouting="on");
add_line(modelName, "StimulusValid/1", "DUT/2", autorouting="on");

names = harnessVariables;
for k = 1:numel(names)
    block = modelName+"/Log_"+names(k);
    top = 40+(k-1)*45;
    add_block("simulink/Sinks/To Workspace", block, ...
        Position=[520 top 640 top+35]);
    set_param(block, VariableName=names(k), SaveFormat="Array", ...
        SampleTime="-1", MaxDataPoints="inf");
    add_line(modelName, sprintf("DUT/%d", k), "Log_"+names(k)+"/1", ...
        autorouting="on");
end
end

function buildDut(modelName, n, m)
%BUILDDUT Streaming correlator with production and verification outputs.

dut = modelName+"/DUT";
add_block("simulink/Ports & Subsystems/Subsystem", dut, ...
    Position=[260 90 420 760]);
delete_line(dut, "In1/1", "Out1/1");
delete_block(dut+"/In1");
delete_block(dut+"/Out1");

addInport(dut, "iqIn", 1, [40 100]);
addInport(dut, "validIn", 2, [40 170]);

% --- symbol framing on the input stream -----------------------------------
add_block("simulink/User-Defined Functions/MATLAB Function", ...
    dut+"/InputFraming", Position=[170 160 300 220]);
lora_sim.set_function_script(dut+"/InputFraming", [
    "function symbolBoundary = fcn(validIn)"
    "%#codegen"
    "% First input sample of every M-sample symbol window."
    "persistent counter"
    "if isempty(counter)"
    "    counter = uint32(0);"
    "end"
    "symbolBoundary = false;"
    "if validIn"
    "    symbolBoundary = counter == uint32(0);"
    "    if counter == uint32(" + (m-1) + ")"
    "        counter = uint32(0);"
    "    else"
    "        counter = counter + uint32(1);"
    "    end"
    "end"
    "end"]);
add_line(dut, "validIn/1", "InputFraming/1", autorouting="on");

% --- M-point streaming FFT -------------------------------------------------
add_block("simulink/User-Defined Functions/MATLAB System", dut+"/FFT_M", ...
    Position=[170 80 300 140]);
set_param(dut+"/FFT_M", System="dsphdl.FFT");
set_param(dut+"/FFT_M", FFTLength=num2str(m), BitReversedOutput="off", ...
    BitReversedInput="off", Normalize="off");
add_line(dut, "iqIn/1", "FFT_M/1", autorouting="on");
add_line(dut, "validIn/1", "FFT_M/2", autorouting="on");

% --- frequency bin counter -------------------------------------------------
add_block("simulink/User-Defined Functions/MATLAB Function", ...
    dut+"/BinCounter", Position=[350 80 480 150]);
lora_sim.set_function_script(dut+"/BinCounter", [
    "function binIndex = fcn(fftValid)"
    "%#codegen"
    "% Natural-order frequency bin index q of the M-point FFT output."
    "persistent counter"
    "if isempty(counter)"
    "    counter = uint32(0);"
    "end"
    "binIndex = counter;"
    "if fftValid"
    "    if counter == uint32(" + (m-1) + ")"
    "        counter = uint32(0);"
    "    else"
    "        counter = counter + uint32(1);"
    "    end"
    "end"
    "end"]);
add_line(dut, "FFT_M/2", "BinCounter/1", autorouting="on");

% --- conjugated reference spectrum ROMs ------------------------------------
add_block("simulink/Lookup Tables/Direct Lookup Table (n-D)", ...
    dut+"/RomReal", Position=[520 60 620 110]);
set_param(dut+"/RomReal", NumberOfTableDimensions="1", ...
    Table="refConjReal", InputsSelectThisObjectFromTable="Element", ...
    TableIsInput="off", DiagnosticForOutOfRangeInput="Error");
add_block("simulink/Lookup Tables/Direct Lookup Table (n-D)", ...
    dut+"/RomImag", Position=[520 130 620 180]);
set_param(dut+"/RomImag", NumberOfTableDimensions="1", ...
    Table="refConjImag", InputsSelectThisObjectFromTable="Element", ...
    TableIsInput="off", DiagnosticForOutOfRangeInput="Error");
add_line(dut, "BinCounter/1", "RomReal/1", autorouting="on");
add_line(dut, "BinCounter/1", "RomImag/1", autorouting="on");

add_block("simulink/Math Operations/Real-Imag to Complex", ...
    dut+"/RomComplex", Position=[660 80 720 150]);
set_param(dut+"/RomComplex", Input="Real and imag");
add_line(dut, "RomReal/1", "RomComplex/1", autorouting="on");
add_line(dut, "RomImag/1", "RomComplex/2", autorouting="on");

% --- reference multiply ----------------------------------------------------
add_block("simulink/Math Operations/Product", dut+"/Multiply", ...
    Position=[770 80 820 140]);
set_param(dut+"/Multiply", Inputs="2", Multiplication="Element-wise(.*)");
add_line(dut, "FFT_M/1", "Multiply/1", autorouting="on");
add_line(dut, "RomComplex/1", "Multiply/2", autorouting="on");

% --- frequency partition accumulation --------------------------------------
add_block("simulink/User-Defined Functions/MATLAB Function", ...
    dut+"/PartitionAccumulate", Position=[870 70 1010 160]);
lora_sim.set_function_script(dut+"/PartitionAccumulate", [
    "function [partitionData, partitionValid] = fcn(product, fftValid, binIndex)"
    "%#codegen"
    "% Length-N recursive comb: y[q] = product[q] + y[q-N]."
    "% After M bins the last N outputs are sum_r product(m + r*N),"
    "% delivered in natural order m = 0..N-1."
    "persistent buffer"
    "if isempty(buffer)"
    "    buffer = complex(zeros(" + n + ", 1));"
    "end"
    "partitionData = complex(0);"
    "partitionValid = false;"
    "if fftValid"
    "    slot = mod(binIndex, uint32(" + n + ")) + uint32(1);"
    "    if binIndex < uint32(" + n + ")"
    "        accumulated = product;"
    "    else"
    "        accumulated = product + buffer(slot);"
    "    end"
    "    buffer(slot) = accumulated;"
    "    partitionData = accumulated;"
    "    partitionValid = binIndex >= uint32(" + (m-n) + ");"
    "end"
    "end"]);
add_line(dut, "Multiply/1", "PartitionAccumulate/1", autorouting="on");
add_line(dut, "FFT_M/2", "PartitionAccumulate/2", autorouting="on");
add_line(dut, "BinCounter/1", "PartitionAccumulate/3", autorouting="on");

% --- N-point streaming FFT -------------------------------------------------
add_block("simulink/User-Defined Functions/MATLAB System", dut+"/FFT_N", ...
    Position=[1060 70 1190 140]);
set_param(dut+"/FFT_N", System="dsphdl.FFT");
set_param(dut+"/FFT_N", FFTLength=num2str(n), BitReversedOutput="off", ...
    BitReversedInput="off", Normalize="off");
add_line(dut, "PartitionAccumulate/1", "FFT_N/1", autorouting="on");
add_line(dut, "PartitionAccumulate/2", "FFT_N/2", autorouting="on");

add_block("simulink/Math Operations/Gain", dut+"/ScaleByM", ...
    Position=[1240 80 1290 120]);
set_param(dut+"/ScaleByM", Gain="1/M");
add_line(dut, "FFT_N/1", "ScaleByM/1", autorouting="on");

add_block("simulink/Math Operations/Math Function", ...
    dut+"/MagnitudeSquared", Position=[1340 80 1400 120]);
set_param(dut+"/MagnitudeSquared", Operator="magnitude^2");
add_line(dut, "ScaleByM/1", "MagnitudeSquared/1", autorouting="on");

% --- peak, spectrum sum, and confidence ------------------------------------
add_block("simulink/User-Defined Functions/MATLAB Function", ...
    dut+"/PeakTracker", Position=[1450 60 1600 160]);
lora_sim.set_function_script(dut+"/PeakTracker", [
    "function [symbolIndex, peakValue, spectrumSum, symbolValid] = fcn(magSq, magValid)"
    "%#codegen"
    "% Strict > keeps the first maximum, matching MATLAB max() tie-breaking."
    "persistent counter bestValue bestIndex runningSum"
    "if isempty(counter)"
    "    counter = uint32(0);"
    "    bestValue = 0;"
    "    bestIndex = uint32(0);"
    "    runningSum = 0;"
    "end"
    "symbolIndex = uint32(0);"
    "peakValue = 0;"
    "spectrumSum = 0;"
    "symbolValid = false;"
    "if magValid"
    "    if counter == uint32(0)"
    "        bestValue = magSq;"
    "        bestIndex = counter;"
    "        runningSum = magSq;"
    "    else"
    "        if magSq > bestValue"
    "            bestValue = magSq;"
    "            bestIndex = counter;"
    "        end"
    "        runningSum = runningSum + magSq;"
    "    end"
    "    if counter == uint32(" + (n-1) + ")"
    "        symbolIndex = bestIndex;"
    "        peakValue = bestValue;"
    "        spectrumSum = runningSum;"
    "        symbolValid = true;"
    "        counter = uint32(0);"
    "    else"
    "        counter = counter + uint32(1);"
    "    end"
    "end"
    "end"]);
add_line(dut, "MagnitudeSquared/1", "PeakTracker/1", autorouting="on");
add_line(dut, "FFT_N/2", "PeakTracker/2", autorouting="on");

add_block("simulink/Sources/Constant", dut+"/SumFloor", ...
    Position=[1450 220 1500 250]);
set_param(dut+"/SumFloor", Value="eps", OutDataTypeStr="double");
add_block("simulink/Math Operations/MinMax", dut+"/GuardedSum", ...
    Position=[1560 200 1610 250]);
set_param(dut+"/GuardedSum", Function="max", Inputs="2");
add_line(dut, "PeakTracker/3", "GuardedSum/1", autorouting="on");
add_line(dut, "SumFloor/1", "GuardedSum/2", autorouting="on");

add_block("simulink/Math Operations/Divide", dut+"/Confidence", ...
    Position=[1670 180 1720 240]);
set_param(dut+"/Confidence", Inputs="*/");
add_line(dut, "PeakTracker/2", "Confidence/1", autorouting="on");
add_line(dut, "GuardedSum/1", "Confidence/2", autorouting="on");

% --- outputs ---------------------------------------------------------------
addOutport(dut, "symbolIndex", 1, [1800 60], "PeakTracker/1");
addOutport(dut, "symbolValid", 2, [1800 110], "PeakTracker/4");
addOutport(dut, "confidence", 3, [1800 160], "Confidence/1");
addOutport(dut, "peakMagnitudeSquared", 4, [1800 210], "PeakTracker/2");
addOutport(dut, "spectrumSum", 5, [1800 260], "PeakTracker/3");
addOutport(dut, "symbolBoundary", 6, [1800 310], "InputFraming/1");

addOutport(dut, "stageFftM", 7, [1800 380], "FFT_M/1");
addOutport(dut, "stageProduct", 8, [1800 430], "Multiply/1");
addOutport(dut, "stagePartition", 9, [1800 480], "PartitionAccumulate/1");
addOutport(dut, "stageFftN", 10, [1800 530], "ScaleByM/1");
addOutport(dut, "stageMagnitudeSquared", 11, [1800 580], "MagnitudeSquared/1");
addOutport(dut, "fftMValid", 12, [1800 630], "FFT_M/2");
addOutport(dut, "partitionValid", 13, [1800 680], "PartitionAccumulate/2");
addOutport(dut, "fftNValid", 14, [1800 730], "FFT_N/2");

set_param(dut, TreatAsAtomicUnit="on");
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
