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

        function comparisonToleratesPlatformRoundingButNotDrift(testCase)
            % Reproduces the defect that kept CI red from the day the
            % committed-vector check was added: it demanded bit-identity
            % between vectors written on one machine and the model
            % recomputed on another. Linux CI lands up to 7.3e-12 absolute
            % away from Windows-generated vectors on stages reaching 1e6 --
            % double rounding in a different FFT implementation, not a
            % different answer -- so the check passed only on the machine
            % that wrote the vectors.
            %
            % Platform rounding cannot be reproduced on one host, so what is
            % pinned here is the contract the check has to satisfy: noise at
            % the observed scale passes, a real change does not.
            definitions = lora_verify.stage_case_definitions;
            [window, info] = lora_verify.build_stage_case(definitions(1));
            reference = lora_phy.fft_correlator_stages(window, info.config);
            tolerance = lora_verify.stage_tolerance;

            rounded = perturb(reference, 1e-15);
            report = lora_verify.compare_stages(reference, rounded);
            testCase.verifyGreaterThan(max(report.MaxAbsError), 0, ...
                "the perturbation must actually change the values");
            testCase.verifyTrue(lora_verify.stage_vectors_match(report), ...
                "last-bit rounding must not fail the committed vectors");

            drifted = perturb(reference, 1e-6);
            report = lora_verify.compare_stages(reference, drifted);
            testCase.verifyFalse(lora_verify.stage_vectors_match(report), ...
                "a real algorithmic change must still be caught");
            testCase.verifyGreaterThan(tolerance, 0);
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
                [matched, worst] = lora_verify.stage_vectors_match(report);
                testCase.verifyTrue(matched, ...
                    "Committed vectors for "+string(entry.id)+ ...
                    " differ from the model by relative RMS "+ ...
                    string(worst)+", above "+ ...
                    string(lora_verify.stage_tolerance));
                testCase.verifyEqual(recomputed.symbols(:).', ...
                    double(entry.expectedSymbols(:).'));
            end
        end
    end
end

function stages = perturb(stages, relative)
%PERTURB Scale every compared stage by 1+relative, deterministically.
% A multiplicative nudge keeps the relative error the same everywhere, so
% the test says what it means regardless of each stage's magnitude.
names = lora_verify.stage_order();
for name = names(:).'
    if isfield(stages, name) && isnumeric(stages.(name))
        stages.(name) = stages.(name)*(1+relative);
    end
end
end
