function results = simulate_coded_ber(snrDb, config, packetsPerPoint, ...
    payloadLength, randomSeed, softDecoding, combineOversamplingPhases)
%SIMULATE_CODED_BER Measure hard/soft packet PHY performance in AWGN.
% Timing is known. Each failed header/CRC packet contributes all of its user
% bits to the conservative payload-error count. Optional arguments six and
% seven enable soft-preferred selection and polyphase combining respectively.

if nargin < 3
    packetsPerPoint = 100;
end
if nargin < 4
    payloadLength = 16;
end
if nargin < 5
    randomSeed = 19;
end
if nargin < 6
    softDecoding = false;
end
if nargin < 7
    combineOversamplingPhases = true;
end
snrDb = double(snrDb(:));
validateattributes(packetsPerPoint, {'numeric'}, ...
    {"scalar", "integer", ">=", 1});
validateattributes(payloadLength, {'numeric'}, ...
    {"scalar", "integer", ">=", 1, "<=", 255});
if ~isscalar(softDecoding) || ~ismember(softDecoding, [0, 1]) || ...
        ~isscalar(combineOversamplingPhases) || ...
        ~ismember(combineOversamplingPhases, [0, 1])
    error("lora_phy:InvalidBerOption", ...
        "softDecoding and combineOversamplingPhases must be scalar booleans");
end

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
hardPayloadBitErrors = zeros(pointCount, 1);
softPayloadBitErrors = zeros(pointCount, 1);
hardPacketErrors = zeros(pointCount, 1);
softPacketErrors = zeros(pointCount, 1);
hardSuccessPackets = zeros(pointCount, 1);
softSuccessPackets = zeros(pointCount, 1);
softRecoveredPackets = zeros(pointCount, 1);
undetectedErrors = zeros(pointCount, 1);
payloadBits = packetsPerPoint*payloadLength*8*ones(pointCount, 1);

for point = 1:pointCount
    for packet = 1:packetsPerPoint
        payload = uint8(randi([0, 255], payloadLength, 1));
        encoded = lora_phy.encode_packet(payload, config);
        waveform = lora_phy.modulate(encoded.symbols, config);
        noisy = lora_phy.add_awgn(waveform, snrDb(point));
        [detectedSymbols, ~, metrics] = lora_phy.demodulate_metrics( ...
            noisy, config, CombineOversamplingPhases= ...
            logical(combineOversamplingPhases));
        hardDecoded = lora_phy.decode_packet(detectedSymbols, config);
        softDecoded = lora_phy.decode_packet_soft(metrics, config);
        decoded = hardDecoded;
        if softDecoding && (softDecoded.success || ...
                (~hardDecoded.success && (softDecoded.headerValid || ...
                ~hardDecoded.headerValid)))
            decoded = softDecoded;
        end

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

        hardCorrect = hardDecoded.success && ...
            isequal(hardDecoded.payload, payload);
        softCorrect = softDecoded.success && ...
            isequal(softDecoded.payload, payload);
        packetCorrect = decoded.success && isequal(decoded.payload, payload);
        hardSuccessPackets(point) = hardSuccessPackets(point)+hardCorrect;
        softSuccessPackets(point) = softSuccessPackets(point)+softCorrect;
        softRecoveredPackets(point) = softRecoveredPackets(point)+ ...
            (~hardCorrect && softCorrect);
        hardPacketErrors(point) = hardPacketErrors(point)+~hardCorrect;
        softPacketErrors(point) = softPacketErrors(point)+~softCorrect;
        hardPayloadBitErrors(point) = hardPayloadBitErrors(point)+ ...
            decoded_payload_bit_errors(hardDecoded, payload, payloadLength);
        softPayloadBitErrors(point) = softPayloadBitErrors(point)+ ...
            decoded_payload_bit_errors(softDecoded, payload, payloadLength);
        if ~packetCorrect
            packetErrors(point) = packetErrors(point) + 1;
        end
        if ~decoded.headerValid
            headerFailures(point) = headerFailures(point) + 1;
        elseif config.payloadCrc && ~decoded.crcValid
            crcFailures(point) = crcFailures(point) + 1;
        end
        payloadBitErrors(point) = payloadBitErrors(point)+ ...
            decoded_payload_bit_errors(decoded, payload, payloadLength);
        if decoded.headerValid && decoded.crcValid && ~packetCorrect
            undetectedErrors(point) = undetectedErrors(point)+1;
        end
    end
end

results = table;
results.SNR_dB = snrDb;
results.SpreadingFactor = repmat(config.spreadingFactor, pointCount, 1);
results.SamplesPerChip = repmat(config.samplesPerChip, pointCount, 1);
results.CodingRate = repmat(config.codingRate, pointCount, 1);
results.Packets = repmat(packetsPerPoint, pointCount, 1);
results.PayloadBytes = repmat(payloadLength, pointCount, 1);
results.SymbolErrors = symbolErrors;
results.Symbols = symbolTrials;
results.PreFecBitErrors = preFecBitErrors;
results.PreFecBits = preFecBits;
results.PayloadBitErrors = payloadBitErrors;
results.HardPayloadBitErrors = hardPayloadBitErrors;
results.SoftPayloadBitErrors = softPayloadBitErrors;
results.PayloadBits = payloadBits;
results.PacketErrors = packetErrors;
results.HardPacketErrors = hardPacketErrors;
results.SoftPacketErrors = softPacketErrors;
results.HardSuccessPackets = hardSuccessPackets;
results.SoftSuccessPackets = softSuccessPackets;
results.SoftRecoveredPackets = softRecoveredPackets;
results.HeaderFailures = headerFailures;
results.CrcFailures = crcFailures;
results.UndetectedErrors = undetectedErrors;
results.SER = symbolErrors./symbolTrials;
results.PreFecBER = preFecBitErrors./preFecBits;
results.PayloadBER = payloadBitErrors./payloadBits;
results.HardPayloadBER = hardPayloadBitErrors./payloadBits;
results.SoftPayloadBER = softPayloadBitErrors./payloadBits;
results.PER = packetErrors/packetsPerPoint;
results.HardPER = hardPacketErrors/packetsPerPoint;
results.SoftPER = softPacketErrors/packetsPerPoint;
results.SoftRecoveryRate = softRecoveredPackets/packetsPerPoint;
[results.PreFecBER_Lower95, results.PreFecBER_Upper95] = ...
    lora_phy.binomial_wilson_interval(preFecBitErrors, preFecBits);
[results.PayloadBER_Lower95, results.PayloadBER_Upper95] = ...
    lora_phy.binomial_wilson_interval(payloadBitErrors, payloadBits);
[results.HardPayloadBER_Lower95, results.HardPayloadBER_Upper95] = ...
    lora_phy.binomial_wilson_interval(hardPayloadBitErrors, payloadBits);
[results.SoftPayloadBER_Lower95, results.SoftPayloadBER_Upper95] = ...
    lora_phy.binomial_wilson_interval(softPayloadBitErrors, payloadBits);
[results.PER_Lower95, results.PER_Upper95] = ...
    lora_phy.binomial_wilson_interval(packetErrors, results.Packets);
[results.HardPER_Lower95, results.HardPER_Upper95] = ...
    lora_phy.binomial_wilson_interval(hardPacketErrors, results.Packets);
[results.SoftPER_Lower95, results.SoftPER_Upper95] = ...
    lora_phy.binomial_wilson_interval(softPacketErrors, results.Packets);
mode = "single-phase";
if combineOversamplingPhases
    mode = "polyphase";
end
results.DemodulationMode = repmat(mode, pointCount, 1);
decoder = "hard";
if softDecoding
    decoder = "soft-preferred";
end
results.SelectedDecoder = repmat(decoder, pointCount, 1);
probe = lora_phy.encode_packet(zeros(payloadLength, 1, "uint8"), config);
packetSamples = numel(probe.symbols)*config.samplesPerSymbol;
results.EbN0_dB = results.SNR_dB+ ...
    10*log10(packetSamples/(payloadLength*8));
end

function codewords = recover_header_codewords(symbols, config)
labels = lora_phy.unmap_symbols_to_labels( ...
    symbols(1:8), config.spreadingFactor, ...
    config.spreadingFactor >= 7);
codewords = lora_phy.diagonal_deinterleave( ...
    labels, config.spreadingFactor, 4, config.spreadingFactor >= 7);
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

function count = decoded_payload_bit_errors(decoded, payload, payloadLength)
if numel(decoded.payload) == payloadLength
    count = sum(byte_bit_errors(decoded.payload, payload));
else
    count = payloadLength*8;
end
end
