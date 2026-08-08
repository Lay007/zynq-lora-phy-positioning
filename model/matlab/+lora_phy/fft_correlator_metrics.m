function [symbols, confidence, metrics, spectrum] = ...
    fft_correlator_metrics(waveform, config, options)
%FFT_CORRELATOR_METRICS Exact CSS matched filtering with two FFT stages.
%
% The full-rate FFT is multiplied by the conjugated reference spectrum.
% Only correlation lags spaced by samplesPerChip are needed, so frequency
% bins separated by symbolCount are accumulated before a symbolCount-point
% FFT. This is algebraically equivalent to the full-IFFT matched-filter bank
% while exposing an HDL-oriented streaming architecture.
%
% The intermediate results are defined by LORA_PHY.FFT_CORRELATOR_STAGES,
% which is also the source of the exported Simulink/HDL golden vectors.

arguments
    waveform (:,1) {mustBeNumeric}
    config (1,1) struct
    options.Reference (:,1) {mustBeNumeric} = zeros(0, 1)
end

stages = lora_phy.fft_correlator_stages(waveform, config, ...
    Reference=options.Reference);

symbols = stages.symbols;
confidence = stages.confidence;
metrics = stages.metrics;
spectrum = stages.magnitudeSquared;
end
