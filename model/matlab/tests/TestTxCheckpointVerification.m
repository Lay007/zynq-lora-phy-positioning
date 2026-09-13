classdef TestTxCheckpointVerification < matlab.unittest.TestCase
    methods (Test)
        function parserMapsAllFiveStages(testCase)
            names = [ ...
                "hdl_sf7_bw125k_fs2000k_chirp-h17-up.pcm", ...
                "hdl_sf7_bw125k_fs2000k_package.pcm", ...
                "hdl_sf7_bw125k_fs1920k_resampler.pcm", ...
                "hdl_sf7_bw125k_fs61440k_cic.pcm", ...
                "hdl_sf7_bw125k_fs61440k_mixer.pcm"];
            expectedStages = 1:5;
            expectedRates = [2e6 2e6 1.92e6 61.44e6 61.44e6];

            for k = 1:numel(names)
                metadata = lora_phy.parse_hdl_recording_name(names(k));
                testCase.verifyEqual(metadata.stageNumber, expectedStages(k));
                testCase.verifyEqual(metadata.expectedSampleRateHz, expectedRates(k));
                testCase.verifyTrue(metadata.sampleRateMatchesStage);
            end
        end

        function exactStage1ChirpPasses(testCase)
            metadata = lora_phy.parse_hdl_recording_name( ...
                "hdl_sf7_bw125k_fs2000k_chirp-h17-down.pcm");
            config = lora_phy.css_config(7, 16);
            iq = 0.5*conj(lora_phy.modulate_symbol(17, config));

            verification = lora_phy.verify_tx_checkpoint(iq, metadata);

            testCase.verifyEqual(verification.stageNumber, 1);
            testCase.verifyEqual(verification.verdict, "PASS");
            testCase.verifyTrue(verification.sampleCountPassed);
            testCase.verifyEqual(verification.expectedSampleCount, 2048);
            testCase.verifyLessThan(verification.worstEvmPercent, 1e-10);
            testCase.verifyGreaterThan(verification.worstCorrelation, 1-1e-12);
        end

        function stage1RejectsWrongLength(testCase)
            metadata = lora_phy.parse_hdl_recording_name( ...
                "hdl_sf7_bw125k_fs2000k_chirp-h0-up.pcm");
            config = lora_phy.css_config(7, 16);
            reference = lora_phy.modulate_symbol(0, config);
            iq = [0.5*reference; 0];

            verification = lora_phy.verify_tx_checkpoint(iq, metadata);

            testCase.verifyEqual(verification.verdict, "FAIL");
            testCase.verifyFalse(verification.sampleCountPassed);
        end

        function exactCurrentPackagePasses(testCase)
            metadata = lora_phy.parse_hdl_recording_name( ...
                "hdl_sf7_bw125k_fs2000k_package.pcm");
            config = lora_phy.css_config(7, 16);
            symbols = [0 0 0 0 0 0 5 17 64 127];
            directions = ["up" "up" "up" "up" "up" "up" "up" "up" "down" "up"];
            iq = complex(zeros(10*config.samplesPerSymbol,1));
            for k = 1:numel(symbols)
                chirp = lora_phy.modulate_symbol(symbols(k), config);
                if directions(k) == "down"
                    chirp = conj(chirp);
                end
                range = (k-1)*config.samplesPerSymbol + (1:config.samplesPerSymbol);
                iq(range) = 0.5*chirp;
            end

            verification = lora_phy.verify_tx_checkpoint(iq, metadata);

            testCase.verifyEqual(verification.stageNumber, 2);
            testCase.verifyEqual(verification.verdict, "PASS");
            testCase.verifyTrue(verification.sampleCountPassed);
            testCase.verifyEqual(verification.symbolsPassed, 10);
            testCase.verifyEqual(verification.transitionsCovered, 9);
            testCase.verifyLessThan(verification.worstEvmPercent, 1e-10);
            testCase.verifyGreaterThan(verification.worstCorrelation, 1-1e-12);
            testCase.verifyLessThan(verification.fullStreamEvmPercent, 1e-10);
        end

        function unreferencedStagesNeverClaimPass(testCase)
            cases = [ ...
                "hdl_sf7_bw125k_fs1920k_resampler.pcm", ...
                "hdl_sf7_bw125k_fs61440k_cic.pcm", ...
                "hdl_sf7_bw125k_fs61440k_mixer.pcm"];
            for name = cases
                metadata = lora_phy.parse_hdl_recording_name(name);
                verification = lora_phy.verify_tx_checkpoint(complex(ones(512,1)), metadata);
                testCase.verifyEqual(verification.verdict, "NOT VERIFIED");
                testCase.verifyTrue(verification.sampleRatePassed);
            end
        end
    end
end
