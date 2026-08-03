function encoded = encode_packet(payload, config)
%ENCODE_PACKET Encode payload bytes into LoRa-compatible CSS symbol indices.
% This is the bit-accurate packet-coding layer. Preamble and sync-word
% waveforms remain separate acquisition-model concerns.

payload = uint8(payload(:));
if numel(payload) > 255
    error("lora_phy:PayloadTooLong", "Explicit header supports at most 255 bytes");
end
validate_config(config);

whitenedPayload = lora_phy.whiten_bytes(payload);
payloadNibbles = lora_phy.bytes_to_nibbles(whitenedPayload);
if config.payloadCrc
    crc = lora_phy.payload_crc(payload);
    crcNibbles = lora_phy.crc_to_nibbles(crc);
else
    crc = uint16(0);
    crcNibbles = zeros(0, 1, "uint8");
end
dataNibbles = [payloadNibbles; crcNibbles];

if config.explicitHeader
    headerNibbles = lora_phy.explicit_header_encode( ...
        numel(payload), config.codingRate, config.payloadCrc);
else
    headerNibbles = zeros(0, 1, "uint8");
end
frameNibbles = [headerNibbles; dataNibbles];

headerReducedRate = config.spreadingFactor >= 7;
firstCount = config.spreadingFactor - 2*headerReducedRate;
firstPadded = zeros(firstCount, 1, "uint8");
firstUsed = min(firstCount, numel(frameNibbles));
firstPadded(1:firstUsed) = frameNibbles(1:firstUsed);
headerCodewords = lora_phy.hamming_encode(firstPadded, 4);
headerLabels = lora_phy.diagonal_interleave( ...
    headerCodewords, config.spreadingFactor, headerReducedRate);
headerSymbols = lora_phy.map_labels_to_symbols( ...
    headerLabels, config.spreadingFactor);

remainingNibbles = frameNibbles(firstUsed+1:end);
payloadSf = config.spreadingFactor - ...
    2*logical(config.lowDataRateOptimization);
payloadBlockCount = ceil(numel(remainingNibbles)/payloadSf);
payloadCodewords = false(payloadBlockCount*payloadSf, 4+config.codingRate);
payloadLabels = zeros(payloadBlockCount*(4+config.codingRate), 1, "uint16");
payloadSymbols = zeros(size(payloadLabels));
payloadPaddedNibbles = zeros(payloadBlockCount*payloadSf, 1, "uint8");
payloadPaddedNibbles(1:numel(remainingNibbles)) = remainingNibbles;

for block = 1:payloadBlockCount
    nibbleRows = (block-1)*payloadSf + (1:payloadSf);
    symbolRows = (block-1)*(4+config.codingRate) + (1:4+config.codingRate);
    codewords = lora_phy.hamming_encode( ...
        payloadPaddedNibbles(nibbleRows), config.codingRate);
    labels = lora_phy.diagonal_interleave(codewords, ...
        config.spreadingFactor, config.lowDataRateOptimization);
    payloadCodewords(nibbleRows, :) = codewords;
    payloadLabels(symbolRows) = labels;
    payloadSymbols(symbolRows) = uint16(lora_phy.map_labels_to_symbols( ...
        labels, config.spreadingFactor));
end

encoded = struct;
encoded.config = config;
encoded.payload = payload;
encoded.whiteningSequence = lora_phy.whitening_sequence(numel(payload));
encoded.whitenedPayload = whitenedPayload;
encoded.payloadCrc = crc;
encoded.headerNibbles = headerNibbles;
encoded.payloadNibbles = payloadNibbles;
encoded.crcNibbles = crcNibbles;
encoded.frameNibbles = frameNibbles;
encoded.headerPaddedNibbles = firstPadded;
encoded.payloadPaddedNibbles = payloadPaddedNibbles;
encoded.headerCodewords = headerCodewords;
encoded.payloadCodewords = payloadCodewords;
encoded.headerInterleavedLabels = headerLabels;
encoded.payloadInterleavedLabels = payloadLabels;
encoded.symbols = double([uint16(headerSymbols); payloadSymbols]);
encoded.headerSymbolCount = numel(headerSymbols);
encoded.payloadSymbolCount = numel(payloadSymbols);
end

function validate_config(config)
required = ["spreadingFactor", "codingRate", "payloadCrc", ...
    "explicitHeader", "lowDataRateOptimization"];
for field = required
    if ~isfield(config, field)
        error("lora_phy:MissingConfig", "Missing config field: %s", field);
    end
end
validateattributes(config.spreadingFactor, {'numeric'}, ...
    {"scalar", "integer", ">=", 5, "<=", 12});
validateattributes(config.codingRate, {'numeric'}, ...
    {"scalar", "integer", ">=", 1, "<=", 4});
end
