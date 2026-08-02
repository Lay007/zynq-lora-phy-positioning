function result = inspect_iq_capture(iq, sampleRateHz, options)
%INSPECT_IQ_CAPTURE Estimate the main parameters of the strongest CSS burst.
%
% The estimator is intended for exploratory measurements, not for calibrated
% receiver qualification. Frequencies are relative to the capture centre.

arguments
    iq (:,1) {mustBeNumeric}
    sampleRateHz (1,1) double {mustBePositive}
    options.CandidateBandwidthHz (1,:) double {mustBePositive} = ...
        [62.5e3, 125e3, 250e3, 500e3]
    options.CandidateSpreadingFactors (1,:) double = 5:12
    options.MaximumSymbols (1,1) double {mustBeInteger, mustBePositive} = 64
    options.SpectrogramFftLength (1,1) double ...
        {mustBeInteger, mustBePositive} = 1024
end

iq = double(iq(:));
if numel(iq) < 256
    error("lora_phy:CaptureTooShort", ...
        "At least 256 IQ samples are required for analysis");
end
if any(~isfinite(iq))
    error("lora_phy:InvalidCapture", ...
        "The IQ capture contains NaN or Inf values");
end

candidateBw = unique(options.CandidateBandwidthHz( ...
    options.CandidateBandwidthHz < 0.95*sampleRateHz));
candidateSf = unique(options.CandidateSpreadingFactors);
if isempty(candidateBw)
    error("lora_phy:NoValidBandwidth", ...
        "No candidate bandwidth is below the sample rate");
end
if any(candidateSf ~= fix(candidateSf) | candidateSf < 5 | candidateSf > 12)
    error("lora_phy:InvalidSpreadingFactor", ...
        "Candidate spreading factors must be integers from 5 to 12");
end

[burstStart, burstEnd, burst] = detect_strongest_burst(iq, sampleRateHz);
packet = iq(burstStart:burstEnd);
[spectrumFrequency, spectrumPowerDb, measuredBw, centreHz] = ...
    estimate_band(packet, sampleRateHz, burst.noisePower);
[~, bandwidthIndex] = min(abs(candidateBw-measuredBw));
bandwidthHz = candidateBw(bandwidthIndex);

nPacket = (0:numel(packet)-1).';
centredPacket = packet .* exp(-2j*pi*centreHz*nPacket/sampleRateHz);
[spreadingFactor, sfScores] = estimate_sf( ...
    centredPacket, sampleRateHz, bandwidthHz, candidateSf);
samplesPerSymbol = sampleRateHz * 2^spreadingFactor / bandwidthHz;

alignedStart = refine_start(iq, burstStart, burstEnd, sampleRateHz, ...
    bandwidthHz, spreadingFactor, centreHz, burst.blockLength);
[fftPowerDb, detectedSymbols, residualCfoHz] = dechirp_symbols( ...
    iq, alignedStart, burstEnd, sampleRateHz, bandwidthHz, ...
    spreadingFactor, centreHz, options.MaximumSymbols);

noisePower = max(burst.noisePower, eps);
signalPower = mean(abs(iq(alignedStart:burstEnd)).^2);
snrLinear = max(signalPower/noisePower - 1, eps);
dcOffset = mean(iq);
iPower = mean(real(packet).^2);
qPower = mean(imag(packet).^2);

result = struct;
result.packetStartIndex = burstStart;
result.packetEndIndex = burstEnd;
result.alignedStartIndex = alignedStart;
result.packetStartSeconds = (burstStart-1)/sampleRateHz;
result.packetEndSeconds = (burstEnd-1)/sampleRateHz;
result.estimatedBandwidthHz = bandwidthHz;
result.measuredOccupiedBandwidthHz = measuredBw;
result.estimatedSpreadingFactor = spreadingFactor;
result.estimatedSymbolDurationSeconds = 2^spreadingFactor/bandwidthHz;
result.estimatedCarrierOffsetHz = centreHz;
result.residualCfoHz = residualCfoHz;
result.estimatedSnrDb = 10*log10(snrLinear);
result.signalPowerDbRelative = 10*log10(max(signalPower, eps));
result.noisePowerDbRelative = 10*log10(noisePower);
result.dcOffset = dcOffset;
result.iqPowerImbalanceDb = 10*log10(max(iPower, eps)/max(qPower, eps));
result.preambleScore = max(sfScores);
result.candidateSpreadingFactors = candidateSf;
result.spreadingFactorScores = sfScores;
result.averageSpectrumFrequencyHz = spectrumFrequency;
result.averageSpectrumPowerDb = spectrumPowerDb;
result.dechirpedFftPowerDb = fftPowerDb;
result.detectedSymbols = detectedSymbols;
result.analyzedSymbolCount = numel(detectedSymbols);
result.blockTimeSeconds = burst.blockTimeSeconds;
result.blockPowerDb = burst.blockPowerDb;
result.activityThresholdDb = burst.thresholdDb;
result.spectrogram = lora_phy.compute_spectrogram(iq, sampleRateHz, ...
    options.SpectrogramFftLength, 800);
result.sampleRateHz = sampleRateHz;
result.samplesPerSymbol = samplesPerSymbol;
end

function [startIndex, endIndex, info] = detect_strongest_burst(iq, fs)
blockLength = max(32, round(fs/2000));
blockCount = floor(numel(iq)/blockLength);
if blockCount < 4
    blockLength = max(16, floor(numel(iq)/8));
    blockCount = floor(numel(iq)/blockLength);
end
trimmed = iq(1:blockCount*blockLength);
blocks = reshape(trimmed, blockLength, blockCount);
blockPower = mean(abs(blocks).^2, 1);
blockPowerDb = 10*log10(blockPower + eps);
sortedPowerDb = sort(blockPowerDb);
noiseSubset = sortedPowerDb(1:max(3, floor(0.4*numel(sortedPowerDb))));
noiseDb = median(noiseSubset);
robustSpread = median(abs(noiseSubset-noiseDb));
thresholdDb = noiseDb + max(4, 6*robustSpread);
active = blockPowerDb > thresholdDb;
inactiveEdges = diff([true, active, true]);
gapStarts = find(inactiveEdges == -1);
gapEnds = find(inactiveEdges == 1)-1;
for gap = 1:numel(gapStarts)
    if gapStarts(gap) > 1 && gapEnds(gap) < numel(active) && ...
            gapEnds(gap)-gapStarts(gap)+1 <= 2
        active(gapStarts(gap):gapEnds(gap)) = true;
    end
end

edges = diff([false, active, false]);
runStarts = find(edges == 1);
runEnds = find(edges == -1)-1;
if isempty(runStarts)
    [~, peakBlock] = max(blockPowerDb);
    runStarts = max(1, peakBlock-2);
    runEnds = min(blockCount, peakBlock+2);
end
% A run that touches a capture boundary may be only a packet fragment.  If
% at least one complete interior run exists, rank only the complete runs.
eligibleRuns = find(runStarts > 1 & runEnds < blockCount);
if isempty(eligibleRuns)
    eligibleRuns = 1:numel(runStarts);
end
scores = zeros(size(eligibleRuns));
for k = 1:numel(eligibleRuns)
    run = eligibleRuns(k);
    range = runStarts(run):runEnds(run);
    scores(k) = sum(max(blockPowerDb(range)-noiseDb, 0));
end
[~, bestEligible] = max(scores);
best = eligibleRuns(bestEligible);
firstBlock = runStarts(best);
lastBlock = runEnds(best);
startIndex = (firstBlock-1)*blockLength+1;
endIndex = min(numel(iq), lastBlock*blockLength);

quietPower = blockPower(~active);
if isempty(quietPower)
    quietPower = sort(blockPower);
    quietPower = quietPower(1:max(1, floor(numel(quietPower)/4)));
end
info = struct;
info.blockLength = blockLength;
info.noisePower = median(quietPower);
info.blockTimeSeconds = (((1:blockCount)-0.5)*blockLength/fs).';
info.blockPowerDb = blockPowerDb(:);
info.thresholdDb = thresholdDb;
end

function [frequency, powerDb, measuredBw, centreHz] = estimate_band(x, fs, noisePower)
fftLength = 2^nextpow2(min(max(2048, round(fs/100)), 16384));
windowLength = min(numel(x), fftLength);
n = (0:windowLength-1).';
window = 0.5-0.5*cos(2*pi*n/max(windowLength-1, 1));
hop = max(1, floor(windowLength/2));
starts = 1:hop:max(1, numel(x)-windowLength+1);
power = zeros(fftLength, 1);
for k = 1:numel(starts)
    segment = x(starts(k)+(0:windowLength-1)).*window;
    power = power + abs(fftshift(fft(segment, fftLength))).^2;
end
power = power/max(numel(starts), 1);
powerDb = 10*log10(power+eps);
frequency = ((-fftLength/2):(fftLength/2-1)).'*fs/fftLength;

pairPower = 0.5*(abs(x(1:end-1)).^2+abs(x(2:end)).^2);
instantFrequency = angle(x(2:end).*conj(x(1:end-1)))*fs/(2*pi);
instantFrequency = sort(instantFrequency(pairPower > 5*noisePower));
if numel(instantFrequency) < 32
    instantFrequency = sort(angle(x(2:end).*conj(x(1:end-1)))*fs/(2*pi));
end
lowIndex = max(1, round(0.02*numel(instantFrequency)));
highIndex = min(numel(instantFrequency), round(0.98*numel(instantFrequency)));
lowFrequency = instantFrequency(lowIndex);
highFrequency = instantFrequency(highIndex);
centreHz = 0.5*(lowFrequency+highFrequency);
measuredBw = max(fs/fftLength, (highFrequency-lowFrequency)/0.96);
end

function [sf, scores] = estimate_sf(x, fs, bw, candidates)
scores = zeros(size(candidates));
for k = 1:numel(candidates)
    lag = round(fs*2^candidates(k)/bw);
    usable = min(numel(x)-lag, 8*lag);
    if usable < lag
        scores(k) = 0;
        continue
    end
    a = x(1:usable);
    b = x(1+lag:lag+usable);
    scores(k) = abs(sum(b.*conj(a))) / ...
        sqrt(max(sum(abs(a).^2)*sum(abs(b).^2), eps));
end
maximum = max(scores);
eligible = find(scores >= 0.92*maximum & scores >= 0.15, 1, "first");
if isempty(eligible)
    [~, eligible] = max(scores);
end
sf = candidates(eligible);
end

function bestStart = refine_start(iq, roughStart, burstEnd, fs, bw, sf, centre, blockLength)
symbolSamples = round(fs*2^sf/bw);
searchFirst = max(1, roughStart-blockLength);
searchLast = min(burstEnd-symbolSamples+1, roughStart+blockLength);
step = max(1, round(fs/bw/2));
if searchLast < searchFirst
    bestStart = roughStart;
    return
end
modelConfig = lora_phy.css_config(sf, 4);
reference = lora_phy.reference_chirp(modelConfig, "up");
bestMetric = -inf;
bestStart = roughStart;
for candidate = searchFirst:step:searchLast
    original = iq(candidate:candidate+symbolSamples-1);
    time = (0:symbolSamples-1).';
    original = original.*exp(-2j*pi*centre*time/fs);
    symbol = resample_linear(original, modelConfig.samplesPerSymbol);
    spectrum = abs(fft(symbol.*conj(reference))).^2;
    [peak, bin] = max(spectrum);
    signedBin = bin-1;
    if signedBin > numel(spectrum)/2
        signedBin = signedBin-numel(spectrum);
    end
    concentration = peak/max(sum(spectrum), eps);
    metric = concentration/(1+abs(signedBin)/8);
    if metric > bestMetric
        bestMetric = metric;
        bestStart = candidate;
    end
end
end

function [matrixDb, symbols, residualCfo] = dechirp_symbols( ...
    iq, startIndex, endIndex, fs, bw, sf, centre, maximumSymbols)
symbolSamples = round(fs*2^sf/bw);
symbolCount = min(maximumSymbols, floor((endIndex-startIndex+1)/symbolSamples));
config = lora_phy.css_config(sf, 4);
reference = lora_phy.reference_chirp(config, "up");
dechirped = complex(zeros(config.samplesPerSymbol, symbolCount));
for k = 1:symbolCount
    indices = startIndex+(k-1)*symbolSamples+(0:symbolSamples-1);
    time = (indices(:)-startIndex)/fs;
    x = iq(indices);
    x = x(:).*exp(-2j*pi*centre*time);
    dechirped(:, k) = resample_linear(x, config.samplesPerSymbol).*conj(reference);
end
if symbolCount == 0
    matrixDb = zeros(0, config.symbolCount);
    symbols = zeros(0, 1);
    residualCfo = NaN;
    return
end
usedPreamble = min(6, symbolCount);
phaseSteps = angle(dechirped(2:end, 1:usedPreamble).* ...
    conj(dechirped(1:end-1, 1:usedPreamble)));
residualCfo = median(phaseSteps(:))*bw*config.samplesPerChip/(2*pi);
sampleTime = (0:config.samplesPerSymbol-1).'/(bw*config.samplesPerChip);
correction = exp(-2j*pi*residualCfo*sampleTime);
matrixDb = zeros(symbolCount, config.symbolCount);
symbols = zeros(symbolCount, 1);
for k = 1:symbolCount
    corrected = dechirped(:, k).*correction;
    chipRate = corrected(1:config.samplesPerChip:end);
    spectrum = abs(fft(chipRate)).^2;
    spectrumDb = 10*log10(spectrum/max(max(spectrum), eps)+eps);
    matrixDb(k, :) = spectrumDb(:).';
    [~, bin] = max(spectrum);
    symbols(k) = bin-1;
end
end

function y = resample_linear(x, outputLength)
x = x(:);
if numel(x) == outputLength
    y = x;
    return
end
inputAxis = linspace(0, 1, numel(x));
outputAxis = linspace(0, 1, outputLength);
y = interp1(inputAxis, x, outputAxis, "linear").';
end
