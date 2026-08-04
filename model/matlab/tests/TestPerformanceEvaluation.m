classdef TestPerformanceEvaluation < matlab.unittest.TestCase
    methods (Test)
        function counterPayloadMatchesFirmwareLayout(testCase)
            payload = lora_phy.counter_payload(7, 383435, 32);
            testCase.verifyEqual(char(payload(1:4).'), 'ZLP1');
            testCase.verifyEqual(typecast(payload(5:8), 'uint32'), uint32(7));
            testCase.verifyEqual(typecast(payload(9:12), 'uint32'), uint32(383435));
            testCase.verifyEqual(payload(13:end), uint8((7:26).'));
        end

        function missingPacketContributesToPerAndConservativeBer(testCase)
            config = lora_phy.phy_config(7, 2, 1);
            expected = {lora_phy.counter_payload(1, 100, 16); ...
                lora_phy.counter_payload(2, 200, 16)};
            encoded = lora_phy.encode_packet(expected{1}, config);
            reception = struct;
            reception.preambleStartIndex = 100;
            reception.preambleValid = true;
            reception.syncValid = true;
            reception.decoded = lora_phy.decode_packet(encoded.symbols, config);

            report = lora_phy.evaluate_packet_receptions( ...
                reception, expected, config);

            testCase.verifyEqual(report.summary.Transmissions, 2);
            testCase.verifyEqual(report.summary.PacketErrors, 1);
            testCase.verifyEqual(report.summary.PER, 0.5);
            testCase.verifyEqual(report.summary.PayloadBitErrors, 16*8);
            testCase.verifyEqual(report.summary.PayloadBits, 2*16*8);
            testCase.verifyEqual(report.summary.ComparedPayloadBER, 0);
            testCase.verifyEqual(report.summary.PreFecBER, 0);
        end
    end
end
