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

        function hdlPcmCaptureIsLoaded(testCase)
            path = [tempname, '.pcm'];
            cleanup = onCleanup(@() delete_if_present(path));
            file = fopen(path, "w", "ieee-le");
            fileCleanup = onCleanup(@() fclose(file));

            % Packed HDL words are {I[15:0], Q[15:0]}.
            % 0x4000E000 -> I=+16384, Q=-8192
            % 0xC0002000 -> I=-16384, Q=+8192
            words = uint32([hex2dec('4000E000'), hex2dec('C0002000')]);
            fwrite(file, words, "uint32");
            clear fileCleanup

            [iq, info] = lora_phy.load_iq_capture(path, "auto");

            testCase.verifyEqual(iq, complex([1; -1], [-0.5; 0.5]), ...
                "AbsTol", 1e-12);
            testCase.verifyEqual(info.format, "hdl32");
            testCase.verifyEqual(info.sampleCount, 2);
            testCase.verifyEqual(info.componentCount, 4);
            testCase.verifyTrue(isnan(info.clippedComponentFraction));
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
