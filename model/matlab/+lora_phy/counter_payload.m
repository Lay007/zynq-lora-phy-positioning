function payload = counter_payload(sequence, startMilliseconds, payloadLength)
%COUNTER_PAYLOAD Rebuild the deterministic payload emitted by test firmware.

arguments
    sequence (1,1) double {mustBeInteger, mustBeNonnegative}
    startMilliseconds (1,1) double {mustBeInteger, mustBeNonnegative}
    payloadLength (1,1) double {mustBeInteger, mustBeGreaterThanOrEqual(payloadLength,12), mustBeLessThanOrEqual(payloadLength,255)}
end
payload = zeros(payloadLength, 1, "uint8");
payload(1:4) = uint8('ZLP1').';
payload(5:8) = typecast(uint32(sequence), "uint8");
payload(9:12) = typecast(uint32(startMilliseconds), "uint8");
for index = 13:payloadLength
    payload(index) = uint8(mod(sequence+index-13, 256));
end
end
