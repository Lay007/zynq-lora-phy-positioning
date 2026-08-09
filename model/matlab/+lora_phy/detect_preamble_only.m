function result = detect_preamble_only(bins, config, options)
%DETECT_PREAMBLE_ONLY Preamble decision from preamble bins alone.
%
% LORA_PHY.DETECT_PREAMBLE_RUN decides preamble and sync together over
% PreambleSymbols+2 bins. That is the right shape for scoring a candidate
% offline, and the wrong shape for a receiver, because the decision cannot
% be available until two windows of sync word have already gone past.
%
% Composing the Simulink subsystems is what exposed it. The front-end
% realigns the window grid using chipsToBoundary, so the realignment cannot
% take effect until the preamble flag asserts; with the flag gated on the
% sync slots it always arrived after the sync word, at every preamble length.
% Lengthening the preamble does not help, because the decision waits on the
% two windows that follow it rather than on the preamble itself.
%
% So the preamble decision is defined here on PreambleSymbols bins and
% nothing else, and DETECT_PREAMBLE_RUN calls this for its preamble half.
% One definition, two call sites.
%
% RESULT fields:
%   preambleBin        bin the preamble settled on, = chipsSinceBoundary
%   chipsSinceBoundary chips elapsed since the last symbol boundary
%   chipsToBoundary    mod(-preambleBin, N), chips to advance to align
%   distances          circular distance of each bin from the first
%   preambleValid      every bin within BinTolerance of the first

arguments
    bins (:,1) {mustBeNumeric, mustBeInteger, mustBeNonnegative}
    config (1,1) struct
    options.BinTolerance (1,1) double ...
        {mustBeInteger, mustBeNonnegative} = 1
end

n = config.symbolCount;
if isempty(bins)
    error("lora_phy:InvalidRunLength", "Expected at least one bin");
end
if any(bins >= n)
    error("lora_phy:BinOutOfRange", "Bins must be in [0, %d]", n-1);
end

values = double(bins);
reference = values(1);
delta = mod(values-reference+n/2, n)-n/2;

result = struct;
result.preambleBin = reference;
result.chipsSinceBoundary = reference;
result.chipsToBoundary = mod(-reference, n);
result.distances = abs(delta);
result.preambleValid = all(result.distances <= options.BinTolerance);
result.binTolerance = options.BinTolerance;
end
