classdef TestCssModel < matlab.unittest.TestCase
    methods (Test)
        function referenceChirpHasUnitMagnitude(testCase)
            config = lora_phy.css_config(7, 2);
            upchirp = lora_phy.reference_chirp(config, "up");
            downchirp = lora_phy.reference_chirp(config, "down");

            testCase.verifySize(upchirp, [256, 1]);
            testCase.verifyEqual(abs(upchirp), ones(256, 1), ...
                "AbsTol", 1e-12);
            testCase.verifyEqual(downchirp, conj(upchirp), ...
                "AbsTol", 1e-12);
        end

        function everySf7SymbolRoundTrips(testCase)
            config = lora_phy.css_config(7, 2);
            transmitted = (0:config.symbolCount-1).';

            waveform = lora_phy.modulate(transmitted, config);
            received = lora_phy.demodulate(waveform, config);

            testCase.verifyEqual(received, transmitted);
        end

        function symbolsSurviveNoiseAndCompensatedCfo(testCase)
            config = lora_phy.css_config(7, 2);
            transmitted = [0; 3; 17; 63; 92; 127];
            trueCfo = 0.00125;
            waveform = lora_phy.modulate(transmitted, config);
            impaired = lora_phy.apply_frequency_offset(waveform, trueCfo);
            impaired = lora_phy.add_awgn(impaired, 10, 42);

            firstSymbol = impaired(1:config.samplesPerSymbol);
            estimatedCfo = lora_phy.estimate_frequency_offset( ...
                firstSymbol, config, 0);
            received = lora_phy.demodulate(impaired, config, estimatedCfo);

            testCase.verifyEqual(estimatedCfo, trueCfo, "AbsTol", 1e-4);
            testCase.verifyEqual(received, transmitted);
        end

        function invalidConfigurationIsRejected(testCase)
            testCase.verifyError(@() lora_phy.css_config(4, 1), ...
                "MATLAB:css_config:notGreaterEqual");
            testCase.verifyError(@() lora_phy.css_config(7, 0), ...
                "MATLAB:css_config:notGreaterEqual");
        end

        function demodulatorCombinesEveryOversamplingPhase(testCase)
            config = lora_phy.css_config(5, 8);
            expected = 19;
            waveform = lora_phy.modulate_symbol(expected, config);
            % The former receiver observed only this phase. Erasing it
            % made every nonzero symbol look like bin zero even though
            % seven complete chip-rate observations remained available.
            waveform(1:config.samplesPerChip:end) = 0;

            actual = lora_phy.demodulate_symbol(waveform, config);

            testCase.verifyEqual(actual, expected);
        end

        function everyOversampledSf5SymbolRoundTrips(testCase)
            config = lora_phy.css_config(5, 8);
            transmitted = (0:config.symbolCount-1).';

            received = lora_phy.demodulate( ...
                lora_phy.modulate(transmitted, config), config);

            testCase.verifyEqual(received, transmitted);
        end

        function polyphaseSpectrumRejectsIncompleteSymbols(testCase)
            testCase.verifyError(@() lora_phy.polyphase_spectrum( ...
                ones(17, 1), 8), "lora_phy:InvalidSampleCount");
        end

        function metricsCanReproduceLegacySinglePhaseDecision(testCase)
            config = lora_phy.css_config(5, 8);
            waveform = lora_phy.modulate_symbol(19, config);
            waveform(1:config.samplesPerChip:end) = 0;

            polyphase = lora_phy.demodulate_metrics(waveform, config);
            singlePhase = lora_phy.demodulate_metrics(waveform, config, ...
                CombineOversamplingPhases=false);

            testCase.verifyEqual(polyphase, 19);
            testCase.verifyEqual(singlePhase, 0);
        end

        function coherentMatchedFilterRoundTripsEverySymbol(testCase)
            config = lora_phy.css_config(5, 8);
            transmitted = (0:config.symbolCount-1).';

            [received, confidence, metrics] = ...
                lora_phy.matched_filter_metrics( ...
                lora_phy.modulate(transmitted, config), config);

            testCase.verifyEqual(received, transmitted);
            testCase.verifySize(confidence, [config.symbolCount, 1]);
            testCase.verifySize(metrics, ...
                [config.symbolCount, config.symbolCount]);
        end

        function matchedFilterRejectsIncompleteSymbols(testCase)
            config = lora_phy.css_config(5, 8);
            testCase.verifyError(@() lora_phy.matched_filter_metrics( ...
                ones(config.samplesPerSymbol-1, 1), config), ...
                "lora_phy:InvalidSampleCount");
        end
    end
end
