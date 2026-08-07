function [impaired, diagnostics] = apply_channel_impairments( ...
    samples, sampleRateHz, options)
%APPLY_CHANNEL_IMPAIRMENTS Apply reproducible radio/front-end impairments.
%
% Positive SampleRateOffsetPpm advances through the nominal input waveform
% faster than one input sample per output sample. Positive
% FractionalDelaySamples delays the received waveform. Multipath delays are
% relative to that common delay and may be fractional.

arguments
    samples (:,1) {mustBeNumeric}
    sampleRateHz (1,1) double {mustBePositive}
    options.FrequencyOffsetHz (1,1) double = 0
    options.SampleRateOffsetPpm (1,1) double = 0
    options.FractionalDelaySamples (1,1) double = 0
    options.MultipathDelaysSamples (:,1) double = 0
    options.MultipathGains (:,1) double = 1
    options.IqGainImbalanceDb (1,1) double = 0
    options.IqPhaseImbalanceDegrees (1,1) double = 0
    options.DcOffset (1,1) double = 0
    options.SnrDb (1,1) double = Inf
    options.RandomSeed (1,1) double ...
        {mustBeInteger, mustBeNonnegative} = 0
end

if numel(options.MultipathDelaysSamples) ~= numel(options.MultipathGains)
    error("lora_phy:PathCountMismatch", ...
        "MultipathDelaysSamples and MultipathGains must have equal lengths");
end
if any(options.MultipathDelaysSamples < 0)
    error("lora_phy:NegativePathDelay", ...
        "Multipath delays must be nonnegative");
end
if isnan(options.SnrDb)
    error("lora_phy:InvalidSnr", "SnrDb cannot be NaN");
end

samples = double(samples(:));
sampleCount = numel(samples);
nominalAxis = (0:sampleCount-1).';
rateScale = 1+options.SampleRateOffsetPpm*1e-6;
impaired = complex(zeros(sampleCount, 1));
for path = 1:numel(options.MultipathGains)
    totalDelay = options.FractionalDelaySamples+ ...
        options.MultipathDelaysSamples(path);
    sourceAxis = (nominalAxis-totalDelay)*rateScale;
    pathSamples = interp1(nominalAxis, samples, sourceAxis, "linear", 0);
    impaired = impaired+options.MultipathGains(path)*pathSamples;
end

phase = 2*pi*options.FrequencyOffsetHz*nominalAxis/sampleRateHz;
impaired = impaired.*exp(1j*phase);

gainRatio = 10^(options.IqGainImbalanceDb/20);
iGain = sqrt(gainRatio);
qGain = 1/sqrt(gainRatio);
phaseError = deg2rad(options.IqPhaseImbalanceDegrees);
iComponent = iGain*real(impaired);
qComponent = qGain*(cos(phaseError)*imag(impaired)+ ...
    sin(phaseError)*real(impaired));
impaired = complex(iComponent, qComponent)+options.DcOffset;

signalPower = mean(abs(impaired).^2);
noisePower = 0;
if isfinite(options.SnrDb)
    if signalPower == 0
        error("lora_phy:ZeroSignal", ...
            "Cannot define SNR for an all-zero impaired signal");
    end
    noisePower = signalPower/10^(options.SnrDb/10);
    previousState = rng;
    restoreState = onCleanup(@() rng(previousState));
    rng(options.RandomSeed, "twister");
    noise = sqrt(noisePower/2)*( ...
        randn(size(impaired))+1j*randn(size(impaired)));
    impaired = impaired+noise;
end

diagnostics = struct;
diagnostics.sampleRateHz = sampleRateHz;
diagnostics.sampleRateOffsetPpm = options.SampleRateOffsetPpm;
diagnostics.frequencyOffsetHz = options.FrequencyOffsetHz;
diagnostics.commonDelaySamples = options.FractionalDelaySamples;
diagnostics.multipathDelaysSamples = options.MultipathDelaysSamples;
diagnostics.multipathGains = options.MultipathGains;
diagnostics.iqGainImbalanceDb = options.IqGainImbalanceDb;
diagnostics.iqPhaseImbalanceDegrees = options.IqPhaseImbalanceDegrees;
diagnostics.dcOffset = options.DcOffset;
diagnostics.requestedSnrDb = options.SnrDb;
diagnostics.signalPower = signalPower;
diagnostics.noisePower = noisePower;
diagnostics.randomSeed = options.RandomSeed;
end
