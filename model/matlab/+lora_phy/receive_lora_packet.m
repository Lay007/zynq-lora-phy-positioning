function result = receive_lora_packet( ...
    iq, sampleRateHz, bandwidthHz, spreadingFactor, options)
%RECEIVE_LORA_PACKET Synchronize and decode one standard on-air LoRa packet.
%
% The receiver uses the strongest-burst inspector for coarse acquisition,
% validates the programmable preamble and sync word, accounts for the LoRa
% 2.25-downchirp SFD, searches a small payload timing neighbourhood, and then
% passes hard FFT decisions to the packet coding decoder.

arguments
    iq (:,1) {mustBeNumeric}
    sampleRateHz (1,1) double {mustBePositive}
    bandwidthHz (1,1) double {mustBePositive}
    spreadingFactor (1,1) double {mustBeInteger, mustBeGreaterThanOrEqual(spreadingFactor,5), mustBeLessThanOrEqual(spreadingFactor,12)}
    options.PreambleSymbols (1,1) double {mustBeInteger, mustBePositive} = 8
    options.SyncWord (1,1) double {mustBeInteger, mustBeNonnegative} = hex2dec("12")
    options.IqInverted (1,1) logical = false
    options.LowDataRateOptimization (1,1) double = NaN
    options.ExpectedCarrierOffsetHz (1,1) double = NaN
    options.SoftDecoding (1,1) logical = true
    options.MaximumPayloadSymbols (1,1) double {mustBeInteger, mustBePositive} = 1024
end

if options.SyncWord > 255
    error("lora_phy:InvalidSyncWord", "SyncWord must fit one byte");
end
samplesPerChip = sampleRateHz/bandwidthHz;
if abs(samplesPerChip-round(samplesPerChip)) > 1e-9
    error("lora_phy:NonIntegerOversampling", ...
        "On-air decoding currently requires an integer Fs/BW ratio");
end
samplesPerChip = round(samplesPerChip);
symbolSamples = samplesPerChip*2^spreadingFactor;

workingIq = double(iq(:));
if options.IqInverted
    workingIq = conj(workingIq);
end
frontEndShiftHz = 0;
if ~isnan(options.ExpectedCarrierOffsetHz)
    frontEndShiftHz = options.ExpectedCarrierOffsetHz;
    if options.IqInverted
        frontEndShiftHz = -frontEndShiftHz;
    end
    sampleIndices = (0:numel(workingIq)-1).';
    workingIq = workingIq.*exp(-2j*pi*frontEndShiftHz*sampleIndices/sampleRateHz);
end
inspection = lora_phy.inspect_iq_capture(workingIq, sampleRateHz, ...
    CandidateBandwidthHz=bandwidthHz, ...
    CandidateSpreadingFactors=spreadingFactor, ...
    MaximumSymbols=max(options.PreambleSymbols+4, 16));

demodulationCentreHz = inspection.estimatedCarrierOffsetHz;
demodulationResidualCfoHz = inspection.residualCfoHz;
coarsePreambleStart = inspection.alignedStartIndex;
effectivePacketEnd = inspection.packetEndIndex;
usedChirpSearch = inspection.packetStartIndex == 1 && ...
    inspection.packetEndIndex > 0.5*numel(workingIq);
usedChirpSearch = usedChirpSearch || ...
    (~isnan(options.ExpectedCarrierOffsetHz) && ...
    bandwidthHz >= 0.45*sampleRateHz);
if usedChirpSearch
    coarsePreambleStart = locate_repeated_upchirps(workingIq, ...
        spreadingFactor, samplesPerChip, options.PreambleSymbols);
    demodulationCentreHz = 0;
    demodulationResidualCfoHz = 0;
    effectivePacketEnd = numel(workingIq);
end

acquisitionCount = options.PreambleSymbols+2;
% LoRa encodes each sync-word nibble as a symbol index multiplied by 8.
% The scale is fixed; it is not 2^(SF-4) for SF other than seven.
syncScale = 8;
expectedSyncBins = syncScale*double([bitshift(uint8(options.SyncWord), -4); ...
    bitand(uint8(options.SyncWord), 15)]);
symbolSearchRadius = 4;
if usedChirpSearch
    symbolSearchRadius = options.PreambleSymbols;
end
preambleCandidates = coarsePreambleStart + ...
    (-symbolSearchRadius:symbolSearchRadius).'*symbolSamples + ...
    (-samplesPerChip:samplesPerChip);
preambleCandidates = unique(round(preambleCandidates(:)));
bestAcquisitionScore = -inf;
preambleStart = inspection.alignedStartIndex;
acquisitionSymbols = zeros(0, 1);
acquisitionConfidence = zeros(0, 1);
for candidateStart = preambleCandidates.'
    [candidateSymbols, candidateConfidence] = demodulate_windows( ...
        workingIq, candidateStart, acquisitionCount, candidateStart, ...
        sampleRateHz, bandwidthHz, spreadingFactor, ...
        demodulationCentreHz, demodulationResidualCfoHz);
    if numel(candidateSymbols) ~= acquisitionCount
        continue
    end
    candidatePreamble = candidateSymbols(1:options.PreambleSymbols);
    candidateSync = candidateSymbols(options.PreambleSymbols+(1:2));
    mismatch = sum(circular_distance(candidatePreamble, 0, ...
        2^spreadingFactor)) + sum(circular_distance(candidateSync, ...
        expectedSyncBins, 2^spreadingFactor));
    score = -mismatch + 0.01*mean(candidateConfidence);
    if score > bestAcquisitionScore
        bestAcquisitionScore = score;
        preambleStart = candidateStart;
        acquisitionSymbols = candidateSymbols;
        acquisitionConfidence = candidateConfidence;
    end
end
% Every candidate offset is rejected when the segment cannot hold a complete
% preamble and sync word, which happens for short activity runs near the end
% of a capture. Report it as an identified failure instead of indexing an
% empty acquisition.
if numel(acquisitionSymbols) ~= acquisitionCount
    error("lora_phy:AcquisitionWindowTooShort", ...
        "No candidate offset yielded %d complete acquisition symbols; " + ...
        "the segment is too short to validate the preamble and sync word", ...
        acquisitionCount);
end
preambleBins = acquisitionSymbols(1:options.PreambleSymbols);
syncBins = acquisitionSymbols(options.PreambleSymbols+(1:2));
preambleValid = all(circular_distance(preambleBins, 0, 2^spreadingFactor) <= 1);
syncValid = all(circular_distance(syncBins, double(expectedSyncBins), ...
    2^spreadingFactor) <= 1);

if isnan(options.LowDataRateOptimization)
    lowDataRateOptimization = 2^spreadingFactor/bandwidthHz >= 16e-3;
elseif ismember(options.LowDataRateOptimization, [0, 1])
    lowDataRateOptimization = logical(options.LowDataRateOptimization);
else
    error("lora_phy:InvalidLdro", ...
        "LowDataRateOptimization must be NaN (auto), zero, or one");
end
config = lora_phy.phy_config(spreadingFactor, samplesPerChip, 1);
config.lowDataRateOptimization = lowDataRateOptimization;

sx126xLowSfPadding = 2*(spreadingFactor < 7);
nominalPayloadStart = preambleStart + round( ...
    (options.PreambleSymbols+2+2.25+sx126xLowSfPadding)*symbolSamples);
searchOffsets = (-samplesPerChip:samplesPerChip).';
bestCandidate = struct("offset", 0, "symbols", zeros(0,1), ...
    "confidence", zeros(0,1), "metrics", zeros(0, 2^spreadingFactor), ...
    "hardDecoded", struct, "softDecoded", struct, ...
    "decoded", struct, "score", -inf);
for candidate = 1:numel(searchOffsets)
    candidateStart = nominalPayloadStart+searchOffsets(candidate);
    candidateSymbolCount = floor( ...
        (effectivePacketEnd-candidateStart+1)/symbolSamples);
    candidateSymbolCount = max(0, min( ...
        options.MaximumPayloadSymbols, candidateSymbolCount));
    [symbols, confidence, metrics] = demodulate_windows( ...
        workingIq, candidateStart, candidateSymbolCount, preambleStart, ...
        sampleRateHz, bandwidthHz, spreadingFactor, ...
        demodulationCentreHz, demodulationResidualCfoHz);
    hardDecoded = lora_phy.decode_packet(symbols, config);
    softDecoded = lora_phy.decode_packet_soft(metrics, config);
    decoded = hardDecoded;
    if options.SoftDecoding && (softDecoded.success || ~hardDecoded.success)
        decoded = softDecoded;
    end
    score = mean(confidence);
    if hardDecoded.headerValid || softDecoded.headerValid
        score = score+10;
    end
    if hardDecoded.success
        score = score+100;
    end
    if softDecoded.success
        score = score+120;
    end
    if score > bestCandidate.score
        bestCandidate.offset = searchOffsets(candidate);
        bestCandidate.symbols = symbols;
        bestCandidate.confidence = confidence;
        bestCandidate.metrics = metrics;
        bestCandidate.hardDecoded = hardDecoded;
        bestCandidate.softDecoded = softDecoded;
        bestCandidate.decoded = decoded;
        bestCandidate.score = score;
    end
end
timingOffset = bestCandidate.offset;
payloadStart = nominalPayloadStart+timingOffset;
symbols = bestCandidate.symbols;
symbolConfidence = bestCandidate.confidence;
symbolMetrics = bestCandidate.metrics;
decoded = bestCandidate.decoded;

result = struct;
result.success = preambleValid && syncValid && decoded.success;
result.preambleValid = preambleValid;
result.syncValid = syncValid;
result.preambleBins = preambleBins;
result.syncBins = syncBins;
result.expectedSyncBins = double(expectedSyncBins);
result.acquisitionConfidence = acquisitionConfidence;
result.preambleStartIndex = preambleStart;
result.preambleStartSeconds = (preambleStart-1)/sampleRateHz;
result.payloadStartIndex = payloadStart;
result.payloadStartSeconds = (payloadStart-1)/sampleRateHz;
result.timingOffsetSamples = timingOffset;
result.symbols = symbols;
result.symbolConfidence = symbolConfidence;
result.symbolMetrics = symbolMetrics;
result.decoded = decoded;
result.hardDecoded = bestCandidate.hardDecoded;
result.softDecoded = bestCandidate.softDecoded;
result.inspection = inspection;
result.inspection.estimatedCarrierOffsetHz = ...
    inspection.estimatedCarrierOffsetHz+frontEndShiftHz;
result.config = config;
result.preambleSymbols = options.PreambleSymbols;
result.syncWord = uint8(options.SyncWord);
result.iqInverted = options.IqInverted;
result.lowSfPaddingSymbols = sx126xLowSfPadding;
result.frontEndFrequencyShiftHz = frontEndShiftHz;
result.usedChirpPreambleSearch = usedChirpSearch;
result.residualCfoHz = demodulationResidualCfoHz;
result.softDecoding = options.SoftDecoding;
result.decodingMethod = "hard";
if options.SoftDecoding && isequaln(decoded, bestCandidate.softDecoded)
    result.decodingMethod = "soft";
end

result.packetEndIndex = min(numel(iq), payloadStart + ...
    decoded.consumedSymbolCount*symbolSamples-1);
result.packetEndSeconds = (result.packetEndIndex-1)/sampleRateHz;
end

function startIndex = locate_repeated_upchirps(iq, sf, samplesPerChip, preambleSymbols)
config = lora_phy.css_config(sf, samplesPerChip);
reference = lora_phy.reference_chirp(config, "up");
symbolSamples = config.samplesPerSymbol;
hop = max(1, floor(symbolSamples/4));
starts = (1:hop:numel(iq)-symbolSamples+1).';
confidence = zeros(size(starts));
bins = zeros(size(starts));
for index = 1:numel(starts)
    indices = starts(index)+(0:symbolSamples-1);
    dechirped = iq(indices(:)).*conj(reference);
    spectrum = abs(fft(dechirped(1:samplesPerChip:end))).^2;
    [peak, peakIndex] = max(spectrum);
    confidence(index) = peak/max(sum(spectrum), eps);
    bins(index) = peakIndex-1;
end
stride = round(symbolSamples/hop);
repetitions = min(8, preambleSymbols);
last = numel(starts)-(repetitions-1)*stride;
scores = -inf(max(last, 0), 1);
for index = 1:last
    rows = index+(0:repetitions-1)*stride;
    binDistance = circular_distance(bins(rows), bins(rows(1)), 2^sf);
    scores(index) = mean(confidence(rows))-0.05*mean(binDistance);
end
[~, best] = max(scores);
startIndex = starts(best);
end

function [symbols, confidence, metrics] = demodulate_windows( ...
    iq, startIndex, symbolCount, phaseOrigin, fs, bw, sf, centre, residualCfo)
samplesPerChip = round(fs/bw);
symbolSamples = samplesPerChip*2^sf;
if symbolCount < 1 || startIndex < 1 || ...
        startIndex+symbolCount*symbolSamples-1 > numel(iq)
    symbols = zeros(0, 1);
    confidence = zeros(0, 1);
    metrics = zeros(0, 2^sf);
    return
end
config = lora_phy.css_config(sf, samplesPerChip);
reference = lora_phy.reference_chirp(config, "up");
localTime = (0:symbolSamples-1).'/fs;
residualCorrection = exp(-2j*pi*residualCfo*localTime);
symbols = zeros(symbolCount, 1);
confidence = zeros(symbolCount, 1);
metrics = zeros(symbolCount, 2^sf);
for symbol = 1:symbolCount
    indices = startIndex+(symbol-1)*symbolSamples+(0:symbolSamples-1);
    carrierTime = (indices(:)-phaseOrigin)/fs;
    window = iq(indices(:)).*exp(-2j*pi*centre*carrierTime);
    dechirped = window.*conj(reference).*residualCorrection;
    spectrum = abs(fft(dechirped(1:samplesPerChip:end))).^2;
    [peak, peakIndex] = max(spectrum);
    symbols(symbol) = peakIndex-1;
    confidence(symbol) = peak/max(sum(spectrum), eps);
    noisePower = max(median(spectrum)/log(2), eps);
    metrics(symbol, :) = min((spectrum/noisePower).', 1e6);
end
end

function distance = circular_distance(values, reference, modulus)
delta = mod(double(values)-double(reference)+modulus/2, modulus)-modulus/2;
distance = abs(delta);
end
