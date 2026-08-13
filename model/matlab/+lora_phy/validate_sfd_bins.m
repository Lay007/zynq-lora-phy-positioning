function result = validate_sfd_bins(downBins, preambleBin, config, options)
%VALIDATE_SFD_BINS Confirm the SFD downchirps follow the preamble.
%
% The last acceptance step before framing. Preamble and sync word say a
% packet is probably there; the SFD says the receiver has found the packet
% *structure* rather than a run of upchirps that happen to agree.
%
% The rule is measured rather than assumed. Dechirping the SFD windows with
% LORA_PHY.DOWNCHIRP_REFERENCE_SPECTRUM on a grid already realigned to the
% packet gives, for injected offsets of 0, 1 and 3 bins:
%
%   preamble bin   0   1     3
%   SFD down bin   0   127   125
%
% that is, downBin = mod(-preambleBin, N). Whatever displaces the preamble
% upward displaces the SFD downward by the same amount, which is the same
% mirror the joint estimator exploits.
%
% This deliberately does not split the displacement into CFO and timing.
% That is LORA_PHY.JOINT_TIMING_CFO_FROM_BINS's job and it has its own sign
% convention, verified against 130 real packets; duplicating the split here
% with a second convention would be a good way to end up with two.
%
% The check is only valid on a realigned grid. On the free-running grid the
% preamble bin carries the whole-chip offset as well, and the mirror no
% longer holds.
%
% RESULT fields:
%   expectedBin   mod(-preambleBin, N)
%   distances     circular distance of each SFD bin from expectedBin
%   agree         the SFD windows agree with each other
%   valid         every SFD bin is within BinTolerance of expectedBin

arguments
    downBins (:,1) {mustBeNumeric, mustBeInteger, mustBeNonnegative}
    preambleBin (1,1) {mustBeNumeric, mustBeInteger, mustBeNonnegative}
    config (1,1) struct
    options.BinTolerance (1,1) double ...
        {mustBeInteger, mustBeNonnegative} = 1
end

n = config.symbolCount;
if isempty(downBins)
    error("lora_phy:InvalidSfdBinCount", "Expected at least one SFD bin");
end
if any(downBins >= n) || preambleBin >= n
    error("lora_phy:BinOutOfRange", "Bins must be in [0, %d]", n-1);
end

values = double(downBins);
expected = mod(-double(preambleBin), n);
delta = mod(values-expected+n/2, n)-n/2;

result = struct;
result.expectedBin = expected;
result.distances = abs(delta);
result.valid = all(result.distances <= options.BinTolerance);
result.agree = max(abs(mod(values-values(1)+n/2, n)-n/2)) ...
    <= options.BinTolerance;
result.binTolerance = options.BinTolerance;
end
