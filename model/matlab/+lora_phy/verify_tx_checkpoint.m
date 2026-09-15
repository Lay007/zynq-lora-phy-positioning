function verification = verify_tx_checkpoint(iq, metadata, options)
%VERIFY_TX_CHECKPOINT Verify one of five HDL TX-chain checkpoints.
%
% Stage 1: one LoRa/CSS chirp at parametrized Fs (integer Fs/BW).
% Stage 2: current formiration_package stream at 2.000 MS/s.
% Stage 3: output of the 24/25 resampler at 1.920 MS/s.
% Stage 4: output of the CIC interpolator at 61.440 MS/s.
% Stage 5: output of the frequency shifter at 61.440 MS/s.
%
% Stages 1 and 2 have executable MATLAB golden references today. Stages
% 3..5 deliberately return NOT VERIFIED until the repository contains the
% exact production resampler/CIC/mixer contracts needed for bit-meaningful
% reference generation.

arguments
    iq (:,1) {mustBeNumeric}
    metadata (1,1) struct
    options.StageOverride (1,1) double {mustBeInteger, mustBeGreaterThanOrEqual(options.StageOverride,0), mustBeLessThanOrEqual(options.StageOverride,5)} = 0
    options.StartIndex (1,1) double {mustBeInteger, mustBePositive} = 1
end

iq = double(iq(:));
stage = metadata.stageNumber;
if options.StageOverride > 0
    stage = options.StageOverride;
end

verification = base_result(stage, metadata, numel(iq));

switch stage
    case 1
        verification = verify_chirp(iq, metadata, verification, options.StartIndex);
    case 2
        verification = verify_package(iq, metadata, verification);
    case 3
        verification.expectedSampleRateHz = 1.92e6;
        verification.sampleRatePassed = abs(metadata.sampleRateHz-verification.expectedSampleRateHz) <= 0.5;
        verification.contractPassed = verification.sampleRatePassed;
        verification.verdict = "NOT VERIFIED";
        verification.summary = "Stage 3 contract is recognized; exact 24/25 FIR/resampler coefficients are not yet a repository golden reference.";
    case 4
        verification.expectedSampleRateHz = 61.44e6;
        verification.sampleRatePassed = abs(metadata.sampleRateHz-verification.expectedSampleRateHz) <= 0.5;
        verification.contractPassed = verification.sampleRatePassed;
        verification.verdict = "NOT VERIFIED";
        verification.summary = "Stage 4 contract is recognized; exact production CIC transfer function is not yet a repository golden reference.";
    case 5
        verification.expectedSampleRateHz = 61.44e6;
        verification.sampleRatePassed = abs(metadata.sampleRateHz-verification.expectedSampleRateHz) <= 0.5;
        verification.contractPassed = verification.sampleRatePassed;
        verification.verdict = "NOT VERIFIED";
        verification.summary = "Stage 5 contract is recognized; mixer/NCO frequency contract is not yet a repository golden reference.";
    otherwise
        error("lora_phy:InvalidTxCheckpoint", "TX checkpoint must be in the range 1..5");
end
end

function verification = base_result(stage, metadata, sampleCount)
verification = struct;
verification.stageNumber = stage;
verification.stageName = stage_name(stage);
verification.verdict = "NOT VERIFIED";
verification.summary = "No executable golden verification is available for this stage.";
verification.sampleCount = sampleCount;
verification.expectedSampleCount = NaN;
verification.sampleCountPassed = NaN;
verification.expectedSampleRateHz = NaN;
verification.sampleRatePassed = NaN;
verification.contractPassed = NaN;
verification.goldenPassed = NaN;
verification.failureReasons = strings(0,1);
verification.metrics = [];
verification.meanEvmPercent = NaN;
verification.worstEvmPercent = NaN;
verification.worstCorrelation = NaN;
verification.worstRmsPhaseErrorDegrees = NaN;
verification.symbolCount = NaN;
verification.expectedSymbolCount = NaN;
verification.symbolsPassed = NaN;
verification.transitionsCovered = NaN;
verification.metadata = metadata;
end

function verification = verify_chirp(iq, metadata, verification, startIndex)
expectedSamples = round(metadata.symbolSamples);
verification.expectedSampleCount = expectedSamples;
verification.sampleCountPassed = numel(iq) == expectedSamples;
verification.expectedSampleRateHz = NaN;
verification.sampleRatePassed = metadata.integerSamplesPerChip;
verification.contractPassed = verification.sampleCountPassed && verification.sampleRatePassed;

if ~verification.sampleRatePassed
    verification.verdict = "FAIL";
    verification.failureReasons(end+1,1) = sprintf( ...
        "Fs/BW must be integer for Stage 1 golden verification; got %.9g", ...
        metadata.samplesPerChip);
    verification.summary = sprintf("Stage 1 chirp: FAIL — %s", verification.failureReasons(1));
    return
end

metrics = lora_phy.compare_iq_to_golden( ...
    iq, metadata.sampleRateHz, metadata.spreadingFactor, metadata.bandwidthHz, ...
    StartIndex=startIndex, Symbol=metadata.referenceSymbol, ...
    Direction=metadata.referenceDirection);
verification.metrics = metrics;
verification.meanEvmPercent = metrics.evmPercent;
verification.worstEvmPercent = metrics.evmPercent;
verification.worstCorrelation = metrics.correlation;
verification.worstRmsPhaseErrorDegrees = metrics.rmsPhaseErrorDegrees;
verification.symbolCount = 1;
verification.expectedSymbolCount = 1;
verification.symbolsPassed = double(metrics.passed);
verification.transitionsCovered = 0;
verification.goldenPassed = metrics.passed;

if ~verification.sampleCountPassed
    verification.failureReasons(end+1,1) = sprintf( ...
        "sample count %d != expected %d", numel(iq), expectedSamples);
end
if ~metrics.passed
    if metrics.evmPercent > metrics.passThresholds.evmPercent
        verification.failureReasons(end+1,1) = sprintf( ...
            "EVM %.4f%% > %.4f%%", metrics.evmPercent, metrics.passThresholds.evmPercent);
    end
    if metrics.correlation < metrics.passThresholds.correlation
        verification.failureReasons(end+1,1) = sprintf( ...
            "correlation %.8f < %.8f", metrics.correlation, metrics.passThresholds.correlation);
    end
    if metrics.rmsPhaseErrorDegrees > metrics.passThresholds.rmsPhaseErrorDegrees
        verification.failureReasons(end+1,1) = sprintf( ...
            "RMS phase %.4f deg > %.4f deg", metrics.rmsPhaseErrorDegrees, ...
            metrics.passThresholds.rmsPhaseErrorDegrees);
    end
end

if verification.contractPassed && verification.goldenPassed
    verification.verdict = "PASS";
    verification.summary = sprintf( ...
        "Stage 1 chirp: PASS; EVM %.4f%%, corr %.8f, RMS phase %.4f deg", ...
        metrics.evmPercent, metrics.correlation, metrics.rmsPhaseErrorDegrees);
else
    verification.verdict = "FAIL";
    verification.summary = sprintf("Stage 1 chirp: FAIL — %s", ...
        strjoin(verification.failureReasons, "; "));
end
end

function verification = verify_package(iq, metadata, verification)
config = lora_phy.css_config(metadata.spreadingFactor, round(metadata.samplesPerChip));
if abs(metadata.samplesPerChip-round(metadata.samplesPerChip)) > 1e-9
    error("lora_phy:NonIntegerSamplesPerChip", ...
        "Stage 2 package verification requires integer Fs/BW");
end

% Current production contract of formiration_package, not a complete
% standard LoRa PHY frame.
symbols = [0 0 0 0 0 0 5 17 64 127];
directions = ["up" "up" "up" "up" "up" "up" "up" "up" "down" "up"];
symbolSamples = config.samplesPerSymbol;
expectedSamples = numel(symbols)*symbolSamples;
verification.expectedSampleCount = expectedSamples;
verification.sampleCountPassed = numel(iq) == expectedSamples;
verification.expectedSampleRateHz = 2e6;
verification.sampleRatePassed = abs(metadata.sampleRateHz-verification.expectedSampleRateHz) <= 0.5;
verification.symbolCount = floor(numel(iq)/symbolSamples);
verification.expectedSymbolCount = numel(symbols);
verification.transitionsCovered = numel(symbols)-1;
verification.contractPassed = verification.sampleCountPassed && verification.sampleRatePassed && ...
    verification.symbolCount >= verification.expectedSymbolCount;

reference = complex(zeros(expectedSamples,1));
perSymbol = repmat(struct('symbol',0,'direction',"up",'passed',false, ...
    'evmPercent',Inf,'correlation',0,'rmsPhaseErrorDegrees',Inf), numel(symbols), 1);

usableSymbols = min(numel(symbols), floor(numel(iq)/symbolSamples));
for k = 1:numel(symbols)
    ref = lora_phy.modulate_symbol(symbols(k), config);
    if directions(k) == "down"
        ref = conj(ref);
    end
    range = (k-1)*symbolSamples + (1:symbolSamples);
    reference(range) = ref(:);
    if k <= usableSymbols
        metrics = lora_phy.compare_iq_to_golden( ...
            iq(range), metadata.sampleRateHz, metadata.spreadingFactor, ...
            metadata.bandwidthHz, StartIndex=1, Symbol=symbols(k), ...
            Direction=directions(k), SearchRadiusSamples=0);
        perSymbol(k).symbol = symbols(k);
        perSymbol(k).direction = directions(k);
        perSymbol(k).passed = metrics.passed;
        perSymbol(k).evmPercent = metrics.evmPercent;
        perSymbol(k).correlation = metrics.correlation;
        perSymbol(k).rmsPhaseErrorDegrees = metrics.rmsPhaseErrorDegrees;
    end
end
verification.metrics = perSymbol;
verification.symbolsPassed = sum([perSymbol.passed]);
verification.meanEvmPercent = mean([perSymbol(1:usableSymbols).evmPercent]);
verification.worstEvmPercent = max([perSymbol(1:usableSymbols).evmPercent]);
verification.worstCorrelation = min([perSymbol(1:usableSymbols).correlation]);
verification.worstRmsPhaseErrorDegrees = max([perSymbol(1:usableSymbols).rmsPhaseErrorDegrees]);

wholePassed = false;
if numel(iq) >= expectedSamples
    received = iq(1:expectedSamples);
    gain = (reference' * received) / sum(abs(reference).^2);
    fitted = gain*reference;
    residual = received-fitted;
    evm = 100*sqrt(mean(abs(residual).^2))/max(sqrt(mean(abs(fitted).^2)), eps);
    corr = abs(reference'*received)/sqrt(sum(abs(reference).^2)*sum(abs(received).^2));
    phaseError = angle(received.*conj(fitted));
    rmsPhase = rad2deg(sqrt(mean(phaseError.^2)));
    verification.fullStreamEvmPercent = evm;
    verification.fullStreamCorrelation = corr;
    verification.fullStreamRmsPhaseErrorDegrees = rmsPhase;
    wholePassed = evm <= 1.0 && corr >= 0.999 && rmsPhase <= 1.0;
else
    verification.fullStreamEvmPercent = Inf;
    verification.fullStreamCorrelation = 0;
    verification.fullStreamRmsPhaseErrorDegrees = Inf;
end

allSymbolsPassed = usableSymbols == numel(symbols) && all([perSymbol.passed]);
verification.goldenPassed = allSymbolsPassed && wholePassed;
if ~verification.sampleCountPassed
    verification.failureReasons(end+1,1) = sprintf( ...
        "sample count %d != expected %d", numel(iq), expectedSamples);
end
if ~verification.sampleRatePassed
    verification.failureReasons(end+1,1) = sprintf( ...
        "sample rate %.6f MHz != 2.000000 MHz", metadata.sampleRateHz/1e6);
end
if verification.contractPassed && verification.goldenPassed
    verification.verdict = "PASS";
else
    verification.verdict = "FAIL";
    if ~verification.goldenPassed
        verification.failureReasons(end+1,1) = sprintf( ...
            "golden symbols %d/%d or full-stream thresholds failed", ...
            verification.symbolsPassed, numel(symbols));
    end
end
verification.summary = sprintf( ...
    "Stage 2 package: %s; symbols %d/%d, worst EVM %.4f%%, worst corr %.8f", ...
    verification.verdict, verification.symbolsPassed, numel(symbols), ...
    verification.worstEvmPercent, verification.worstCorrelation);
if verification.verdict == "FAIL" && ~isempty(verification.failureReasons)
    verification.summary = verification.summary + " — " + strjoin(verification.failureReasons, "; ");
end
end

function name = stage_name(stage)
names = [ ...
    "1 - Chirp / parametrized Fs"; ...
    "2 - Package / 2.000 MS/s"; ...
    "3 - Resampler 24/25 / 1.920 MS/s"; ...
    "4 - CIC x32 / 61.440 MS/s"; ...
    "5 - Frequency shift / 61.440 MS/s"];
name = names(stage);
end
