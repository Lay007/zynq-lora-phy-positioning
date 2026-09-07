classdef TestIqInspector < matlab.unittest.TestCase
    methods (Test)
        function cu8CaptureIsLoaded(testCase)
            path = [tempname, '.cu8'];
            cleanup = onCleanup(@() delete_if_present(path));
            file = fopen(path, "w");
            fileCleanup = onCleanup(@() fclose(file));
            fwrite(file, uint8([0, 255, 128, 127]), "uint8");
            clear fileCleanup

            [iq, info] = lora_phy.load_iq_capture(path, "auto");

            expected = complex([-1; 0.5/127.5], [1; -0.5/127.5]);
            testCase.verifyEqual(iq, expected, "AbsTol", 1e-12);
            testCase.verifyEqual(info.format, "cu8");
            testCase.verifyEqual(info.sampleCount, 2);
            testCase.verifyEqual(info.clippedComponentFraction, 0.5);
        end

        function cf32CaptureIsLoaded(testCase)
            path = [tempname, '.cf32'];
            cleanup = onCleanup(@() delete_if_present(path));
            file = fopen(path, "w", "ieee-le");
            fileCleanup = onCleanup(@() fclose(file));
            fwrite(file, single([0.25, -0.5, 1.0, 0.75]), "single");
            clear fileCleanup

            [iq, info] = lora_phy.load_iq_capture(path, "auto");

            testCase.verifyEqual(iq, complex([0.25; 1], [-0.5; 0.75]), ...
                "AbsTol", 1e-7);
            testCase.verifyEqual(info.format, "cf32");
            testCase.verifyTrue(isnan(info.clippedComponentFraction));
        end

        function ci16CaptureIsLoaded(testCase)
            path = [tempname, '.pcm'];
            cleanup = onCleanup(@() delete_if_present(path));
            file = fopen(path, "w", "ieee-le");
            fileCleanup = onCleanup(@() fclose(file));

            % Conventional complex int16 stream: I0,Q0,I1,Q1,...
            raw = int16([16384, -8192, -16384, 8192]);
            fwrite(file, raw, "int16");
            clear fileCleanup

            [iq, info] = lora_phy.load_iq_capture(path, "auto");

            testCase.verifyEqual(iq, complex([0.5; -0.5], [-0.25; 0.25]), ...
                "AbsTol", 1e-12);
            testCase.verifyEqual(info.format, "ci16");
            testCase.verifyEqual(info.sampleCount, 2);
            testCase.verifyEqual(info.componentCount, 4);
            testCase.verifyEqual(info.clippedComponentFraction, 0);
        end

        function hdlRecordingNameProvidesVerificationMetadata(testCase)
            metadata = lora_phy.parse_hdl_recording_name( ...
                "hdl_sf7_bw125k_fs2000k_chirp-h17-down.pcm");

            testCase.verifyEqual(metadata.spreadingFactor, 7);
            testCase.verifyEqual(metadata.bandwidthHz, 125e3);
            testCase.verifyEqual(metadata.sampleRateHz, 2e6);
            testCase.verifyEqual(metadata.samplesPerChip, 16);
            testCase.verifyTrue(metadata.integerSamplesPerChip);
            testCase.verifyEqual(metadata.referenceSymbol, 17);
            testCase.verifyEqual(metadata.referenceDirection, "down");
        end

        function projectProfileMatchesSx1262(testCase)
            profile = lora_phy.match_lora_profile(7, 125e3, 868.35e6);

            testCase.verifyEqual(profile.modulation, "LoRa CSS");
            testCase.verifyEqual(profile.semtechPacketType, "PACKET_TYPE_LORA");
            testCase.verifyTrue(any(profile.compatibleRadios == "SX1262"));
            testCase.verifyTrue(any(profile.compatibleRadios == "SX1276"));
            testCase.verifyFalse(any(profile.compatibleRadios == "SX1278"));
            testCase.verifyTrue(profile.projectReferenceCompatible);
            testCase.verifyEqual(profile.symbolDurationSeconds, 128/125e3, ...
                "AbsTol", 1e-15);
        end

        function exactChirpPassesGoldenComparison(testCase)
            config = lora_phy.css_config(7, 16);
            reference = lora_phy.modulate_symbol(17, config);
            capture = [zeros(12,1); 0.5*reference; zeros(8,1)];

            metrics = lora_phy.compare_iq_to_golden( ...
                capture, 2e6, 7, 125e3, ...
                StartIndex=10, Symbol=17, Direction="up", ...
                SearchRadiusSamples=8);

            testCase.verifyEqual(metrics.bestStartIndex, 13);
            testCase.verifyLessThan(metrics.evmPercent, 1e-10);
            testCase.verifyGreaterThan(metrics.correlation, 1-1e-12);
            testCase.verifyLessThan(metrics.rmsPhaseErrorDegrees, 1e-10);
            testCase.verifyTrue(metrics.passed);
        end

        function sfBandwidthAndCarrierAreEstimated(testCase)
            config = lora_phy.css_config(7, 4);
            payload = [3; 17; 64];
            frame = lora_phy.build_css_frame(payload, config, 8, 2);
            sampleRateHz = 500e3;
            carrierOffsetHz = 40e3;
            capture = [zeros(4000, 1); frame; zeros(3000, 1)];
            capture = lora_phy.apply_frequency_offset( ...
                capture, carrierOffsetHz/sampleRateHz);
            rng(7, "twister");
            noise = sqrt(0.002/2)*(randn(size(capture))+1j*randn(size(capture)));

            result = lora_phy.inspect_iq_capture(capture+noise, sampleRateHz);

            testCase.verifyEqual(result.estimatedBandwidthHz, 125e3);
            testCase.verifyEqual(result.estimatedSpreadingFactor, 7);
            testCase.verifyEqual(result.alignedStartIndex, 4001, "AbsTol", 4);
            testCase.verifyEqual(result.estimatedCarrierOffsetHz, ...
                carrierOffsetHz, "AbsTol", 1500);
            testCase.verifyGreaterThan(result.estimatedSnrDb, 20);
            testCase.verifyEqual(result.detectedSymbols(1:8), zeros(8, 1));
            testCase.verifyEqual(result.detectedSymbols(end-2:end), payload);
        end

        function spectrogramDimensionsAreConsistent(testCase)
            iq = exp(2j*pi*0.1*(0:4095).');
            result = lora_phy.compute_spectrogram(iq, 1e6, 256, 40);

            testCase.verifySize(result.powerDb, ...
                [numel(result.frequencyHz), numel(result.timeSeconds)]);
            testCase.verifyLessThanOrEqual(numel(result.timeSeconds), 40);
        end

        function completeBurstIsPreferredOverBoundaryFragment(testCase)
            config = lora_phy.css_config(7, 4);
            frame = lora_phy.build_css_frame([3; 17; 64], config, 8, 2);
            fragment = frame(round(end/3):end);
            capture = [fragment; zeros(3000, 1); frame; zeros(3000, 1)];
            rng(11, "twister");
            noise = sqrt(0.0002/2)*(randn(size(capture))+1j*randn(size(capture)));

            result = lora_phy.inspect_iq_capture(capture+noise, 500e3, ...
                CandidateBandwidthHz=125e3, CandidateSpreadingFactors=7);

            expectedStart = numel(fragment)+3001;
            testCase.verifyEqual(result.packetStartIndex, expectedStart, ...
                "AbsTol", 300);
            testCase.verifyGreaterThan(result.packetStartIndex, numel(fragment));
        end
    end
end

function delete_if_present(path)
if isfile(path)
    delete(path);
end
end
