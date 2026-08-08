classdef TestSymbolWindowExport < matlab.unittest.TestCase
    %TESTSYMBOLWINDOWEXPORT Corrected symbol windows exposed to Simulink/HDL.

    methods (Test)
        function windowsAreEmptyUnlessRequested(testCase)
            [iq, truth] = TestSymbolWindowExport.buildPacket;
            result = lora_phy.receive_lora_packet(iq, truth.sampleRateHz, ...
                truth.bandwidthHz, truth.spreadingFactor, ...
                PreambleSymbols=truth.preambleSymbols);

            testCase.verifyTrue(result.success);
            testCase.verifyEmpty(result.symbolWindows);
            testCase.verifyEmpty(result.correlationReference);
            testCase.verifyEmpty(result.nominalReference);
        end

        function windowsReproduceReceiverDecisions(testCase)
            [iq, truth] = TestSymbolWindowExport.buildPacket;
            result = lora_phy.receive_lora_packet(iq, truth.sampleRateHz, ...
                truth.bandwidthHz, truth.spreadingFactor, ...
                PreambleSymbols=truth.preambleSymbols, ...
                ReturnSymbolWindows=true);

            testCase.verifyTrue(result.success);
            testCase.verifyEqual(result.demodulationMode, "fft-correlator");

            config = lora_phy.css_config(truth.spreadingFactor, ...
                truth.samplesPerChip);
            testCase.verifySize(result.symbolWindows, ...
                [config.samplesPerSymbol, numel(result.symbols)]);

            % Feeding the exported windows back through the correlator with
            % the receiver's own reference must return the receiver's own
            % symbols. This is what makes the windows usable as a Simulink
            % and HDL stimulus.
            replayed = lora_phy.fft_correlator_metrics( ...
                result.symbolWindows(:), config, ...
                Reference=result.correlationReference);
            testCase.verifyEqual(replayed, result.symbols);
        end

        function windowsSurviveTheMultiPacketReceiver(testCase)
            [iq, truth] = TestSymbolWindowExport.buildPacket;
            result = lora_phy.receive_lora_packets(iq, ...
                truth.sampleRateHz, truth.bandwidthHz, ...
                truth.spreadingFactor, ...
                PreambleSymbols=truth.preambleSymbols, ...
                ReturnSymbolWindows=true);

            testCase.verifyGreaterThanOrEqual(numel(result.packets), 1);
            packet = result.packets(1);
            config = lora_phy.css_config(truth.spreadingFactor, ...
                truth.samplesPerChip);
            testCase.verifySize(packet.symbolWindows, ...
                [config.samplesPerSymbol, numel(packet.symbols)]);
            testCase.verifySize(packet.nominalReference, ...
                [config.samplesPerSymbol, 1]);
            testCase.verifyEqual(packet.nominalReference, ...
                lora_phy.reference_chirp(config));
        end
    end

    methods (Static)
        function [iq, truth] = buildPacket
            truth = struct;
            truth.spreadingFactor = 7;
            truth.samplesPerChip = 4;
            truth.bandwidthHz = 125e3;
            truth.sampleRateHz = truth.bandwidthHz*truth.samplesPerChip;
            truth.preambleSymbols = 12;
            truth.payload = uint8((1:12).');

            config = lora_phy.phy_config(truth.spreadingFactor, ...
                truth.samplesPerChip, 1);
            packet = lora_phy.build_lora_packet(truth.payload, config, ...
                PreambleSymbols=truth.preambleSymbols);
            iq = [complex(zeros(4000, 1)); packet; complex(zeros(5000, 1))];
            iq = lora_phy.add_awgn(iq, 20, 4242);
        end
    end
end
