classdef TestChannelImpairments < matlab.unittest.TestCase
    methods (Test)
        function defaultsLeaveWaveformUnchanged(testCase)
            samples = complex((1:16).', (-8:7).');

            [actual, diagnostics] = ...
                lora_phy.apply_channel_impairments(samples, 1e6);

            testCase.verifyEqual(actual, samples, "AbsTol", 1e-12);
            testCase.verifyEqual(diagnostics.noisePower, 0);
        end

        function fractionalAndMultipathDelaysAreApplied(testCase)
            impulse = complex(zeros(24, 1));
            impulse(6) = 1;

            actual = lora_phy.apply_channel_impairments(impulse, 1e6, ...
                FractionalDelaySamples=0.5, ...
                MultipathDelaysSamples=[0; 3], ...
                MultipathGains=[1; 0.5j]);

            expected = complex(zeros(size(impulse)));
            expected(6:7) = 0.5;
            expected(9:10) = 0.25j;
            testCase.verifyEqual(actual, expected, "AbsTol", 1e-12);
        end

        function sampleRateOffsetUsesDocumentedSign(testCase)
            ramp = (0:100).';

            actual = lora_phy.apply_channel_impairments(ramp, 1e3, ...
                SampleRateOffsetPpm=10000);

            testCase.verifyEqual(actual(51), 50.5, "AbsTol", 1e-12);
        end

        function seededNoiseIsReproducible(testCase)
            samples = exp(1j*2*pi*(0:999).'/17);

            first = lora_phy.apply_channel_impairments(samples, 1e6, ...
                SnrDb=12, RandomSeed=73);
            second = lora_phy.apply_channel_impairments(samples, 1e6, ...
                SnrDb=12, RandomSeed=73);

            testCase.verifyEqual(first, second);
            measuredSnr = 10*log10(mean(abs(samples).^2)/ ...
                mean(abs(first-samples).^2));
            testCase.verifyEqual(measuredSnr, 12, "AbsTol", 0.5);
        end

        function mismatchedPathVectorsAreRejected(testCase)
            testCase.verifyError(@() lora_phy.apply_channel_impairments( ...
                ones(8, 1), 1e6, MultipathDelaysSamples=[0; 1], ...
                MultipathGains=1), "lora_phy:PathCountMismatch");
        end
    end
end
