classdef TestSoftDecoding < matlab.unittest.TestCase
    methods (Test)
        function reliabilityResolvesHardDecisionFailure(testCase)
            nibble = uint8(6);
            codeword = lora_phy.hamming_encode(nibble, 4);
            found = false;
            for first = 1:7
                for second = first+1:8
                    llrs = 5*(1-2*double(codeword));
                    llrs([first, second]) = -0.05*llrs([first, second])/5;
                    hardNibble = lora_phy.hamming_decode(llrs < 0, 4);
                    softNibble = lora_phy.hamming_decode_soft(llrs, 4);
                    if hardNibble ~= nibble && softNibble == nibble
                        found = true;
                        break
                    end
                end
                if found
                    break
                end
            end
            testCase.verifyTrue(found, ...
                "Expected soft reliability to resolve a two-bit hard error");
        end

        function softDeinterleaverPreservesCodewordSigns(testCase)
            sf = 7;
            cr = 3;
            codewords = lora_phy.hamming_encode(uint8((0:6).'), cr);
            labels = lora_phy.diagonal_interleave(codewords, sf, false);
            symbols = lora_phy.map_labels_to_symbols(labels, sf);
            metrics = zeros(numel(symbols), 2^sf);
            for row = 1:numel(symbols)
                metrics(row, symbols(row)+1) = 20;
            end
            labelLlrs = lora_phy.soft_symbol_to_label_llrs(metrics, sf, false);
            recoveredLlrs = lora_phy.diagonal_deinterleave_soft( ...
                labelLlrs, sf, cr, false);
            testCase.verifyEqual(recoveredLlrs < 0, codewords);
        end

        function noiselessPacketMetricsRoundTrip(testCase)
            config = lora_phy.phy_config(7, 2, 2);
            payload = uint8([double('SOFT'), 0:31]).';
            encoded = lora_phy.encode_packet(payload, config);
            metrics = zeros(numel(encoded.symbols), 2^config.spreadingFactor);
            for row = 1:numel(encoded.symbols)
                metrics(row, encoded.symbols(row)+1) = 50;
            end

            decoded = lora_phy.decode_packet_soft(metrics, config);

            testCase.verifyTrue(decoded.success);
            testCase.verifyEqual(decoded.payload, payload);
            testCase.verifyGreaterThan(min(decoded.headerDecoderMargins), 0);
            testCase.verifyGreaterThan(min(decoded.payloadDecoderMargins), 0);
        end
    end
end
