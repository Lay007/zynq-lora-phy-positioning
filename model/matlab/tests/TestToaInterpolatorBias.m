classdef TestToaInterpolatorBias < matlab.unittest.TestCase
    %TESTTOAINTERPOLATORBIAS Sub-sample ToA must not carry a systematic bias.
    %
    % Fractional ToA is what makes TDoA usable at all: the coarse timestamp
    % resolves one sample, which is 1199 m at Fs = 250 kHz. The fractional
    % part was measured at roughly 77 m of error and, crucially, that error
    % barely moved between +20 dB and -5 dB SNR. An error that ignores SNR is
    % not noise.
    %
    % A noiseless sweep of the true delay confirmed it: the estimate traces a
    % clean S-curve, zero at whole samples and worst between them, 0.17
    % samples peak to peak. That is the three-point parabola missing a
    % correlation peak that is not a parabola.
    %
    % The distinction matters for positioning rather than for tidiness. A
    % deterministic bias repeats packet to packet, so averaging does not
    % remove it, and across three stations it does not cancel -- it turns
    % into a position offset.

    methods (Test)
        function noiselessBiasStaysBelowOneHundredthSample(testCase)
            % The acceptance bar, chosen from the measurement rather than
            % from taste: the parabola on power gives 0.0625 samples RMS
            % with nothing but the interpolator to blame, and interpolating
            % the log-magnitude instead measured 0.0066. 0.01 sits between
            % them, so it fails the old rule and passes a corrected one.
            [errors, config] = testCase.sweepNoiselessDelay();
            errors = errors-mean(errors);

            testCase.verifyLessThan(rms(errors), 0.01, ...
                sprintf("systematic interpolator bias is %.4f samples", ...
                    rms(errors)));
            testCase.verifyLessThan(max(errors)-min(errors), 0.04, ...
                "peak-to-peak interpolator bias");
            testCase.verifyGreaterThan(config.sampleRateHz, 0);
        end

        function biasIsNotHiddenByNoiseAveraging(testCase)
            % The property that makes this worth a test at all: the error
            % survives averaging, because it is the same for every packet at
            % a given sub-sample delay.
            [errors, ~] = testCase.sweepNoiselessDelay();
            firstHalf = mean(errors(1:floor(end/2)));
            secondHalf = mean(errors(floor(end/2)+1:end));

            testCase.verifyLessThan(abs(firstHalf-secondHalf), 0.02, ...
                "a repeatable estimator must not drift across the sweep");
        end
    end

    methods (Static, Access = private)
        function [errors, config] = sweepNoiselessDelay()
            %SWEEPNOISELESSDELAY Estimate error against true sub-sample delay.
            spreadingFactor = 7;
            samplesPerChip = 2;
            config = lora_phy.css_config(spreadingFactor, samplesPerChip);
            config.sampleRateHz = 125e3*samplesPerChip;
            reference = lora_phy.modulate(0, config);
            lead = 2*config.samplesPerSymbol;
            tail = config.samplesPerSymbol;

            delays = (0:0.05:0.95).';
            errors = zeros(numel(delays), 1);
            for k = 1:numel(delays)
                clean = [complex(zeros(lead, 1)); reference; ...
                    complex(zeros(tail, 1))];
                delayed = lora_phy.apply_channel_impairments(clean, ...
                    config.sampleRateHz, ...
                    FractionalDelaySamples=delays(k));
                estimate = lora_phy.estimate_fractional_toa(delayed, ...
                    reference, config.sampleRateHz);
                errors(k) = estimate.toaSamples-(lead+delays(k));
            end
        end
    end
end
