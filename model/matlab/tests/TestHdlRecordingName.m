classdef TestHdlRecordingName < matlab.unittest.TestCase
    methods (Test)
        function packageTagUsesPreambleReference(testCase)
            metadata = lora_phy.parse_hdl_recording_name( ...
                "hdl_sf7_bw125k_fs2000k_package.pcm");

            testCase.verifyEqual(metadata.referenceSymbol, 0);
            testCase.verifyEqual(metadata.referenceDirection, "up");
            testCase.verifyEqual(metadata.symbolSamples, 2048);
        end

        function explicitChirpTagIsAccepted(testCase)
            metadata = lora_phy.parse_hdl_recording_name( ...
                "hdl_sf7_bw125k_fs2000k_chirp-h17-down.pcm");

            testCase.verifyEqual(metadata.referenceSymbol, 17);
            testCase.verifyEqual(metadata.referenceDirection, "down");
        end

        function ambiguousChirpTagIsRejected(testCase)
            testCase.verifyError(@() lora_phy.parse_hdl_recording_name( ...
                "hdl_sf7_bw125k_fs2000k_chirp.pcm"), ...
                "lora_phy:InvalidHdlRecordingTag");
        end
    end
end
