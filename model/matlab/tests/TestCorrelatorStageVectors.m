classdef TestCorrelatorStageVectors < matlab.unittest.TestCase
    %TESTCORRELATORSTAGEVECTORS Stage decomposition and exported vectors.

    methods (Test)
        function stagesReproduceMetricsExactly(testCase)
            for samplesPerChip = [1, 2, 4, 8]
                config = lora_phy.css_config(6, samplesPerChip);
                transmitted = (0:config.symbolCount-1).';
                waveform = lora_phy.add_awgn( ...
                    lora_phy.modulate(transmitted, config), -6, ...
                    500+samplesPerChip);

                stages = lora_phy.fft_correlator_stages(waveform, config);
                [symbols, confidence, metrics, spectrum] = ...
                    lora_phy.fft_correlator_metrics(waveform, config);

                testCase.verifyEqual(stages.symbols, symbols);
                testCase.verifyEqual(stages.confidence, confidence);
                testCase.verifyEqual(stages.metrics, metrics);
                testCase.verifyEqual(stages.magnitudeSquared, spectrum);
            end
        end

        function stageDecompositionIsInternallyConsistent(testCase)
            config = lora_phy.css_config(7, 4);
            waveform = lora_phy.modulate([5; 90], config);
            stages = lora_phy.fft_correlator_stages(waveform, config);

            testCase.verifyEqual(stages.fftM, fft(stages.input, [], 1), ...
                "AbsTol", 1e-9);
            testCase.verifyEqual(stages.product, ...
                stages.fftM.*stages.conjReferenceSpectrum, "AbsTol", 1e-9);

            folded = reshape(stages.product, config.symbolCount, ...
                config.samplesPerChip, []);
            testCase.verifyEqual(stages.partition, ...
                reshape(sum(folded, 2), config.symbolCount, []), ...
                "AbsTol", 1e-9);
            testCase.verifyEqual(stages.fftN, ...
                fft(stages.partition, [], 1)/config.samplesPerSymbol, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual(stages.magnitudeSquared, ...
                abs(stages.fftN).^2, "AbsTol", 1e-15);
        end

        function partitionAccumulationMatchesRecursiveComb(testCase)
            % The Simulink DUT accumulates partitions as a length-N comb
            % rather than a reshape-and-sum. Prove the two agree.
            config = lora_phy.css_config(5, 4);
            waveform = lora_phy.modulate([9; 21], config);
            stages = lora_phy.fft_correlator_stages(waveform, config);

            n = config.symbolCount;
            m = config.samplesPerSymbol;
            for column = 1:size(stages.product, 2)
                bins = stages.product(:, column);
                comb = complex(zeros(m, 1));
                for q = 1:m
                    comb(q) = bins(q);
                    if q > n
                        comb(q) = comb(q)+comb(q-n);
                    end
                end
                testCase.verifyEqual(comb(m-n+1:m), ...
                    stages.partition(:, column), "AbsTol", 1e-9);
            end
        end

        function stageCasesBuildDeterministically(testCase)
            definitions = lora_verify.stage_case_definitions;
            testCase.verifyGreaterThanOrEqual(numel(definitions), 15);

            identifiers = arrayfun(@(d) d.id, definitions);
            testCase.verifyEqual(numel(unique(identifiers)), ...
                numel(identifiers));

            for k = 1:numel(definitions)
                [first, info] = lora_verify.build_stage_case(definitions(k));
                second = lora_verify.build_stage_case(definitions(k));
                testCase.verifyEqual(first, second);
                testCase.verifyEqual(numel(first), ...
                    numel(definitions(k).symbols)*info.config.samplesPerSymbol);
                testCase.verifyTrue(all(isfinite(first)));
            end
        end

        function noiselessCasesRecoverTransmittedSymbols(testCase)
            definitions = lora_verify.stage_case_definitions;
            for k = 1:numel(definitions)
                definition = definitions(k);
                isClean = isinf(definition.snrDb) && ...
                    definition.frequencyOffsetHz == 0 && ...
                    definition.fractionalDelaySamples == 0 && ...
                    definition.integerOffsetSamples == 0;
                if ~isClean
                    continue;
                end
                [window, info] = lora_verify.build_stage_case(definition);
                stages = lora_phy.fft_correlator_stages(window, info.config);
                testCase.verifyEqual(stages.symbols(:).', ...
                    double(info.transmittedSymbols), ...
                    "Case "+definition.id+" must decode exactly");
            end
        end

        function committedVectorsMatchTheModel(testCase)
            manifest = lora_verify.load_stage_manifest;
            definitions = lora_verify.stage_case_definitions;
            testCase.verifyEqual(numel(manifest.cases), numel(definitions));

            for k = 1:numel(manifest.cases)
                entry = manifest.cases(k);
                stored = lora_verify.read_stage_vectors( ...
                    fullfile(manifest.directory, string(entry.dataFile)), ...
                    entry.stages);

                definition = definitions( ...
                    arrayfun(@(d) d.id == string(entry.id), definitions));
                testCase.verifyNumElements(definition, 1);
                [window, info] = lora_verify.build_stage_case(definition);
                recomputed = lora_phy.fft_correlator_stages( ...
                    window, info.config);

                report = lora_verify.compare_stages(stored, recomputed);
                testCase.verifyEqual(max(report.MaxAbsError), 0, ...
                    "Committed vectors for "+string(entry.id)+ ...
                    " are not bit-identical to the model");
                testCase.verifyEqual(recomputed.symbols(:).', ...
                    double(entry.expectedSymbols(:).'));
            end
        end
    end
end
