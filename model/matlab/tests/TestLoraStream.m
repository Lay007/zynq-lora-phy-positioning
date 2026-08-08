classdef TestLoraStream < matlab.unittest.TestCase
    methods (Test)
        function completePacketsAreBuiltWithTruthMetadata(testCase)
            config = lora_phy.phy_config(7, 4, 2);
            payloads = {lora_phy.counter_payload(1, 10, 16); ...
                lora_phy.counter_payload(2, 20, 20)};

            [stream, truth, metadata] = lora_phy.build_lora_stream( ...
                payloads, config, 125e3, PreambleSymbols=12, ...
                InterPacketGapSeconds=0.01, RandomSeed=41);

            testCase.verifyEqual(height(truth), 2);
            testCase.verifyEqual(metadata.sampleRateHz, 500e3);
            testCase.verifyGreaterThan(truth.StartIndex(2), truth.EndIndex(1));
            testCase.verifyEqual(truth.Payload{1}, payloads{1});
            testCase.verifyEqual(numel(stream), ...
                round(metadata.durationSeconds*metadata.sampleRateHz));
        end

        function continuousStreamRoundTripsEndToEnd(testCase)
            config = lora_phy.phy_config(7, 4, 2);
            payloads = {lora_phy.counter_payload(11, 100, 16); ...
                lora_phy.counter_payload(12, 200, 24); ...
                lora_phy.counter_payload(13, 300, 32)};
            [stream, truth, metadata] = lora_phy.build_lora_stream( ...
                payloads, config, 125e3, PreambleSymbols=12, ...
                InterPacketGapSeconds=0.03, RandomSeed=42);
            rng(43, "twister");
            stream = stream+sqrt(1e-5/2)*(randn(size(stream))+ ...
                1j*randn(size(stream)));

            receiver = lora_phy.receive_lora_stream(stream, ...
                metadata.sampleRateHz, metadata.bandwidthHz, config, ...
                PreambleSymbols=12);
            evaluation = lora_phy.evaluate_lora_stream( ...
                receiver, truth, config);

            testCase.verifyEqual(receiver.successCount, 3);
            testCase.verifyEqual(evaluation.summary.Transmissions, 3);
            testCase.verifyEqual(evaluation.summary.AcquiredPackets, 3);
            testCase.verifyEqual(evaluation.summary.FalseAlarmCandidates, 0);
            testCase.verifyEqual(evaluation.summary.DuplicateCandidates, 0);
            testCase.verifyEqual(evaluation.summary.PER, 0);
            testCase.verifyEqual(evaluation.summary.PayloadBER, 0);
        end

        function implicitHeaderPacketRoundTrips(testCase)
            config = lora_phy.phy_config(7, 4, 3);
            config.explicitHeader = false;
            config.payloadLength = 20;
            payload = lora_phy.counter_payload(21, 100, config.payloadLength);
            [packet, ~] = lora_phy.build_lora_packet(payload, config, ...
                PreambleSymbols=12);
            capture = [zeros(3000, 1); packet; zeros(4000, 1)];

            result = lora_phy.receive_lora_packet(capture, 500e3, ...
                125e3, 7, PreambleSymbols=12, ExplicitHeader=false, ...
                PayloadLength=config.payloadLength, ...
                CodingRate=config.codingRate, PayloadCrc=config.payloadCrc);

            testCase.verifyTrue(result.success);
            testCase.verifyEqual(result.decoded.payload, payload);
            testCase.verifyFalse(result.config.explicitHeader);
        end

        function evaluatorSeparatesMissesDuplicatesAndFalseAlarms(testCase)
            config = lora_phy.phy_config(7, 4, 1);
            payloads = {lora_phy.counter_payload(31, 100, 16); ...
                lora_phy.counter_payload(32, 200, 16)};
            [~, truth, metadata] = lora_phy.build_lora_stream( ...
                payloads, config, 125e3, PreambleSymbols=12);
            first = [truth.StartIndex(1), truth.EndIndex(1)];
            duplicate = first+[100, -100];
            falseRun = [truth.EndIndex(end)+1000, truth.EndIndex(end)+2000];
            receiver = struct("activityRuns", ...
                [first; duplicate; falseRun], "receptions", ...
                repmat(struct, 0, 1), "candidateCount", 3, ...
                "sampleRateHz", metadata.sampleRateHz, ...
                "durationSeconds", metadata.durationSeconds+1);

            evaluation = lora_phy.evaluate_lora_stream( ...
                receiver, truth, config);

            testCase.verifyEqual(evaluation.summary.EnergyDetectedPackets, 1);
            testCase.verifyEqual(evaluation.summary.MissedEnergyDetections, 1);
            testCase.verifyEqual(evaluation.summary.DuplicateCandidates, 1);
            testCase.verifyEqual(evaluation.summary.FalseAlarmCandidates, 1);
            testCase.verifyEqual(evaluation.summary.PER, 1);
        end

        function chirpDetectorFindsPacketsBelowEnergyFloor(testCase)
            config = lora_phy.phy_config(7, 4, 1);
            payloads = {lora_phy.counter_payload(41, 100, 16); ...
                lora_phy.counter_payload(42, 200, 16)};
            [stream, truth, metadata] = lora_phy.build_lora_stream( ...
                payloads, config, 125e3, PreambleSymbols=12, ...
                InterPacketGapSeconds=0.03, RandomSeed=44);
            received = lora_phy.apply_channel_impairments( ...
                stream, metadata.sampleRateHz, SnrDb=-10, ...
                NoiseReferencePower=1, RandomSeed=45);

            [starts, diagnostics] = lora_phy.detect_lora_preambles( ...
                received, metadata.sampleRateHz, metadata.bandwidthHz, 7, ...
                PreambleSymbols=12);

            testCase.verifyEqual(numel(starts), 2);
            testCase.verifyLessThanOrEqual(abs(starts- ...
                truth.PreambleStartIndex), config.samplesPerSymbol);
            testCase.verifyTrue(any(diagnostics.sequenceSyncValid & ...
                diagnostics.sequenceSfdValid));
        end

        function noiseOnlyStreamHasNoLoRaCandidates(testCase)
            config = lora_phy.phy_config(7, 4, 1);
            rng(46, "twister");
            noise = sqrt(0.5)*(randn(250000, 1)+1j*randn(250000, 1));

            receiver = lora_phy.receive_lora_stream( ...
                noise, 500e3, 125e3, config, PreambleSymbols=12);

            testCase.verifyEqual(receiver.candidateCount, 0);
            testCase.verifyEqual(receiver.successCount, 0);
        end

        function strongEnergyCandidateDoesNotHideWeakChirpCandidate(testCase)
            config = lora_phy.phy_config(7, 4, 1);
            payloads = {lora_phy.counter_payload(51, 100, 16); ...
                lora_phy.counter_payload(52, 200, 16)};
            [stream, truth, metadata] = lora_phy.build_lora_stream( ...
                payloads, config, 125e3, PreambleSymbols=12, ...
                InterPacketGapSeconds=0.05, Amplitudes=[4; 1], ...
                RandomSeed=47);
            received = lora_phy.apply_channel_impairments( ...
                stream, metadata.sampleRateHz, SnrDb=-8, ...
                NoiseReferencePower=1, RandomSeed=48);

            receiver = lora_phy.receive_lora_stream(received, ...
                metadata.sampleRateHz, metadata.bandwidthHz, config, ...
                PreambleSymbols=12);
            evaluation = lora_phy.evaluate_lora_stream( ...
                receiver, truth, config);

            testCase.verifyEqual(evaluation.summary.AcquiredPackets, 2);
            testCase.verifyEqual(evaluation.summary.PER, 0);
            testCase.verifyEqual(evaluation.summary.FalseAlarmCandidates, 0);
            testCase.verifyTrue(any(receiver.candidateSources == "chirp"));
        end

        function endToEndReceiverSurvivesCombinedImpairments(testCase)
            config = lora_phy.phy_config(7, 4, 2);

            result = lora_phy.simulate_lora_stream_performance( ...
                -6, config, PacketsPerPoint=3, PayloadLength=20, ...
                RandomSeed=500, FrequencyOffsetHz=1500, ...
                SampleRateOffsetPpm=20, FractionalDelaySamples=1.75, ...
                MultipathDelaysSamples=[0; 3.5], ...
                MultipathGains=[1; 0.2j], IqGainImbalanceDb=0.5, ...
                IqPhaseImbalanceDegrees=2, DcOffset=0.02, ...
                AdcFullScale=2, AdcBits=12);

            testCase.verifyEqual(result.AcquiredPackets, 3);
            testCase.verifyEqual(result.FalseAlarmCandidates, 0);
            testCase.verifyEqual(result.PER, 0);
            testCase.verifyEqual(result.UndetectedErrors, 0);
        end
    end
end
