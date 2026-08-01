function vector = export_golden_vectors(outputPath)
%EXPORT_GOLDEN_VECTORS Write deterministic SF7/CR1 packet intermediates.

rootDirectory = fileparts(mfilename("fullpath"));
addpath(rootDirectory);
if nargin < 1
    outputPath = fullfile(rootDirectory, "golden", "lora-phy-sf7-cr1.json");
end

config = lora_phy.phy_config(7, 2, 1);
payload = uint8((0:15).');
encoded = lora_phy.encode_packet(payload, config);
vector = struct;
vector.schema = "zynq-lora-phy-golden-v1";
vector.description = "Explicit header, CRC on, SF7, CR 4/5, 2 samples/chip";
vector.payload = double(payload(:).');
vector.whiteningSequence = double(encoded.whiteningSequence(:).');
vector.whitenedPayload = double(encoded.whitenedPayload(:).');
vector.payloadCrcHex = upper(dec2hex(encoded.payloadCrc, 4));
vector.headerNibbles = double(encoded.headerNibbles(:).');
vector.payloadNibbles = double(encoded.payloadNibbles(:).');
vector.crcNibbles = double(encoded.crcNibbles(:).');
vector.headerCodewords = double(encoded.headerCodewords);
vector.payloadCodewords = double(encoded.payloadCodewords);
vector.headerInterleavedLabels = double(encoded.headerInterleavedLabels(:).');
vector.payloadInterleavedLabels = double(encoded.payloadInterleavedLabels(:).');
vector.cssSymbols = double(encoded.symbols(:).');

outputDirectory = fileparts(outputPath);
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end
file = fopen(outputPath, "w");
if file < 0
    error("lora_phy:GoldenVectorFile", "Cannot open golden-vector output");
end
cleanup = onCleanup(@() fclose(file));
fprintf(file, "%s\n", jsonencode(vector, "PrettyPrint", true));
end
