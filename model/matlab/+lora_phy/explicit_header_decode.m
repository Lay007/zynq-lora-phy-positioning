function header = explicit_header_decode(nibbles)
%EXPLICIT_HEADER_DECODE Parse and verify five LoRa explicit-header nibbles.

nibbles = uint8(nibbles(:));
if numel(nibbles) < 5 || any(nibbles(1:5) > 15)
    error("lora_phy:InvalidHeader", "Explicit header requires five nibbles");
end
received = nibbles(1:5);
payloadLength = 16*double(received(1)) + double(received(2));
codingRate = bitshift(received(3), -1);
payloadCrc = logical(bitand(received(3), 1));

header = struct;
header.payloadLength = payloadLength;
header.codingRate = double(codingRate);
header.payloadCrc = payloadCrc;
header.validFields = codingRate >= 1 && codingRate <= 4 && received(3) <= 9;
if header.validFields
    expected = lora_phy.explicit_header_encode( ...
        payloadLength, double(codingRate), payloadCrc);
    header.checksumValid = isequal(received(4:5), expected(4:5));
else
    header.checksumValid = false;
end
header.valid = header.validFields && header.checksumValid;
header.nibbles = received;
end
