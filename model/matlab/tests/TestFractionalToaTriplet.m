classdef TestFractionalToaTriplet < matlab.unittest.TestCase
    %TESTFRACTIONALTOATRIPLET Hardware-shaped sub-sample interpolation.

    methods (Test)
        function exactTableMatchesTheFullEstimator(testCase)
            % The reduced form must agree with the estimator it is reduced
            % from, or the DUT would be verified against the wrong thing.
            [triplets, truth] = testCase.sweepPeaks();
            for k = 1:size(triplets, 1)
                result = lora_phy.fractional_toa_from_triplet( ...
                    triplets(k, :).', LogTableBits=0);
                expected = referenceOffset(triplets(k, :));
                testCase.verifyEqual(result.fractionalOffsetSamples, ...
                    expected, AbsTol=1e-12);
            end
            testCase.verifyEqual(numel(truth), size(triplets, 1));
        end

        function sixtyFourEntriesStayWithinAMetreOfTheExactLog(testCase)
            % The table size is a hardware decision, so the test pins the
            % measurement behind it rather than the number alone.
            [triplets, truth] = testCase.sweepPeaks();
            errorFor = @(bits) rms(arrayfun(@(k) ...
                lora_phy.fractional_toa_from_triplet(triplets(k, :).', ...
                    LogTableBits=bits).fractionalOffsetSamples ...
                -truth(k), (1:numel(truth)).'));

            exact = errorFor(0);
            sixtyFour = errorFor(6);

            testCase.verifyLessThan(exact, 0.01, ...
                "the exact log must reproduce the published bias");
            testCase.verifyLessThan(sixtyFour-exact, 0.002, ...
                sprintf("64 entries cost %.4f samples over exact", ...
                    sixtyFour-exact));
        end

        function smallerTablesDegradeMonotonically(testCase)
            % If a smaller table were not worse, the sizing argument would
            % be wrong somewhere.
            [triplets, truth] = testCase.sweepPeaks();
            errors = zeros(1, 3);
            sizes = [4 5 6];
            for j = 1:numel(sizes)
                offsets = arrayfun(@(k) ...
                    lora_phy.fractional_toa_from_triplet( ...
                        triplets(k, :).', ...
                        LogTableBits=sizes(j)).fractionalOffsetSamples, ...
                    (1:numel(truth)).');
                errors(j) = rms(offsets-truth);
            end
            testCase.verifyGreaterThan(errors(1), errors(2));
            testCase.verifyGreaterThan(errors(2), errors(3));
        end

        function aZeroBesideThePeakIsReportedNotSwallowed(testCase)
            % log(0) would give a NaN that looks like a measurement.
            result = lora_phy.fractional_toa_from_triplet([0; 1; 0.5]);
            testCase.verifyFalse(result.valid);
            testCase.verifyEqual(result.fractionalOffsetSamples, 0);
        end

        function aSymmetricPeakSitsExactlyOnTheSample(testCase)
            result = lora_phy.fractional_toa_from_triplet([1; 4; 1], ...
                LogTableBits=0);
            testCase.verifyTrue(result.valid);
            testCase.verifyEqual(result.fractionalOffsetSamples, 0, ...
                AbsTol=1e-12);
        end
    end

    methods (Static, Access = private)
        function [triplets, truth] = sweepPeaks()
            %SWEEPPEAKS Correlation triplets against known sub-sample delays.
            spreadingFactor = 7;
            samplesPerChip = 2;
            config = lora_phy.css_config(spreadingFactor, samplesPerChip);
            sampleRateHz = 125e3*samplesPerChip;
            reference = lora_phy.modulate(0, config);
            lead = 2*config.samplesPerSymbol;

            delays = (0.05:0.05:0.95).';
            triplets = zeros(numel(delays), 3);
            truth = zeros(numel(delays), 1);
            for k = 1:numel(delays)
                clean = [complex(zeros(lead, 1)); reference; ...
                    complex(zeros(config.samplesPerSymbol, 1))];
                delayed = lora_phy.apply_channel_impairments(clean, ...
                    sampleRateHz, FractionalDelaySamples=delays(k));
                correlation = conv(delayed, conj(flipud(reference)));
                [~, peak] = max(abs(correlation));
                triplets(k, :) = abs(correlation(peak+(-1:1))).';
                truth(k) = (lead+delays(k))-(peak-numel(reference));
            end
        end
    end
end

function offset = referenceOffset(triplet)
%REFERENCEOFFSET The estimator's own rule, written out independently.
logs = log(double(triplet(:)));
denominator = logs(1)-2*logs(2)+logs(3);
offset = 0;
if denominator ~= 0
    offset = max(-0.5, min(0.5, 0.5*(logs(1)-logs(3))/denominator));
end
end
