function result = validate_acquisition_bins(preambleBins, syncBins, ...
    syncWord, config, options)
%VALIDATE_ACQUISITION_BINS Accept or reject a preamble and sync-word pair.
%
% Acquisition is decided entirely on dechirped bin indices: the preamble
% upchirps must all land near bin 0, and the two sync symbols must land near
% the bins the sync word encodes. Both tests are circular, because a bin is
% only defined modulo N.
%
% LoRa encodes each sync-word nibble as a symbol index multiplied by 8. The
% scale is fixed at 8; it is not 2^(SF-4) for spreading factors other than
% seven, which is a common and expensive misreading.
%
% This is integer arithmetic on bins, like LORA_PHY.JOINT_TIMING_CFO_FROM_BINS,
% so the Simulink and HDL implementation can be bit-exact rather than close.
%
% RESULT fields:
%   expectedSyncBins    the two bins the sync word encodes
%   preambleDistances   circular distance of each preamble bin from 0
%   syncDistances       circular distance of each sync bin from its target
%   preambleValid       every preamble distance within BinTolerance
%   syncValid           both sync distances within BinTolerance
%   valid               preambleValid && syncValid
%   binTolerance        the tolerance actually applied

arguments
    preambleBins (:,1) {mustBeNumeric, mustBeInteger, mustBeNonnegative}
    syncBins (:,1) {mustBeNumeric, mustBeInteger, mustBeNonnegative}
    syncWord (1,1) {mustBeNumeric, mustBeInteger, mustBeNonnegative}
    config (1,1) struct
    options.BinTolerance (1,1) double ...
        {mustBeInteger, mustBeNonnegative} = 1
end

if numel(syncBins) ~= 2
    error("lora_phy:InvalidSyncBinCount", ...
        "Exactly two sync-word symbols are required");
end
if syncWord > 255
    error("lora_phy:InvalidSyncWord", "SyncWord must fit one byte");
end
n = config.symbolCount;
if any(preambleBins >= n) || any(syncBins >= n)
    error("lora_phy:BinOutOfRange", "Bins must be in [0, %d]", n-1);
end

syncScale = 8;
expectedSyncBins = syncScale*double([bitshift(uint8(syncWord), -4); ...
    bitand(uint8(syncWord), 15)]);

preambleDistances = circularDistance(preambleBins, 0, n);
syncDistances = circularDistance(syncBins, expectedSyncBins, n);

result = struct;
result.expectedSyncBins = expectedSyncBins;
result.preambleDistances = preambleDistances;
result.syncDistances = syncDistances;
result.preambleValid = all(preambleDistances <= options.BinTolerance);
result.syncValid = all(syncDistances <= options.BinTolerance);
result.valid = result.preambleValid && result.syncValid;
result.binTolerance = options.BinTolerance;
end

function distance = circularDistance(values, reference, modulus)
delta = mod(double(values)-double(reference)+modulus/2, modulus)-modulus/2;
distance = abs(delta);
end
