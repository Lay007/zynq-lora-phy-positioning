classdef TestOnAirReceiver < matlab.unittest.TestCase
    methods (Test)
        function standardFrameRoundTrips(testCase)
            [capture, payload, sampleRateHz, bandwidthHz] = synthetic_capture(false);

            result = lora_phy.receive_lora_packet(capture, sampleRateHz, ...
                bandwidthHz, 7, PreambleSymbols=12, SyncWord=hex2dec("12"));

            testCase.verifyTrue(result.success);
            testCase.verifyTrue(result.preambleValid);
            testCase.verifyTrue(result.syncValid);
            testCase.verifyEqual(result.syncBins, [8; 16]);
            testCase.verifyEqual(result.decoded.payload, payload);
            testCase.verifyTrue(result.decoded.headerValid);
            testCase.verifyTrue(result.decoded.crcValid);
        end

        function invertedIqRoundTrips(testCase)
            [capture, payload, sampleRateHz, bandwidthHz] = synthetic_capture(true);

            result = lora_phy.receive_lora_packet(capture, sampleRateHz, ...
                bandwidthHz, 7, PreambleSymbols=12, SyncWord=hex2dec("12"), ...
                IqInverted=true);

            testCase.verifyTrue(result.success);
            testCase.verifyEqual(result.decoded.payload, payload);
        end

        function sx126xLowSpreadingFactorsRoundTrip(testCase)
            for sf = 5:6
                [capture, payload, sampleRateHz, bandwidthHz] = ...
                    synthetic_capture(false, sf);
                result = lora_phy.receive_lora_packet(capture, sampleRateHz, ...
                    bandwidthHz, sf, PreambleSymbols=12, ...
                    SyncWord=hex2dec("12"));
                testCase.verifyTrue(result.success, sprintf("SF%d", sf));
                testCase.verifyEqual(result.decoded.payload, payload);
                testCase.verifyEqual(result.lowSfPaddingSymbols, 2);
            end
        end
    end
end

function [capture, payload, sampleRateHz, bandwidthHz] = synthetic_capture(inverted, sf)
if nargin < 2
    sf = 7;
end
bandwidthHz = 125e3;
samplesPerChip = 4;
sampleRateHz = bandwidthHz*samplesPerChip;
preambleSymbols = 12;
syncWord = hex2dec("12");
css = lora_phy.css_config(sf, samplesPerChip);
phy = lora_phy.phy_config(sf, samplesPerChip, 1);
payload = uint8([double('ZLP1'), 1:20]).';
encoded = lora_phy.encode_packet(payload, phy);

up = lora_phy.reference_chirp(css, "up");
down = lora_phy.reference_chirp(css, "down");
syncScale = 8;
syncSymbols = syncScale*[bitshift(syncWord, -4); bitand(syncWord, 15)];
syncWaveform = [lora_phy.modulate_symbol(syncSymbols(1), css); ...
    lora_phy.modulate_symbol(syncSymbols(2), css)];
sfd = [down; down; down(1:numel(down)/4)];
if sf < 7
    sfd = [sfd; up; up];
end
packet = [repmat(up, preambleSymbols, 1); syncWaveform; sfd; ...
    lora_phy.modulate(encoded.symbols, phy)];
if inverted
    packet = conj(packet);
end
capture = [zeros(4000, 1); packet; zeros(5000, 1)];
rng(91, "twister");
capture = capture + sqrt(1e-5/2)*(randn(size(capture))+1j*randn(size(capture)));
end
