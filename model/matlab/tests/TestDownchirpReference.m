classdef TestDownchirpReference < matlab.unittest.TestCase
    %TESTDOWNCHIRPREFERENCE SFD dechirping reuses the upchirp reference ROM.
    %
    % Validating the SFD needs a downchirp reference, which looks like a
    % second pair of ROMs and about one extra BRAM. These tests pin the
    % identity that removes it: the same table read at the complemented
    % address with the imaginary part negated.

    methods (Test)
        function derivedSpectrumMatchesTheDirectOne(testCase)
            for spreadingFactor = [7 9]
                for samplesPerChip = [1 4]
                    config = lora_phy.css_config(spreadingFactor, ...
                        samplesPerChip);
                    referenceUp = lora_phy.modulate(0, config);

                    stored = conj(fft(referenceUp));
                    direct = conj(fft(conj(referenceUp)));
                    derived = lora_phy.downchirp_reference_spectrum(stored);

                    testCase.verifyEqual(derived, direct, ...
                        sprintf("SF%d L=%d", spreadingFactor, ...
                            samplesPerChip), RelTol=1e-12, AbsTol=1e-9);
                end
            end
        end

        function downchirpSymbolsRecoverThroughTheDerivedReference(testCase)
            % The identity is only useful if a real SFD symbol dechirps to
            % its own index through it.
            config = lora_phy.css_config(7, 4);
            m = config.samplesPerSymbol;
            n = config.symbolCount;
            stored = conj(fft(lora_phy.modulate(0, config)));
            derived = lora_phy.downchirp_reference_spectrum(stored);

            for symbol = [0 5 37 100]
                downchirp = conj(lora_phy.modulate(symbol, config));
                product = fft(downchirp).*derived;
                partition = sum(reshape(product, n, []), 2);
                spectrum = abs(fft(partition)/m).^2;
                [~, peak] = max(spectrum);

                testCase.verifyEqual(peak-1, symbol, ...
                    sprintf("downchirp %d must dechirp to its own bin", ...
                        symbol));
            end
        end

        function theTransformIsItsOwnInverse(testCase)
            % Applying it twice must return the upchirp table, which is what
            % lets one ROM serve both paths with a single mode bit.
            config = lora_phy.css_config(7, 2);
            stored = conj(fft(lora_phy.modulate(0, config)));

            roundTrip = lora_phy.downchirp_reference_spectrum( ...
                lora_phy.downchirp_reference_spectrum(stored));

            testCase.verifyEqual(roundTrip, stored, RelTol=1e-12);
        end

        function addressComplementIsAMaskForPowerOfTwoLengths(testCase)
            % The hardware claim is that the reversal costs nothing. M is
            % 2^SF times L, so it is a power of two whenever L is, and the
            % complement is then a mask rather than a subtraction.
            for spreadingFactor = 7:9
                for samplesPerChip = [1 2 4 8]
                    m = 2^spreadingFactor*samplesPerChip;
                    testCase.verifyEqual(bitand(m, m-1), 0, ...
                        "M must be a power of two for the mask to hold");

                    k = (0:m-1).';
                    testCase.verifyEqual(mod(-k, m), ...
                        bitand(m-k, m-1), ...
                        "complement must equal the masked difference");
                end
            end
        end
    end
end
