classdef TestSfdValidation < matlab.unittest.TestCase
    %TESTSFDVALIDATION SFD acceptance against real dechirped downchirps.

    methods (Test)
        function sfdMirrorsThePreambleBinOnRealSamples(testCase)
            % The rule is only worth having if real SFD windows obey it, so
            % this dechirps an actual packet rather than asserting on
            % hand-written bins.
            for offsetBins = [0 1 3]
                [downBins, preambleBin, config] = ...
                    testCase.dechirpPacket(offsetBins);

                result = lora_phy.validate_sfd_bins(downBins, ...
                    preambleBin, config);

                testCase.verifyEqual(result.expectedBin, ...
                    mod(-preambleBin, config.symbolCount));
                testCase.verifyTrue(result.agree, ...
                    "the two SFD windows must agree with each other");
                testCase.verifyTrue(result.valid, ...
                    sprintf("SFD must validate at offset %d", offsetBins));
            end
        end

        function upchirpsInPlaceOfTheSfdAreRejected(testCase)
            % The failure this stage exists to catch: a run of upchirps that
            % passed preamble and sync but is not a packet. Their downchirp
            % dechirp does not sit at the mirrored bin.
            config = lora_phy.css_config(7, 4);
            n = config.symbolCount;
            preambleBin = 0;

            impostor = lora_phy.validate_sfd_bins([n/4; n/4], ...
                preambleBin, config);

            testCase.verifyTrue(impostor.agree, ...
                "the impostor windows still agree with each other");
            testCase.verifyFalse(impostor.valid, ...
                "but they must not pass as an SFD");
        end

        function disagreeingWindowsAreReported(testCase)
            config = lora_phy.css_config(7, 4);
            result = lora_phy.validate_sfd_bins([0; 40], 0, config);
            testCase.verifyFalse(result.agree);
            testCase.verifyFalse(result.valid);
        end

        function mirrorWrapsAroundTheSpectrum(testCase)
            config = lora_phy.css_config(7, 4);
            n = config.symbolCount;
            for preambleBin = [0 1 n-1 n/2]
                expected = mod(-preambleBin, n);
                result = lora_phy.validate_sfd_bins( ...
                    [expected; expected], preambleBin, config);
                testCase.verifyTrue(result.valid, ...
                    sprintf("preamble bin %d", preambleBin));
                testCase.verifyLessThan(result.expectedBin, n);
            end
        end

        function toleranceIsConfigurable(testCase)
            config = lora_phy.css_config(7, 4);
            strict = lora_phy.validate_sfd_bins([3; 3], 125, config);
            loose = lora_phy.validate_sfd_bins([3; 3], 125, config, ...
                BinTolerance=3);
            testCase.verifyEqual(strict.expectedBin, 3);
            testCase.verifyTrue(strict.valid);
            testCase.verifyTrue(loose.valid);
        end

        function invalidInputsAreRejected(testCase)
            config = lora_phy.css_config(5, 4);
            testCase.verifyError(@() lora_phy.validate_sfd_bins( ...
                zeros(0, 1), 0, config), "lora_phy:InvalidSfdBinCount");
            testCase.verifyError(@() lora_phy.validate_sfd_bins( ...
                config.symbolCount, 0, config), "lora_phy:BinOutOfRange");
            testCase.verifyError(@() lora_phy.validate_sfd_bins( ...
                0, config.symbolCount, config), "lora_phy:BinOutOfRange");
        end
    end

    methods (Static, Access = private)
        function [downBins, preambleBin, config] = dechirpPacket(offsetBins)
            %DECHIRPPACKET Aligned packet through up and down references.
            spreadingFactor = 7;
            samplesPerChip = 4;
            preambleSymbols = 8;
            phy = lora_phy.phy_config(spreadingFactor, samplesPerChip, 1);
            config = lora_phy.css_config(spreadingFactor, samplesPerChip);
            m = config.samplesPerSymbol;

            packet = lora_phy.build_lora_packet(uint8((1:16).'), phy, ...
                PreambleSymbols=preambleSymbols, SyncWord=hex2dec("12"));
            if offsetBins ~= 0
                index = (0:numel(packet)-1).';
                packet = packet.*exp(1j*2*pi*offsetBins*index/m);
            end

            upReference = conj(fft(lora_phy.modulate(0, config)));
            downReference = ...
                lora_phy.downchirp_reference_spectrum(upReference);

            preambleBin = dechirpWindow(packet(1:m), upReference, config);
            sfdStart = (preambleSymbols+2)*m;
            downBins = [ ...
                dechirpWindow(packet(sfdStart+(1:m)), downReference, config); ...
                dechirpWindow(packet(sfdStart+m+(1:m)), downReference, config)];
        end
    end
end

function bin = dechirpWindow(window, reference, config)
%DECHIRPWINDOW One correlator window, matching fft_correlator_stages.
n = config.symbolCount;
m = config.samplesPerSymbol;
product = fft(window).*reference;
partition = sum(reshape(product, n, []), 2);
spectrum = abs(fft(partition)/m).^2;
[~, peak] = max(spectrum);
bin = peak-1;
end
