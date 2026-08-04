function decoded = decode_packet_soft(symbolMetrics, config)
%DECODE_PACKET_SOFT Decode a packet from per-bin max-log likelihood metrics.

symbolMetrics = double(symbolMetrics);
decoded = empty_result(config);
if size(symbolMetrics, 1) < 8
    decoded.failureReason = "fewer than eight first-block symbols";
    return
end
if size(symbolMetrics, 2) ~= 2^config.spreadingFactor
    error("lora_phy:MetricWidth", "Expected 2^SF metrics per symbol");
end
[~, hardIndices] = max(symbolMetrics, [], 2);
decoded.hardSymbols = hardIndices-1;

headerReducedRate = config.spreadingFactor >= 7;
headerLabelLlrs = lora_phy.soft_symbol_to_label_llrs( ...
    symbolMetrics(1:8, :), config.spreadingFactor, headerReducedRate);
headerCodewordLlrs = lora_phy.diagonal_deinterleave_soft( ...
    headerLabelLlrs, config.spreadingFactor, 4, headerReducedRate);
[firstNibbles, headerMargins, headerCodewords] = ...
    lora_phy.hamming_decode_soft(headerCodewordLlrs, 4);
decoded.headerCodewordLlrs = headerCodewordLlrs;
decoded.headerDecoderMargins = headerMargins;
decoded.receivedHeaderCodewords = headerCodewordLlrs < 0;
decoded.correctedHeaderCodewords = headerCodewords;

if config.explicitHeader
    header = lora_phy.explicit_header_decode(firstNibbles(1:5));
    decoded.header = header;
    decoded.headerValid = header.valid;
    if ~header.valid
        decoded.failureReason = "explicit-header checksum or fields invalid";
        return
    end
    payloadLength = header.payloadLength;
    codingRate = header.codingRate;
    payloadCrcPresent = header.payloadCrc;
    headerNibbleCount = 5;
else
    if ~isfield(config, "payloadLength") || isempty(config.payloadLength)
        error("lora_phy:MissingPayloadLength", ...
            "Implicit-header decoding requires config.payloadLength");
    end
    payloadLength = config.payloadLength;
    codingRate = config.codingRate;
    payloadCrcPresent = logical(config.payloadCrc);
    headerNibbleCount = 0;
    decoded.headerValid = true;
end

dataNibbleCount = 2*payloadLength+4*payloadCrcPresent;
firstCount = config.spreadingFactor-2*headerReducedRate;
firstDataAvailable = max(0, firstCount-headerNibbleCount);
firstDataCount = min(dataNibbleCount, firstDataAvailable);
dataNibbles = firstNibbles(headerNibbleCount+(1:firstDataCount));
remainingCount = dataNibbleCount-firstDataCount;

payloadSf = config.spreadingFactor- ...
    2*logical(config.lowDataRateOptimization);
payloadBlockCount = ceil(remainingCount/payloadSf);
requiredSymbols = 8+payloadBlockCount*(4+codingRate);
decoded.consumedSymbolCount = requiredSymbols;
if size(symbolMetrics, 1) < requiredSymbols
    decoded.failureReason = "truncated payload symbols";
    return
end

payloadCodewords = false(payloadBlockCount*payloadSf, 4+codingRate);
payloadCodewordLlrs = zeros(payloadBlockCount*payloadSf, 4+codingRate);
payloadMargins = zeros(payloadBlockCount*payloadSf, 1);
payloadNibblesPadded = zeros(payloadBlockCount*payloadSf, 1, "uint8");
for block = 1:payloadBlockCount
    symbolRows = 8+(block-1)*(4+codingRate)+(1:4+codingRate);
    nibbleRows = (block-1)*payloadSf+(1:payloadSf);
    labelLlrs = lora_phy.soft_symbol_to_label_llrs( ...
        symbolMetrics(symbolRows, :), config.spreadingFactor, ...
        config.lowDataRateOptimization);
    codewordLlrs = lora_phy.diagonal_deinterleave_soft(labelLlrs, ...
        config.spreadingFactor, codingRate, config.lowDataRateOptimization);
    [nibbles, margins, codewords] = ...
        lora_phy.hamming_decode_soft(codewordLlrs, codingRate);
    payloadCodewords(nibbleRows, :) = codewords;
    payloadCodewordLlrs(nibbleRows, :) = codewordLlrs;
    payloadMargins(nibbleRows) = margins;
    payloadNibblesPadded(nibbleRows) = nibbles;
end
dataNibbles = [dataNibbles; payloadNibblesPadded(1:remainingCount)];

whitenedNibbles = dataNibbles(1:2*payloadLength);
whitenedPayload = lora_phy.nibbles_to_bytes(whitenedNibbles);
payload = lora_phy.whiten_bytes(whitenedPayload);
if payloadCrcPresent
    receivedCrc = lora_phy.nibbles_to_crc(dataNibbles(end-3:end));
    calculatedCrc = lora_phy.payload_crc(payload);
    crcValid = receivedCrc == calculatedCrc;
else
    receivedCrc = uint16(0);
    calculatedCrc = uint16(0);
    crcValid = true;
end

decoded.payload = payload;
decoded.whitenedPayload = whitenedPayload;
decoded.receivedCrc = receivedCrc;
decoded.calculatedCrc = calculatedCrc;
decoded.crcValid = crcValid;
decoded.success = decoded.headerValid && crcValid;
decoded.failureReason = "";
if ~crcValid
    decoded.failureReason = "payload CRC invalid";
end
decoded.receivedPayloadCodewords = payloadCodewordLlrs < 0;
decoded.correctedPayloadCodewords = payloadCodewords;
decoded.payloadCodewordLlrs = payloadCodewordLlrs;
decoded.payloadDecoderMargins = payloadMargins;
decoded.dataNibbles = dataNibbles;
end

function decoded = empty_result(config)
decoded = struct;
decoded.config = config;
decoded.success = false;
decoded.headerValid = false;
decoded.crcValid = false;
decoded.failureReason = "";
decoded.payload = zeros(0, 1, "uint8");
decoded.whitenedPayload = zeros(0, 1, "uint8");
decoded.receivedCrc = uint16(0);
decoded.calculatedCrc = uint16(0);
decoded.header = struct;
decoded.hardSymbols = zeros(0, 1);
decoded.receivedHeaderCodewords = false(0, 8);
decoded.receivedPayloadCodewords = false(0, 0);
decoded.correctedHeaderCodewords = false(0, 8);
decoded.correctedPayloadCodewords = false(0, 0);
decoded.headerCodewordLlrs = zeros(0, 8);
decoded.payloadCodewordLlrs = zeros(0, 0);
decoded.headerDecoderMargins = zeros(0, 1);
decoded.payloadDecoderMargins = zeros(0, 1);
decoded.dataNibbles = zeros(0, 1, "uint8");
decoded.consumedSymbolCount = 0;
end
