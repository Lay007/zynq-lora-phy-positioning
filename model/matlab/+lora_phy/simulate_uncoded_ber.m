function results = simulate_uncoded_ber( ...
    snrDb, config, symbolsPerPoint, randomSeed, combineOversamplingPhases)
%SIMULATE_UNCODED_BER Estimate uncoded CSS BER and SER in complex AWGN.
%
% BER is computed from the natural binary labels of transmitted and detected
% symbol indices. It excludes preamble detection, synchronization, whitening,
% interleaving, FEC, and CRC. The fifth argument selects polyphase combining;
% false reproduces the legacy first-decimation-phase detector.

if nargin < 3
    symbolsPerPoint = 2000;
end
if nargin < 4
    randomSeed = 1;
end
if nargin < 5
    combineOversamplingPhases = true;
end

snrDb = snrDb(:);
validateattributes(symbolsPerPoint, {'numeric'}, ...
    {'scalar', 'integer', '>=', 1}, mfilename, 'symbolsPerPoint');
if ~isscalar(combineOversamplingPhases) || ...
        ~ismember(combineOversamplingPhases, [0, 1])
    error("lora_phy:InvalidBerOption", ...
        "combineOversamplingPhases must be a scalar boolean");
end
previousState = rng;
restoreState = onCleanup(@() rng(previousState));
rng(randomSeed, "twister");

pointCount = numel(snrDb);
bitErrors = zeros(pointCount, 1);
symbolErrors = zeros(pointCount, 1);
bitsPerPoint = symbolsPerPoint * config.spreadingFactor;

for point = 1:pointCount
    transmitted = randi( ...
        [0, config.symbolCount-1], symbolsPerPoint, 1);
    waveform = lora_phy.modulate(transmitted, config);
    receivedWaveform = lora_phy.add_awgn(waveform, snrDb(point));
    received = lora_phy.demodulate_metrics(receivedWaveform, config, ...
        CombineOversamplingPhases=logical(combineOversamplingPhases));
    symbolErrors(point) = nnz(received ~= transmitted);

    differences = bitxor(uint16(transmitted), uint16(received));
    for bitIndex = 1:config.spreadingFactor
        bitErrors(point) = bitErrors(point) + ...
            nnz(bitget(differences, bitIndex));
    end
end

results = table;
results.SNR_dB = snrDb;
results.BER = bitErrors / bitsPerPoint;
results.SER = symbolErrors / symbolsPerPoint;
results.BitErrors = bitErrors;
results.SymbolErrors = symbolErrors;
results.Bits = repmat(bitsPerPoint, pointCount, 1);
results.Symbols = repmat(symbolsPerPoint, pointCount, 1);
[results.BER_Lower95, results.BER_Upper95] = ...
    lora_phy.binomial_wilson_interval(results.BitErrors, results.Bits);
[results.SER_Lower95, results.SER_Upper95] = ...
    lora_phy.binomial_wilson_interval(results.SymbolErrors, results.Symbols);
results.SpreadingFactor = repmat(config.spreadingFactor, pointCount, 1);
results.SamplesPerChip = repmat(config.samplesPerChip, pointCount, 1);
mode = "single-phase";
if combineOversamplingPhases
    mode = "polyphase";
end
results.DemodulationMode = repmat(mode, pointCount, 1);
results.EsN0_dB = results.SNR_dB+10*log10(config.samplesPerSymbol);
results.EbN0_dB = results.SNR_dB+ ...
    10*log10(config.samplesPerSymbol/config.spreadingFactor);
end
