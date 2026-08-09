classdef TestPreambleRunDetection < matlab.unittest.TestCase
    %TESTPREAMBLERUNDETECTION Blind acquisition from a free-running correlator.
    %
    % The claim under test is that finding a packet needs no search over
    % sample offsets: because the preamble is periodic with one symbol, any
    % window lands on a bin that equals the chip offset, and consecutive
    % windows repeat it. These tests pin the bin/offset identity, the
    % CFO behaviour that motivates checking sync relative to the preamble
    % bin, and the rejection cases.

    methods (Test)
        function binEqualsChipsSinceSymbolBoundary(testCase)
            % A window starting d chips after a boundary dechirps to bin d.
            % This is the whole basis of blind detection, so check it against
            % real samples at offsets that are not multiples of the
            % oversampling factor.
            for offset = [0 137 512 999 1023]
                [bins, lead, css] = testCase.correlateStream(offset, 0, Inf);
                hit = testCase.findRun(bins, css);
                testCase.assertFalse(isnan(hit.start), ...
                    sprintf("no run detected at offset %d", offset));

                windowStart = (hit.start-1)*css.samplesPerSymbol;
                expected = mod(windowStart-lead, css.samplesPerSymbol) ...
                    /css.samplesPerChip;
                testCase.verifyEqual(hit.result.preambleBin, ...
                    round(expected), sprintf("offset %d", offset), AbsTol=1);
            end
        end

        function chipsToBoundaryIsTheComplementOfTheBin(testCase)
            config = lora_phy.css_config(7, 8);
            n = config.symbolCount;
            for preambleBin = [0 1 17 64 127]
                bins = [repmat(preambleBin, 8, 1); ...
                    mod(preambleBin+[8; 16], n)];
                result = lora_phy.detect_preamble_run(bins, ...
                    hex2dec("12"), config);
                testCase.verifyTrue(result.valid);
                testCase.verifyEqual(result.chipsSinceBoundary, preambleBin);
                testCase.verifyEqual(result.chipsToBoundary, ...
                    mod(-preambleBin, n));
                testCase.verifyEqual( ...
                    mod(result.chipsSinceBoundary+result.chipsToBoundary, n), 0);
            end
        end

        function syncTargetsFollowThePreambleBinAndWrap(testCase)
            % Sync bins are preambleBin + 8*nibble, wrapped into [0, N).
            config = lora_phy.css_config(7, 8);
            bins = [repmat(120, 8, 1); 0; 8];

            result = lora_phy.detect_preamble_run(bins, hex2dec("12"), config);

            testCase.verifyEqual(result.expectedSyncBins, [0; 8]);
            testCase.verifyTrue(result.valid);
        end

        function relativeCheckSurvivesCarrierFrequencyOffsetAndAbsoluteDoesNot(testCase)
            % CFO displaces the preamble and the sync symbols by the same
            % number of bins. That is exactly why the blind detector checks
            % sync relative to the preamble bin: the absolute checker used
            % after timing correction rejects the very same samples.
            [bins, ~, css] = testCase.correlateStream(137, 3, -5);
            hit = testCase.findRun(bins, css);
            testCase.assertFalse(isnan(hit.start), "CFO run not detected");

            run = bins(hit.start+(0:9));
            absolute = lora_phy.validate_acquisition_bins(run(1:8), ...
                run(9:10), hex2dec("12"), css);

            testCase.verifyTrue(hit.result.valid);
            testCase.verifyFalse(absolute.valid);
            testCase.verifyNotEqual(hit.result.preambleBin, 0);
        end

        function detectionHoldsAtLowSignalToNoiseRatio(testCase)
            for snr = [0 -5 -10]
                [bins, ~, css] = testCase.correlateStream(137, 0, snr);
                hit = testCase.findRun(bins, css);
                testCase.verifyFalse(isnan(hit.start), ...
                    sprintf("no run detected at %d dB", snr));
            end
        end

        function noiseOnlyStreamsAreRejected(testCase)
            % A detector that fires on noise is worse than no detector.
            % Sweep seeds so this is not one lucky draw.
            config = lora_phy.css_config(7, 8);
            m = config.samplesPerSymbol;
            detections = 0;
            windows = 0;
            for seed = 1:20
                % Built directly rather than through add_awgn, which needs a
                % signal to define an SNR against.
                stream = RandStream("twister", Seed=seed);
                noise = complex(randn(stream, 40*m, 1), ...
                    randn(stream, 40*m, 1))/sqrt(2);
                stages = lora_phy.fft_correlator_stages(noise, config);
                bins = double(stages.symbols(:));
                for s = 1:numel(bins)-9
                    result = lora_phy.detect_preamble_run( ...
                        bins(s+(0:9)), hex2dec("12"), config);
                    detections = detections+result.valid;
                    windows = windows+1;
                end
            end
            testCase.verifyEqual(detections, 0, ...
                sprintf("%d false detections in %d windows", ...
                detections, windows));
        end

        function driftBeyondToleranceBreaksTheRun(testCase)
            config = lora_phy.css_config(7, 8);
            n = config.symbolCount;

            tolerated = lora_phy.detect_preamble_run( ...
                [40; 41; 39; 40; 40; 40; 40; 40; 48; 56], hex2dec("12"), config);
            testCase.verifyTrue(tolerated.valid);

            drifted = lora_phy.detect_preamble_run( ...
                [40; 42; 40; 40; 40; 40; 40; 40; 48; 56], hex2dec("12"), config);
            testCase.verifyFalse(drifted.preambleValid);
            testCase.verifyTrue(drifted.syncValid);

            syncOff = lora_phy.detect_preamble_run( ...
                [repmat(40, 8, 1); 48; 58], hex2dec("12"), config);
            testCase.verifyTrue(syncOff.preambleValid);
            testCase.verifyFalse(syncOff.syncValid);
            testCase.verifyEqual(syncOff.expectedSyncBins, mod(40+[8; 16], n));
        end

        function preambleLengthAndToleranceAreConfigurable(testCase)
            config = lora_phy.css_config(7, 8);

            short = lora_phy.detect_preamble_run([repmat(9, 6, 1); 17; 25], ...
                hex2dec("12"), config, PreambleSymbols=6);
            testCase.verifyTrue(short.valid);

            loose = lora_phy.detect_preamble_run( ...
                [9; 12; 9; 9; 9; 9; 9; 9; 17; 25], hex2dec("12"), config, ...
                BinTolerance=3);
            testCase.verifyTrue(loose.valid);
            testCase.verifyEqual(loose.binTolerance, 3);
        end

        function invalidInputsAreRejected(testCase)
            config = lora_phy.css_config(5, 4);
            testCase.verifyError(@() lora_phy.detect_preamble_run( ...
                zeros(9, 1), 18, config), "lora_phy:InvalidRunLength");
            testCase.verifyError(@() lora_phy.detect_preamble_run( ...
                zeros(10, 1), 256, config), "lora_phy:InvalidSyncWord");
            testCase.verifyError(@() lora_phy.detect_preamble_run( ...
                repmat(config.symbolCount, 10, 1), 18, config), ...
                "lora_phy:BinOutOfRange");
        end
    end

    methods (Static, Access = private)
        function [bins, lead, css] = correlateStream(offset, cfoBins, snr)
            %CORRELATESTREAM Free-running correlator over a placed packet.
            sf = 7;
            samplesPerChip = 8;
            phy = lora_phy.phy_config(sf, samplesPerChip, 1);
            css = lora_phy.css_config(sf, samplesPerChip);
            m = css.samplesPerSymbol;

            packet = lora_phy.build_lora_packet(uint8((1:16).'), phy, ...
                PreambleSymbols=8, SyncWord=hex2dec("12"));
            lead = 3*m+offset;
            stream = [complex(zeros(lead, 1)); packet; complex(zeros(6*m, 1))];
            if cfoBins ~= 0
                index = (0:numel(stream)-1).';
                stream = stream.*exp(1j*2*pi*cfoBins*index/m);
            end
            if isfinite(snr)
                stream = lora_phy.add_awgn(stream, snr, 7);
            end
            windows = floor(numel(stream)/m);
            stages = lora_phy.fft_correlator_stages(stream(1:windows*m), css);
            bins = double(stages.symbols(:));
        end

        function hit = findRun(bins, css)
            %FINDRUN What a streaming detector does: retry every window.
            hit = struct("start", NaN, "result", []);
            for s = 1:numel(bins)-9
                result = lora_phy.detect_preamble_run(bins(s+(0:9)), ...
                    hex2dec("12"), css);
                if result.valid
                    hit.start = s;
                    hit.result = result;
                    return
                end
            end
        end
    end
end
