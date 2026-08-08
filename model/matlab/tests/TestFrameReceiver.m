classdef TestFrameReceiver < matlab.unittest.TestCase
    methods (Test)
        function frameIsDetectedAndPayloadRecovered(testCase)
            config = lora_phy.css_config(7, 2);
            payload = [0; 3; 17; 42; 92; 127];
            [frame, info] = lora_phy.build_css_frame(payload, config);
            trueCfo = 0.0007;
            impaired = lora_phy.apply_frequency_offset(frame, trueCfo, 0.3);
            impaired = lora_phy.add_awgn(impaired, 8, 42);
            leadingSamples = 37;
            capture = [zeros(leadingSamples, 1); impaired; zeros(25, 1)];

            result = lora_phy.receive_css_frame( ...
                capture, numel(payload), config);

            testCase.verifyEqual(result.startIndex, leadingSamples + 1);
            testCase.verifyGreaterThan(result.detectionScore, 0.7);
            testCase.verifyEqual(result.frequencyOffset, trueCfo, ...
                "AbsTol", 1e-4);
            testCase.verifyEqual(result.payloadStartIndex, ...
                leadingSamples + info.preambleSamples + 1);
            testCase.verifyEqual(result.symbols, payload);
        end

        function shortCaptureIsRejected(testCase)
            config = lora_phy.css_config(7, 2);
            testCase.verifyError(@() lora_phy.detect_frame_start( ...
                zeros(100, 1), config), "lora_phy:CaptureTooShort");
        end

        function berImprovesWithSnr(testCase)
            config = lora_phy.css_config(7, 2);
            results = lora_phy.simulate_uncoded_ber( ...
                [-18; -8; 2], config, 1000, 9);

            testCase.verifyGreaterThan(results.BER(1), results.BER(2));
            testCase.verifyGreaterThan(results.BER(2), results.BER(3));
            testCase.verifyEqual(results.BER(3), 0);
            testCase.verifyEqual(results.SER(3), 0);
        end

        function uncodedBerReportsConfidenceAndDemodulator(testCase)
            config = lora_phy.css_config(5, 2);
            results = lora_phy.simulate_uncoded_ber( ...
                -4, config, 20, 11, false);

            testCase.verifyEqual(results.DemodulationMode, "single-phase");
            testCase.verifyEqual(results.SamplesPerChip, 2);
            testCase.verifyLessThanOrEqual(results.BER_Lower95, results.BER);
            testCase.verifyGreaterThanOrEqual(results.BER_Upper95, results.BER);
        end

        function wilsonIntervalBoundsZeroErrorRate(testCase)
            [lower, upper] = lora_phy.binomial_wilson_interval(0, 100);

            testCase.verifyEqual(lower, 0, "AbsTol", 1e-15);
            testCase.verifyEqual(upper, 0.0369934982069857, ...
                "AbsTol", 1e-12);
            testCase.verifyError(@() lora_phy.binomial_wilson_interval( ...
                2, 1), "lora_phy:InvalidBinomialCounts");
        end
    end
end
