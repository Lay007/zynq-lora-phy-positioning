function results = simulate_coded_ber(snrDb, config, packetsPerPoint, payloadLength, randomSeed)
%SIMULATE_CODED_BER Measure hard-decision packet PHY performance in AWGN.
% Timing is known. Each failed header/CRC packet contributes all of its user
% bits to the conservative payload-error count used by this experiment.

if nargin < 3
    packetsPerPoint = 100;
end
if nargin < 4
    payloadLength = 16;
end
if nargin < 5
    randomSeed = 19;
end
snrDb = double(snrDb(:));
validateattributes(packetsPerPoint, {'numeric'}, ...
    {"scalar", "integer", ">=", 1});
validateattributes(payloadLength, {'numeric'}, ...
    {"scalar", "integer", ">=", 1, "<=", 255});

previousState = rng;
restoreState = onCleanup(@() rng(previousState));
rng(randomSeed, "twister");

pointCount = numel(snrDb);
packetErrors = zeros(pointCount, 1);
headerFailures = zeros(pointCount, 1);
crcFailures = zeros(pointCount, 1);
symbolErrors = zeros(pointCount, 1);
symbolTrials = zeros(pointCount, 1);
preFecBitErrors = zeros(pointCount, 1);
preFecBits = zeros(pointCount, 1);
payloadBitErrors = zeros(pointCount, 1);
payloadBits = packetsPerPoint*payloadLength*8*ones(pointCount, 1);

for point = 1:pointCount
    for packet = 1:packetsPerPoint
        payload = uint8(randi([0, 255], payloadLength, 1));
        encoded = lora_phy.encode_packet(payload, config);
        waveform = lora_phy.modulate(encoded.symbols, config);
        noisy = lora_phy.add_awgn(waveform, snrDb(point));
        detectedSymbols = lora_phy.demodulate(noisy, config);
        decoded = lora_phy.decode_packet(detectedSymbols, config);

        symbolErrors(point) = symbolErrors(point) + ...
            nnz(detectedSymbols ~= encoded.symbols);
        symbolTrials(point) = symbolTrials(point) + numel(encoded.symbols);

        receivedHeaderCodewords = recover_header_codewords( ...
            detectedSymbols, config);
        receivedPayloadCodewords = recover_payload_codewords( ...
            detectedSymbols, config, size(encoded.payloadCodewords, 1));
        transmittedCodedBits = numel(encoded.headerCodewords) + ...
            numel(encoded.payloadCodewords);
        preFecBits(point) = preFecBits(point) + transmittedCodedBits;
        preFecBitErrors(point) = preFecBitErrors(point) + ...
            nnz(xor(receivedHeaderCodewords, encoded.headerCodewords)) + ...
            nnz(xor(receivedPayloadCodewords, encoded.payloadCodewords));

        packetCorrect = decoded.success && isequal(decoded.payload, payload);
        if ~packetCorrect
            packetErrors(point) = packetErrors(point) + 1;
        end
        if ~decoded.headerValid
            headerFailures(point) = headerFailures(point) + 1;
        elseif config.payloadCrc && ~decoded.crcValid
            crcFailures(point) = crcFailures(point) + 1;
        end
        if numel(decoded.payload) == payloadLength
            payloadBitErrors(point) = payloadBitErrors(point) + ...
                sum(byte_bit_errors(decoded.payload, payload));
        else
            payloadBitErrors(point) = payloadBitErrors(point) + payloadLength*8;
        end
    end
end

results = table(snrDb, repmat(packetsPerPoint, pointCount, 1), ...
    repmat(payloadLength, pointCount, 1), symbolErrors, symbolTrials, ...
    preFecBitErrors, preFecBits, payloadBitErrors, payloadBits, ...
    packetErrors, headerFailures, crcFailures, ...
    symbolErrors./symbolTrials, preFecBitErrors./preFecBits, ...
    payloadBitErrors./payloadBits, packetErrors/packetsPerPoint, ...
    'VariableNames', ["SNR_dB", "Packets", "PayloadBytes", ...
    "SymbolErrors", "Symbols", "PreFecBitErrors", "PreFecBits", ...
    "PayloadBitErrors", "PayloadBits", "PacketErrors", ...
    "HeaderFailures", "CrcFailures", "SER", "PreFecBER", ...
    "PayloadBER", "PER"]);
end

function codewords = recover_header_codewords(symbols, config)
labels = lora_phy.unmap_symbols_to_labels( ...
    symbols(1:8), config.spreadingFactor, true);
codewords = lora_phy.diagonal_deinterleave( ...
    labels, config.spreadingFactor, 4, true);
end

function codewords = recover_payload_codewords(symbols, config, rowCount)
payloadSf = config.spreadingFactor - ...
    2*logical(config.lowDataRateOptimization);
blockCount = rowCount/payloadSf;
codewords = false(rowCount, 4+config.codingRate);
for block = 1:blockCount
    symbolRows = 8 + (block-1)*(4+config.codingRate) + ...
        (1:4+config.codingRate);
    nibbleRows = (block-1)*payloadSf + (1:payloadSf);
    labels = lora_phy.unmap_symbols_to_labels(symbols(symbolRows), ...
        config.spreadingFactor, config.lowDataRateOptimization);
    codewords(nibbleRows, :) = lora_phy.diagonal_deinterleave( ...
        labels, config.spreadingFactor, config.codingRate, ...
        config.lowDataRateOptimization);
end
end

function counts = byte_bit_errors(left, right)
difference = bitxor(uint8(left(:)), uint8(right(:)));
counts = zeros(size(difference));
for bit = 1:8
    counts = counts + double(bitget(difference, bit));
end
end
