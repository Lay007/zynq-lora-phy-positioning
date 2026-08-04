classdef TestMultiPacketReceiver < matlab.unittest.TestCase
    methods (Test)
        function threeSeparatedPacketsAreDecodedInOrder(testCase)
            [packet1, payload1, fs, bw] = standard_packet(11);
            [packet2, payload2] = standard_packet(12);
            [packet3, payload3] = standard_packet(13);
            gap = zeros(round(0.04*fs), 1);
            capture = [zeros(6000, 1); packet1; gap; packet2; gap; ...
                packet3; zeros(7000, 1)];
            rng(32, "twister");
            capture = capture + sqrt(1e-5/2)*( ...
                randn(size(capture))+1j*randn(size(capture)));

            result = lora_phy.receive_lora_packets(capture, fs, bw, 7, ...
                PreambleSymbols=12, SyncWord=hex2dec("12"));

            testCase.verifyEqual(result.successCount, 3);
            testCase.verifyEqual(result.packets(1).decoded.payload, payload1);
            testCase.verifyEqual(result.packets(2).decoded.payload, payload2);
            testCase.verifyEqual(result.packets(3).decoded.payload, payload3);
            testCase.verifyLessThan(result.packets(1).preambleStartIndex, ...
                result.packets(2).preambleStartIndex);
            testCase.verifyLessThan(result.packets(2).preambleStartIndex, ...
                result.packets(3).preambleStartIndex);
        end
    end
end

function [packet, payload, sampleRateHz, bandwidthHz] = standard_packet(sequence)
bandwidthHz = 125e3;
samplesPerChip = 4;
sampleRateHz = bandwidthHz*samplesPerChip;
sf = 7;
css = lora_phy.css_config(sf, samplesPerChip);
phy = lora_phy.phy_config(sf, samplesPerChip, 1);
payload = uint8([double('ZLP1'), typecast(uint32(sequence), 'uint8'), ...
    sequence+(0:19)]).';
encoded = lora_phy.encode_packet(payload, phy);
up = lora_phy.reference_chirp(css, "up");
down = lora_phy.reference_chirp(css, "down");
sync = [lora_phy.modulate_symbol(8, css); ...
    lora_phy.modulate_symbol(16, css)];
sfd = [down; down; down(1:numel(down)/4)];
packet = [repmat(up, 12, 1); sync; sfd; ...
    lora_phy.modulate(encoded.symbols, phy)];
end
