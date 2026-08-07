classdef TestFractionalToa < matlab.unittest.TestCase
    methods (Test)
        function integerDelayIsExact(testCase)
            config = lora_phy.css_config(7, 2);
            reference = lora_phy.preamble_waveform(config, 4, 1);
            leadingSamples = 137;
            capture = [zeros(leadingSamples, 1); reference; zeros(80, 1)];

            result = lora_phy.estimate_fractional_toa( ...
                capture, reference, 250e3);

            testCase.verifyEqual(result.startIndex, leadingSamples+1);
            testCase.verifyEqual(result.toaSamples, leadingSamples, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual(result.peakScore, 1, "AbsTol", 1e-12);
        end

        function fractionalDelayIsRecovered(testCase)
            config = lora_phy.css_config(7, 2);
            reference = lora_phy.preamble_waveform(config, 4, 1);
            leadingSamples = 120;
            clean = [zeros(leadingSamples, 1); reference; zeros(120, 1)];
            trueFraction = 0.35;
            delayed = lora_phy.apply_channel_impairments(clean, 250e3, ...
                FractionalDelaySamples=trueFraction);

            result = lora_phy.estimate_fractional_toa(delayed, reference, ...
                250e3, CoarseStartIndex=leadingSamples+1, ...
                SearchRadiusSamples=4);

            testCase.verifyEqual(result.toaSamples, ...
                leadingSamples+trueFraction, "AbsTol", 0.1);
            testCase.verifyGreaterThan(result.peakToSidelobeDb, 1);
        end

        function seededSweepIsReproducible(testCase)
            first = lora_phy.simulate_toa_accuracy([-15; -10], ...
                TrialsPerPoint=4, SpreadingFactor=5, RandomSeed=8);
            second = lora_phy.simulate_toa_accuracy([-15; -10], ...
                TrialsPerPoint=4, SpreadingFactor=5, RandomSeed=8);

            testCase.verifyEqual(first.trials, second.trials);
            testCase.verifySize(first.summary, [2, 5]);
        end

        function shortCaptureIsRejected(testCase)
            testCase.verifyError(@() lora_phy.estimate_fractional_toa( ...
                ones(4, 1), ones(5, 1), 1e6), ...
                "lora_phy:CaptureTooShort");
        end
    end
end
