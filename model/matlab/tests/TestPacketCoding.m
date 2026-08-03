classdef TestPacketCoding < matlab.unittest.TestCase
    methods (Test)
        function whiteningMatchesKnownSequence(testCase)
            expected = uint8([255, 254, 252, 248, 240, 225, 194, 133, ...
                11, 23, 47, 94, 188, 120, 241, 227]).';
            testCase.verifyEqual(lora_phy.whitening_sequence(16), expected);
            payload = uint8((0:15).');
            testCase.verifyEqual( ...
                lora_phy.whiten_bytes(lora_phy.whiten_bytes(payload)), payload);
        end

        function hammingCodebookMatchesGoldenVector(testCase)
            expected = uint16(hex2dec(["00"; "8B"; "4E"; "C5"; ...
                "2D"; "A6"; "63"; "E8"; "17"; "9C"; "59"; "D2"; ...
                "3A"; "B1"; "74"; "FF"]));
            codewords = lora_phy.hamming_encode(uint8((0:15).'), 4);
            testCase.verifyEqual(lora_phy.bits_to_integers(codewords), expected);
        end

        function crFourCorrectsEverySingleBit(testCase)
            nibbles = uint8((0:15).');
            clean = lora_phy.hamming_encode(nibbles, 4);
            for bit = 1:8
                corrupted = clean;
                corrupted(:, bit) = ~corrupted(:, bit);
                recovered = lora_phy.hamming_decode(corrupted, 4);
                testCase.verifyEqual(recovered, nibbles);
            end
        end

        function interleaverAndGrayMappingRoundTrip(testCase)
            for codingRate = 1:4
                normalWords = lora_phy.hamming_encode( ...
                    uint8((0:6).'), codingRate);
                normalLabels = lora_phy.diagonal_interleave(normalWords, 7, false);
                normalSymbols = lora_phy.map_labels_to_symbols(normalLabels, 7);
                normalRecoveredLabels = lora_phy.unmap_symbols_to_labels( ...
                    normalSymbols, 7, false);
                normalRecovered = lora_phy.diagonal_deinterleave( ...
                    normalRecoveredLabels, 7, codingRate, false);
                testCase.verifyEqual(normalRecovered, normalWords);
            end

            reducedWords = lora_phy.hamming_encode(uint8((0:4).'), 4);
            reducedLabels = lora_phy.diagonal_interleave(reducedWords, 7, true);
            reducedSymbols = lora_phy.map_labels_to_symbols(reducedLabels, 7);
            reducedCore = lora_phy.unmap_symbols_to_labels(reducedSymbols, 7, true);
            reducedRecovered = lora_phy.diagonal_deinterleave( ...
                reducedCore, 7, 4, true);
            testCase.verifyEqual(reducedRecovered, reducedWords);
        end

        function headerAndPayloadCrcMatchGoldenVectors(testCase)
            testCase.verifyEqual( ...
                lora_phy.explicit_header_encode(16, 1, true), ...
                uint8([1; 0; 3; 1; 13]));
            testCase.verifyEqual( ...
                lora_phy.payload_crc(uint8((0:15).')), uint16(hex2dec("DFAE")));
            testCase.verifyNotEqual( ...
                lora_phy.payload_crc(uint8((1:16).')), uint16(hex2dec("DFAE")));
        end

        function fullPacketMatchesGoldenSymbols(testCase)
            config = lora_phy.phy_config(7, 2, 1);
            encoded = lora_phy.encode_packet(uint8((0:15).'), config);
            expected = [89, 13, 29, 13, 113, 29, 97, 41, 75, 86, 75, ...
                86, 7, 7, 116, 86, 109, 99, 72, 116, 25, 61, 19, 92, ...
                80, 111, 4, 10, 126, 87, 91, 86, 127, 2, 1, 64, 32, 16].';
            testCase.verifyEqual(encoded.symbols, expected);
        end

        function completePacketRoundTripsForEveryCodingRate(testCase)
            payload = uint8([0; 1; 2; 3; 16; 32; 127; 128; 254; 255]);
            for codingRate = 1:4
                config = lora_phy.phy_config(7, 2, codingRate);
                encoded = lora_phy.encode_packet(payload, config);
                waveform = lora_phy.modulate(encoded.symbols, config);
                detected = lora_phy.demodulate(waveform, config);
                decoded = lora_phy.decode_packet(detected, config);
                testCase.verifyTrue(decoded.headerValid);
                testCase.verifyTrue(decoded.crcValid);
                testCase.verifyEqual(decoded.payload, payload);
            end
        end

        function codedBerReportsRawDenominators(testCase)
            config = lora_phy.phy_config(7, 1, 4);
            result = lora_phy.simulate_coded_ber(-8, config, 2, 4, 31);
            testCase.verifyEqual(result.Packets, 2);
            testCase.verifyEqual(result.PayloadBits, 64);
            testCase.verifyGreaterThan(result.Symbols, 0);
            testCase.verifyGreaterThan(result.PreFecBits, 0);
        end
    end
end
