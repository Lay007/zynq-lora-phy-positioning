function decoded = decode_packet(symbols, config)
%DECODE_PACKET Decode hard CSS decisions from the packet coding layer.

symbols = double(symbols(:));
decoded = empty_result(config);
if numel(symbols) < 8
    decoded.failureReason = "fewer than eight first-block symbols";
    return;
end

headerReducedRate = config.spreadingFactor >= 7;
headerLabels = lora_phy.unmap_symbols_to_labels( ...
    symbols(1:8), config.spreadingFactor, headerReducedRate);
headerCodewords = lora_phy.diagonal_deinterleave( ...
    headerLabels, config.spreadingFactor, 4, headerReducedRate);
[firstNibbles, headerDistances] = lora_phy.hamming_decode(headerCodewords, 4);
decoded.receivedHeaderCodewords = headerCodewords;
decoded.headerDecoderDistances = headerDistances;

if config.explicitHeader
    header = lora_phy.explicit_header_decode(firstNibbles(1:5));
    decoded.header = header;
    decoded.headerValid = header.valid;
    if ~header.valid
        decoded.failureReason = "explicit-header checksum or fields invalid";
        return;
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

dataNibbleCount = 2*payloadLength + 4*payloadCrcPresent;
firstCount = config.spreadingFactor - 2*headerReducedRate;
firstDataAvailable = max(0, firstCount-headerNibbleCount);
firstDataCount = min(dataNibbleCount, firstDataAvailable);
dataNibbles = firstNibbles(headerNibbleCount+(1:firstDataCount));
remainingCount = dataNibbleCount-firstDataCount;

payloadSf = config.spreadingFactor - ...
    2*logical(config.lowDataRateOptimization);
payloadBlockCount = ceil(remainingCount/payloadSf);
requiredSymbols = 8 + payloadBlockCount*(4+codingRate);
if numel(symbols) < requiredSymbols
    decoded.failureReason = "truncated payload symbols";
    return;
end

payloadCodewords = false(payloadBlockCount*payloadSf, 4+codingRate);
payloadDistances = zeros(payloadBlockCount*payloadSf, 1);
payloadNibblesPadded = zeros(payloadBlockCount*payloadSf, 1, "uint8");
for block = 1:payloadBlockCount
    symbolRows = 8 + (block-1)*(4+codingRate) + (1:4+codingRate);
    nibbleRows = (block-1)*payloadSf + (1:payloadSf);
    labels = lora_phy.unmap_symbols_to_labels(symbols(symbolRows), ...
        config.spreadingFactor, config.lowDataRateOptimization);
    codewords = lora_phy.diagonal_deinterleave(labels, ...
        config.spreadingFactor, codingRate, config.lowDataRateOptimization);
    [nibbles, distances] = lora_phy.hamming_decode(codewords, codingRate);
    payloadCodewords(nibbleRows, :) = codewords;
    payloadDistances(nibbleRows) = distances;
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
decoded.receivedPayloadCodewords = payloadCodewords;
decoded.payloadDecoderDistances = payloadDistances;
decoded.dataNibbles = dataNibbles;
decoded.consumedSymbolCount = requiredSymbols;
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
decoded.receivedHeaderCodewords = false(0, 8);
decoded.receivedPayloadCodewords = false(0, 0);
decoded.headerDecoderDistances = zeros(0, 1);
decoded.payloadDecoderDistances = zeros(0, 1);
decoded.dataNibbles = zeros(0, 1, "uint8");
decoded.consumedSymbolCount = 0;
end
