classdef TestJointTimingCfo < matlab.unittest.TestCase
    %TESTJOINTTIMINGCFO Separating whole-chip timing from carrier offset.

    methods (Test)
        function pureCarrierOffsetProducesNoTimingCorrection(testCase)
            config = lora_phy.css_config(7, 8);
            % Both dechirped peaks move the same way under carrier offset.
            estimate = lora_phy.joint_timing_cfo_from_bins(3, 3, config);

            testCase.verifyEqual(estimate.cfoBins, 3);
            testCase.verifyEqual(estimate.timingChips, 0);
            testCase.verifyEqual(estimate.correctionSamples, 0);
            testCase.verifyFalse(estimate.rejected);
        end

        function pureTimingOffsetProducesNoCarrierOffset(testCase)
            config = lora_phy.css_config(7, 8);
            % The downchirp peak moves the opposite way under timing error.
            estimate = lora_phy.joint_timing_cfo_from_bins( ...
                2, config.symbolCount-2, config);

            testCase.verifyEqual(estimate.cfoBins, 0);
            testCase.verifyEqual(estimate.timingChips, 2);
            testCase.verifyEqual(estimate.correctionSamples, -16);
            testCase.verifyFalse(estimate.rejected);
        end

        function halfChipTimingRoundsAwayFromZero(testCase)
            % At L=1 the half-chip term survives and must round like round().
            config = lora_phy.css_config(7, 1);
            estimate = lora_phy.joint_timing_cfo_from_bins( ...
                [1; config.symbolCount-1], [0; 0], config);

            testCase.verifyEqual(estimate.timingHalfChips, [1; -1]);
            testCase.verifyEqual(estimate.correctionSamples, [-1; 1]);
        end

        function rejectionGuardIsUnreachableForInRangeBins(testCase)
            % The plausibility guard is defensive only. Signed bins live in
            % [-N/2, N/2), so |timingChips| <= (N-1)/2 and the correction
            % cannot exceed (N-1)*L/2, which is always below the
            % M/2 + L = N*L/2 + L limit. Proving this matters because the
            % Simulink DUT carries the same branch and its timingRejected
            % output is therefore expected to stay false.
            for configuration = [5, 1; 7, 8; 9, 2; 12, 1].'
                config = lora_phy.css_config(configuration(1), ...
                    configuration(2));
                n = config.symbolCount;
                limit = config.samplesPerSymbol/2+config.samplesPerChip;
                worstCorrection = (n-1)*config.samplesPerChip/2;
                testCase.verifyLessThanOrEqual(worstCorrection, limit);

                extremes = [0; 1; n/2-1; n/2; n/2+1; n-1];
                [upGrid, downGrid] = ndgrid(extremes, extremes);
                estimate = lora_phy.joint_timing_cfo_from_bins( ...
                    upGrid(:), downGrid(:), config);
                testCase.verifyFalse(any(estimate.rejected), ...
                    sprintf("SF%d L=%d", configuration(1), ...
                    configuration(2)));
            end
        end

        function exhaustivePairsMatchTheClosedForm(testCase)
            for samplesPerChip = [1, 8]
                config = lora_phy.css_config(7, samplesPerChip);
                n = config.symbolCount;
                [upGrid, downGrid] = ndgrid(0:n-1, 0:n-1);
                upBin = upGrid(:);
                downBin = downGrid(:);

                estimate = lora_phy.joint_timing_cfo_from_bins( ...
                    upBin, downBin, config);

                upSigned = mod(upBin+n/2, n)-n/2;
                downSigned = mod(downBin+n/2, n)-n/2;
                expectedCfo = 0.5*(upSigned+downSigned);
                expectedTiming = 0.5*(upSigned-downSigned);
                expectedCorrection = round(-expectedTiming*samplesPerChip);
                limit = config.samplesPerSymbol/2+samplesPerChip;
                expectedRejected = abs(expectedCorrection) > limit;
                expectedCorrection(expectedRejected) = 0;

                testCase.verifyEqual(estimate.cfoBins, expectedCfo);
                testCase.verifyEqual(estimate.timingChips, expectedTiming);
                testCase.verifyEqual(estimate.correctionSamples, ...
                    expectedCorrection);
                testCase.verifyEqual(estimate.rejected, expectedRejected);
            end
        end

        function halfBinUnitsAreExactIntegers(testCase)
            % The Simulink and HDL implementation relies on this: working in
            % half-bin units removes every fractional value from the DUT.
            config = lora_phy.css_config(9, 2);
            n = config.symbolCount;
            upBin = (0:n-1).';
            downBin = mod(upBin*7+3, n);

            estimate = lora_phy.joint_timing_cfo_from_bins( ...
                upBin, downBin, config);

            testCase.verifyEqual(estimate.cfoHalfBins, ...
                round(estimate.cfoHalfBins));
            testCase.verifyEqual(estimate.timingHalfChips, ...
                round(estimate.timingHalfChips));
            testCase.verifyEqual(estimate.cfoBins, estimate.cfoHalfBins/2);
            testCase.verifyEqual(estimate.timingChips, ...
                estimate.timingHalfChips/2);
        end

        function invalidBinsAreRejected(testCase)
            config = lora_phy.css_config(5, 4);
            testCase.verifyError(@() lora_phy.joint_timing_cfo_from_bins( ...
                config.symbolCount, 0, config), "lora_phy:BinOutOfRange");
            testCase.verifyError(@() lora_phy.joint_timing_cfo_from_bins( ...
                [0; 1], 0, config), "lora_phy:BinCountMismatch");
        end
    end
end
