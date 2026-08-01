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
    end
end
