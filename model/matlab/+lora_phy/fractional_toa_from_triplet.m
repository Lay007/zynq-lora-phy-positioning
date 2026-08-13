function result = fractional_toa_from_triplet(magnitudes, options)
%FRACTIONAL_TOA_FROM_TRIPLET Hardware-shaped sub-sample ToA interpolation.
%
% The estimator LORA_PHY.ESTIMATE_FRACTIONAL_TOA performs, reduced to what a
% DUT actually has to do: three correlation magnitudes in, one sub-sample
% offset out. It exists so the Simulink block has a reference of the same
% shape, in the same way the joint estimator and the blind detector do.
%
% Why a Gaussian rather than a parabola is measured and recorded in
% ESTIMATE_FRACTIONAL_TOA: a chirp correlation peak is not a parabola, and
% fitting one leaves 75 m of systematic bias that no amount of SNR removes.
%
% The logarithm is the only part with a hardware cost, and it is small. In
% fixed point log2 splits into the position of the leading one, which a
% priority encoder gives for free, and a table on the mantissa. Measured
% against the delay sweep:
%
%   exact log       8.1 m        16 entries   15.0 m
%   64 entries      9.1 m        32 entries   10.4 m
%
% So 64 entries land within a metre of the exact logarithm, against a noise
% floor of 22.9 m at 0 dB SNR. That is a distributed ROM of a few hundred
% bits and no BRAM. LogTableBits = 0 selects the exact logarithm, which is
% what the floating-point model uses.
%
% Only differences of logs enter the result, so any constant offset in the
% approximation cancels and only the table's shape matters.

arguments
    magnitudes (3,1) {mustBeNumeric, mustBeNonnegative}
    options.LogTableBits (1,1) double ...
        {mustBeInteger, mustBeNonnegative} = 6
end

values = double(magnitudes);
result = struct;
result.logTableBits = options.LogTableBits;
result.valid = all(values > 0);
result.fractionalOffsetSamples = 0;
if ~result.valid
    % A zero beside the peak means the window is clipped or empty. Returning
    % zero with valid=false is deliberate: log(0) would otherwise produce a
    % silent NaN offset that looks like a measurement.
    return;
end

logs = arrayfun(@(v) approximateLog2(v, options.LogTableBits), values);
denominator = logs(1)-2*logs(2)+logs(3);
if denominator ~= 0
    offset = 0.5*(logs(1)-logs(3))/denominator;
    result.fractionalOffsetSamples = max(-0.5, min(0.5, offset));
end
result.logs = logs;
end

function y = approximateLog2(x, bits)
%APPROXIMATELOG2 Leading-one position plus a mantissa table.
if bits == 0
    y = log2(x);
    return;
end
exponent = floor(log2(x));
mantissa = x/2^exponent-1;
index = min(2^bits-1, floor(mantissa*2^bits));
y = exponent+log2(1+(index+0.5)/2^bits);
end
