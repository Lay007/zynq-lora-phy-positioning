function result = detect_preamble_run(bins, syncWord, config, options)
%DETECT_PREAMBLE_RUN Blind acquisition decision from a run of symbol bins.
%
% A free-running correlator that is never told where a packet begins still
% sees the preamble clearly, and this is why no sliding correlation over
% sample offsets is needed to find one.
%
% The preamble is a literal repetition of one upchirp, so the transmitted
% block is periodic with samplesPerSymbol. Any window of that length is a
% cyclic rotation of the reference chirp, and a rotation dechirps to a clean
% tone. Take a window starting d chips after a symbol boundary: at local
% chip c the signal carries chip mod(c+d, N), whose normalised frequency is
% mod(c+d,N)/N - 1/2, and the conjugate reference contributes -(c/N - 1/2).
% The product sits at d/N for every c. So
%
%   bin = d, the number of chips elapsed since the last symbol boundary,
%
% and consecutive windows one symbol apart land on the same bin whatever the
% alignment is. Detection costs nothing beyond the correlator that already
% runs, and the bin itself carries the whole-chip timing offset.
%
% Two limits, both real:
%
% * The estimate is whole-chip. The sub-chip remainder is invisible here and
%   is the job of LORA_PHY.JOINT_TIMING_CFO_FROM_BINS and of fractional ToA.
% * A carrier frequency offset shifts the dechirped tone as well, so the bin
%   is d + cfoBins, not d. On an upchirp-only preamble the two are
%   indistinguishable; the SFD downchirp pair separates them.
%
% The second limit is why the sync word is checked *relative* to the
% preamble bin rather than at absolute positions: CFO displaces the preamble
% and the sync symbols by the same amount, so the relative check survives it
% and the absolute one does not. LORA_PHY.VALIDATE_ACQUISITION_BINS is the
% absolute check, correct once the receiver has already corrected timing and
% CFO. This function is the blind case, before any correction exists.
%
% RESULT fields:
%   preambleBin        bin the preamble settled on, = chipsSinceBoundary
%   chipsSinceBoundary chips elapsed since the last symbol boundary
%   chipsToBoundary    mod(-preambleBin, N), chips to advance to align
%   expectedSyncBins   preambleBin + 8*nibble, wrapped
%   preambleDistances  circular distance of each preamble bin from the first
%   syncDistances      circular distance of each sync bin from its target
%   preambleValid, syncValid, valid

arguments
    bins (:,1) {mustBeNumeric, mustBeInteger, mustBeNonnegative}
    syncWord (1,1) {mustBeNumeric, mustBeInteger, mustBeNonnegative}
    config (1,1) struct
    options.PreambleSymbols (1,1) double ...
        {mustBeInteger, mustBePositive} = 8
    options.BinTolerance (1,1) double ...
        {mustBeInteger, mustBeNonnegative} = 1
end

preambleSymbols = options.PreambleSymbols;
if numel(bins) ~= preambleSymbols+2
    error("lora_phy:InvalidRunLength", ...
        "Expected %d bins (%d preamble plus two sync), got %d", ...
        preambleSymbols+2, preambleSymbols, numel(bins));
end
if syncWord > 255
    error("lora_phy:InvalidSyncWord", "SyncWord must fit one byte");
end
n = config.symbolCount;
if any(bins >= n)
    error("lora_phy:BinOutOfRange", "Bins must be in [0, %d]", n-1);
end

preambleBins = double(bins(1:preambleSymbols));
syncBins = double(bins(preambleSymbols+(1:2)));

preambleBin = preambleBins(1);
syncScale = 8;
expectedSyncBins = mod(preambleBin+syncScale*double([ ...
    bitshift(uint8(syncWord), -4); bitand(uint8(syncWord), 15)]), n);

preambleDistances = circularDistance(preambleBins, preambleBin, n);
syncDistances = circularDistance(syncBins, expectedSyncBins, n);

result = struct;
result.preambleBin = preambleBin;
result.chipsSinceBoundary = preambleBin;
result.chipsToBoundary = mod(-preambleBin, n);
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
