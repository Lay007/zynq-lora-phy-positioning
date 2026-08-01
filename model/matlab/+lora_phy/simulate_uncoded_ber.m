function results = simulate_uncoded_ber( ...
    snrDb, config, symbolsPerPoint, randomSeed)
%SIMULATE_UNCODED_BER Estimate uncoded CSS BER and SER in complex AWGN.
%
% BER is computed from the natural binary labels of transmitted and detected
% symbol indices. It excludes preamble detection, synchronization, whitening,
% interleaving, FEC, and CRC.

if nargin < 3
    symbolsPerPoint = 2000;
end
if nargin < 4
    randomSeed = 1;
end

snrDb = snrDb(:);
validateattributes(symbolsPerPoint, {'numeric'}, ...
    {'scalar', 'integer', '>=', 1}, mfilename, 'symbolsPerPoint');
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
    received = lora_phy.demodulate(receivedWaveform, config);
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
end
