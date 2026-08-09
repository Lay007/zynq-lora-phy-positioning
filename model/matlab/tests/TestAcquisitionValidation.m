classdef TestAcquisitionValidation < matlab.unittest.TestCase
    %TESTACQUISITIONVALIDATION Preamble and sync-word acceptance on bins.

    methods (Test)
        function idealAcquisitionIsAccepted(testCase)
            config = lora_phy.css_config(7, 8);
            syncWord = hex2dec("12");

            result = lora_phy.validate_acquisition_bins( ...
                zeros(8, 1), [8; 16], syncWord, config);

            testCase.verifyEqual(result.expectedSyncBins, [8; 16]);
            testCase.verifyTrue(result.preambleValid);
            testCase.verifyTrue(result.syncValid);
            testCase.verifyTrue(result.valid);
        end

        function syncScaleIsEightForEverySpreadingFactor(testCase)
            % The scale is a fixed 8, not 2^(SF-4). Pin it so the constant
            % cannot drift into an SF-dependent expression.
            for spreadingFactor = 7:12
                config = lora_phy.css_config(spreadingFactor, 1);
                result = lora_phy.validate_acquisition_bins(0, [8; 16], ...
                    hex2dec("12"), config);
                testCase.verifyEqual(result.expectedSyncBins, [8; 16], ...
                    sprintf("SF%d", spreadingFactor));
            end
        end

        function oneBinOfDriftIsToleratedAndTwoIsNot(testCase)
            config = lora_phy.css_config(7, 8);
            syncWord = hex2dec("12");

            tolerated = lora_phy.validate_acquisition_bins( ...
                [0; 1; 127; 0], [9; 15], syncWord, config);
            testCase.verifyTrue(tolerated.valid);

            preambleOff = lora_phy.validate_acquisition_bins( ...
                [0; 2; 0; 0], [8; 16], syncWord, config);
            testCase.verifyFalse(preambleOff.preambleValid);
            testCase.verifyTrue(preambleOff.syncValid);

            syncOff = lora_phy.validate_acquisition_bins( ...
                zeros(4, 1), [8; 18], syncWord, config);
            testCase.verifyTrue(syncOff.preambleValid);
            testCase.verifyFalse(syncOff.syncValid);
        end

        function distanceWrapsAroundTheSpectrum(testCase)
            % Bin N-1 is one away from bin 0, not N-1 away.
            config = lora_phy.css_config(5, 4);
            n = config.symbolCount;

            result = lora_phy.validate_acquisition_bins( ...
                [n-1; 0; 1], [8; 16], hex2dec("12"), config);

            testCase.verifyEqual(result.preambleDistances, [1; 0; 1]);
            testCase.verifyTrue(result.preambleValid);
        end

        function toleranceIsConfigurable(testCase)
            config = lora_phy.css_config(7, 8);
            bins = [0; 3; 0];

            strict = lora_phy.validate_acquisition_bins(bins, [8; 16], ...
                hex2dec("12"), config);
            loose = lora_phy.validate_acquisition_bins(bins, [8; 16], ...
                hex2dec("12"), config, BinTolerance=3);

            testCase.verifyFalse(strict.preambleValid);
            testCase.verifyTrue(loose.preambleValid);
            testCase.verifyEqual(loose.binTolerance, 3);
        end

        function everySyncWordMapsToDistinctBinPairs(testCase)
            % Exhaustive over the whole byte: the mapping must be a
            % function of the nibbles and must stay inside the spectrum.
            config = lora_phy.css_config(7, 8);
            n = config.symbolCount;
            for syncWord = 0:255
                result = lora_phy.validate_acquisition_bins(0, ...
                    [0; 0], syncWord, config);
                expected = 8*[floor(syncWord/16); mod(syncWord, 16)];
                testCase.verifyEqual(result.expectedSyncBins, expected);
                testCase.verifyLessThan(max(result.expectedSyncBins), n);
            end
        end

        function invalidInputsAreRejected(testCase)
            config = lora_phy.css_config(5, 4);
            testCase.verifyError(@() lora_phy.validate_acquisition_bins( ...
                0, [0; 0; 0], 18, config), "lora_phy:InvalidSyncBinCount");
            testCase.verifyError(@() lora_phy.validate_acquisition_bins( ...
                0, [0; 0], 256, config), "lora_phy:InvalidSyncWord");
            testCase.verifyError(@() lora_phy.validate_acquisition_bins( ...
                config.symbolCount, [0; 0], 18, config), ...
                "lora_phy:BinOutOfRange");
        end
    end
end
