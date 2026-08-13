function info = build_toa_interpolator_model(options)
%BUILD_TOA_INTERPOLATOR_MODEL Generate the sub-sample ToA interpolator.
%
% Seventh M2 subsystem, and the one the whole positioning goal rests on: the
% coarse timestamp resolves a whole sample, 1199 m at Fs = 250 kHz, so
% everything TDoA can do comes from this block.
%
%   info = build_toa_interpolator_model(LogTableBits=6);
%
% Mirrors LORA_PHY.FRACTIONAL_TOA_FROM_TRIPLET: three correlation magnitudes
% in, one sub-sample offset out. Finding the peak and narrowing the search to
% +-L is the correlator's and the realignment's job; this block only
% interpolates.
%
% The fit is Gaussian, not parabolic, because a chirp correlation peak is not
% a parabola and fitting one leaves 75 m of systematic bias that no amount of
% SNR removes. That bias is deterministic, so it survives averaging and does
% not cancel across three stations -- it becomes a position offset.
%
% log2 is built the way hardware builds it: the position of the leading one,
% which is a priority encoder, plus a table on the mantissa. The table is
% generated here from the same expression the MATLAB reference uses, so the
% two cannot drift apart. Measured, 64 entries land within a metre of the
% exact logarithm against a 22.9 m noise floor at 0 dB, which is a few
% hundred bits of distributed ROM and no BRAM.
%
% Only differences of logs enter the result, so a constant offset in the
% approximation cancels; that is why so coarse a table costs so little.

arguments
    options.LogTableBits (1,1) double ...
        {mustBeInteger, mustBePositive} = 6
    options.MagnitudeBits (1,1) double {mustBeInteger, mustBePositive} = 32
    options.FractionBits (1,1) double {mustBeInteger, mustBePositive} = 12
    options.ModelName (1,1) string = "lora_toa_interpolator"
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
entries = 2^options.LogTableBits;
scale = 2^options.FractionBits;

% log2(1+m) at the centre of each mantissa bucket, in fixed point. Same
% expression as lora_phy.fractional_toa_from_triplet's approximateLog2.
table = round(scale*log2(1+((0:entries-1)+0.5)/entries));
tableLiteral = "["+strjoin(string(table), " ")+"]";

dut = modelName+"/DUT";
add_block("simulink/Ports & Subsystems/Subsystem", dut, ...
    Position=[240 80 460 300]);
delete_line(dut, "In1/1", "Out1/1");
delete_block(dut+"/In1");
delete_block(dut+"/Out1");

inputs = ["magnitudeBefore", "magnitudePeak", "magnitudeAfter", ...
    "tripletValid"];
for k = 1:numel(inputs)
    block = dut+"/"+inputs(k);
    add_block("simulink/Sources/In1", block, ...
        Position=[40 60+(k-1)*55 70 80+(k-1)*55]);
    set_param(block, Port=num2str(k));
end

add_block("simulink/User-Defined Functions/MATLAB Function", ...
    dut+"/ToaInterpolator", Position=[180 40 420 260]);
lora_sim.set_function_script(dut+"/ToaInterpolator", [
    "function [offsetSamples, offsetValid, logPeak] = fcn(magnitudeBefore, magnitudePeak, magnitudeAfter, tripletValid)"
    "%#codegen"
    "% Gaussian three-point interpolation, matching"
    "% lora_phy.fractional_toa_from_triplet."
    "%"
    "% offsetSamples is in units of 1/" + (2^options.FractionBits) + " sample, signed."
    "persistent logTable"
    "if isempty(logTable)"
    "    logTable = int32(" + tableLiteral + ");"
    "end"
    ""
    "offsetSamples = int32(0);"
    "offsetValid = false;"
    "logPeak = int32(0);"
    ""
    "% A zero beside the peak means a clipped or empty window. Reporting"
    "% invalid beats emitting a number the caller cannot tell apart from a"
    "% measurement."
    "if ~tripletValid || magnitudeBefore == 0 || magnitudePeak == 0 || magnitudeAfter == 0"
    "    return;"
    "end"
    ""
    "logA = approximateLog2(magnitudeBefore, logTable);"
    "logB = approximateLog2(magnitudePeak, logTable);"
    "logC = approximateLog2(magnitudeAfter, logTable);"
    "logPeak = logB;"
    ""
    "denominator = logA - int32(2)*logB + logC;"
    "if denominator == int32(0)"
    "    return;"
    "end"
    ""
    "% offset = 0.5*(logA-logC)/denominator, carried in 1/" + (2^options.FractionBits) + " sample."
    "numerator = int32(" + (2^(options.FractionBits-1)) + ")*(logA - logC);"
    "value = idivide(numerator, denominator, 'fix');"
    "limit = int32(" + (2^(options.FractionBits-1)) + ");"
    "if value > limit"
    "    value = limit;"
    "elseif value < -limit"
    "    value = -limit;"
    "end"
    "offsetSamples = value;"
    "offsetValid = true;"
    "end"
    ""
    "function y = approximateLog2(x, logTable)"
    "%#codegen"
    "% Leading-one position plus a mantissa table, which is how hardware"
    "% builds a logarithm: the exponent is a priority encoder and costs"
    "% nothing, the table is a few hundred bits of ROM."
    "value = uint32(x);"
    "exponent = int32(0);"
    "for bit = int32(31):int32(-1):int32(1)"
    "    if bitshift(value, -bit) > uint32(0) && exponent == int32(0)"
    "        exponent = bit;"
    "    end"
    "end"
    "% Mantissa: the " + options.LogTableBits + " bits below the leading one."
    "shifted = uint32(0);"
    "if exponent >= int32(" + options.LogTableBits + ")"
    "    shifted = bitshift(value, -(exponent-int32(" + options.LogTableBits + ")));"
    "else"
    "    shifted = bitshift(value, int32(" + options.LogTableBits + ")-exponent);"
    "end"
    "index = int32(bitand(shifted, uint32(" + (entries-1) + ")));"
    "y = exponent*int32(" + scale + ") + logTable(index+1);"
    "end"]);

for k = 1:numel(inputs)
    add_line(dut, inputs(k)+"/1", sprintf("ToaInterpolator/%d", k), ...
        autorouting="on");
end

outputs = ["offsetSamples", "offsetValid", "logPeak"];
for k = 1:numel(outputs)
    block = dut+"/"+outputs(k);
    add_block("simulink/Sinks/Out1", block, ...
        Position=[560 60+(k-1)*55 590 80+(k-1)*55]);
    set_param(block, Port=num2str(k));
    add_line(dut, sprintf("ToaInterpolator/%d", k), outputs(k)+"/1", ...
        autorouting="on");
end
set_param(dut, TreatAsAtomicUnit="on");

variables = "stimulus"+["MagnitudeBefore", "MagnitudePeak", ...
    "MagnitudeAfter", "TripletValid"];
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
info.logTableBits = options.LogTableBits;
info.logTableEntries = entries;
info.fractionBits = options.FractionBits;
info.offsetScale = scale;
info.outputVariables = outputs;
end
