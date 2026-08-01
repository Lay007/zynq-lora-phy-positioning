function crc = payload_crc(payload)
%PAYLOAD_CRC Compute the reverse-engineered LoRa PHY payload CRC-16.
% Polynomial 0x1021, initial state 0. The final two payload bytes are mixed
% into the high and low CRC bytes as used by Semtech-compatible PHYs.

payload = uint8(payload(:));
crc = uint16(0);
protectedCount = max(0, numel(payload)-2);

for byteIndex = 1:protectedCount
    value = payload(byteIndex);
    for bitIndex = 1:8
        feedback = xor(logical(bitget(crc, 16)), ...
            logical(bitget(value, 9-bitIndex)));
        crc = bitshift(crc, 1);
        if feedback
            crc = bitxor(crc, uint16(hex2dec("1021")));
        end
    end
end

if numel(payload) >= 2
    crc = bitxor(crc, bitshift(uint16(payload(end-1)), 8));
end
if ~isempty(payload)
    crc = bitxor(crc, uint16(payload(end)));
end
end
