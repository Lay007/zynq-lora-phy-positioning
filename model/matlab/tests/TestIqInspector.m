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
    end
end

function delete_if_present(path)
if isfile(path)
    delete(path);
end
end
