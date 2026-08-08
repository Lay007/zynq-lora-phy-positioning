function estimate = joint_timing_cfo_from_bins(upBin, downBin, config)
%JOINT_TIMING_CFO_FROM_BINS Split whole-chip timing from carrier offset.
%
% A single upchirp cannot separate the two: a whole-chip timing offset and
% a carrier offset both move the dechirped peak. The downchirp flips the
% sign of the timing term only, so
%
%   cfoBins     = (upSigned + downSigned)/2
%   timingChips = (upSigned - downSigned)/2
%
% Both halves are exact multiples of 1/2, so this whole estimator is
% integer arithmetic in units of half a bin. That is what lets the Simulink
% and HDL implementation be bit-exact rather than merely close.
%
% ESTIMATE fields:
%   upSigned, downSigned     signed bin indices in [-N/2, N/2)
%   cfoHalfBins              2*cfoBins, an exact integer
%   timingHalfChips          2*timingChips, an exact integer
%   cfoBins, timingChips     the halved values
%   correctionSamples        round(-timingChips*L), zeroed when implausible
%   rejected                 true when the timing correction was zeroed
%
% Convert to Hz with cfoHz = cfoBins*Fs/samplesPerSymbol.

arguments
    upBin (:,1) {mustBeNumeric, mustBeInteger, mustBeNonnegative}
    downBin (:,1) {mustBeNumeric, mustBeInteger, mustBeNonnegative}
    config (1,1) struct
end

if numel(upBin) ~= numel(downBin)
    error("lora_phy:BinCountMismatch", ...
        "upBin and downBin must have the same number of elements");
end
n = config.symbolCount;
if any(upBin >= n) || any(downBin >= n)
    error("lora_phy:BinOutOfRange", ...
        "Bins must be in [0, %d]", n-1);
end

upSigned = signedBin(double(upBin), n);
downSigned = signedBin(double(downBin), n);

cfoHalfBins = upSigned+downSigned;
timingHalfChips = upSigned-downSigned;

% round(-timingChips*L) with MATLAB's ties-away-from-zero rule, computed on
% integers so no floating-point rounding mode can change the result.
scaled = -timingHalfChips*config.samplesPerChip;
correctionSamples = sign(scaled).*floor((abs(scaled)+1)/2);

% Defensive plausibility guard. For bins that are genuinely in [0, N) it is
% unreachable: |timingChips| <= (N-1)/2 bounds the correction by
% (N-1)*L/2, which never exceeds M/2 + L. It is kept because a future
% caller may supply bins from a wider search, and
% TestJointTimingCfo proves it stays inactive today.
limit = config.samplesPerSymbol/2+config.samplesPerChip;
rejected = abs(correctionSamples) > limit;
correctionSamples(rejected) = 0;

estimate = struct;
estimate.upSigned = upSigned;
estimate.downSigned = downSigned;
estimate.cfoHalfBins = cfoHalfBins;
estimate.timingHalfChips = timingHalfChips;
estimate.cfoBins = cfoHalfBins/2;
estimate.timingChips = timingHalfChips/2;
estimate.correctionSamples = correctionSamples;
estimate.rejected = rejected;
end

function value = signedBin(bin, modulus)
value = mod(bin+modulus/2, modulus)-modulus/2;
end
