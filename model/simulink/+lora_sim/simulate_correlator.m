function result = simulate_correlator(info, waveform, options)
%SIMULATE_CORRELATOR Run one aligned window through the Simulink DUT.
%
% Returns the stage outputs in exactly the layout of
% LORA_PHY.FFT_CORRELATOR_STAGES so that LORA_VERIFY.COMPARE_STAGES can be
% applied directly, plus measured latency and throughput.

arguments
    info (1,1) struct
    waveform (:,1) {mustBeNumeric}
    options.TailSamples (1,1) double = NaN
end

m = info.samplesPerSymbol;
n = info.symbolCount;
if mod(numel(waveform), m) ~= 0
    error("lora_sim:InvalidSampleCount", ...
        "Waveform must contain an integer number of CSS symbols");
end
count = numel(waveform)/m;

tail = options.TailSamples;
if isnan(tail)
    tail = 2*m+3*n+512;
end

% The pipeline must be drained past the last symbol. Rather than guessing a
% single safe tail for every SF/L, grow it until the expected number of
% valid outputs appears; a genuine defect still fails on the final attempt.
for attempt = 1:4
    try
        result = runOnce(info, waveform, m, n, count, tail);
        return;
    catch err
        drainFailure = err.identifier == "lora_sim:StageSampleCount" || ...
            err.identifier == "lora_sim:DecisionCount";
        if ~drainFailure || attempt == 4
            rethrow(err);
        end
        tail = 2*tail;
    end
end
end

function result = runOnce(info, waveform, m, n, count, tail)
stimulus = [double(waveform(:)); zeros(tail, 1)];
validVector = [true(numel(waveform), 1); false(tail, 1)];
timeAxis = (0:numel(stimulus)-1).';

stimulusIq = timeseries(complex(stimulus), timeAxis);
stimulusValid = timeseries(validVector, timeAxis);
assignin("base", "stimulusIq", stimulusIq);
assignin("base", "stimulusValid", stimulusValid);

if ~bdIsLoaded(info.modelName)
    load_system(info.modelPath);
end
set_param(info.modelName, StopTime=num2str(numel(stimulus)-1));
simulationOutput = sim(info.modelName);

fftMValid = logical(simulationOutput.fftMValid(:));
partitionValid = logical(simulationOutput.partitionValid(:));
fftNValid = logical(simulationOutput.fftNValid(:));
symbolValid = logical(simulationOutput.symbolValid(:));

result = struct;
result.symbolWindows = count;
result.fftM = gather(simulationOutput.stageFftM, fftMValid, m, count, "fftM");
result.product = gather(simulationOutput.stageProduct, fftMValid, m, ...
    count, "product");
result.partition = gather(simulationOutput.stagePartition, ...
    partitionValid, n, count, "partition");
result.fftN = gather(simulationOutput.stageFftN, fftNValid, n, count, "fftN");
result.magnitudeSquared = gather(simulationOutput.stageMagnitudeSquared, ...
    fftNValid, n, count, "magnitudeSquared");

result.symbols = double(pick(simulationOutput.symbolIndex, symbolValid, ...
    count, "symbolIndex"));
result.confidence = double(pick(simulationOutput.confidence, symbolValid, ...
    count, "confidence"));
result.peak = double(pick(simulationOutput.peakMagnitudeSquared, ...
    symbolValid, count, "peakMagnitudeSquared"));
result.spectrumSum = double(pick(simulationOutput.spectrumSum, ...
    symbolValid, count, "spectrumSum"));

boundary = logical(simulationOutput.symbolBoundary(:));
result.symbolBoundarySteps = find(boundary);

symbolSteps = find(symbolValid);
result.symbolValidSteps = symbolSteps;
result.fftMFirstValidStep = find(fftMValid, 1);
result.partitionFirstValidStep = find(partitionValid, 1);
result.fftNFirstValidStep = find(fftNValid, 1);

% Latency is counted from the last input sample of a symbol window, which
% is the earliest instant at which that symbol could possibly be decided.
result.fftMLatencySamples = result.fftMFirstValidStep-m;
result.symbolLatencySamples = symbolSteps(1)-m;
if numel(symbolSteps) > 1
    result.symbolIntervalSamples = unique(diff(symbolSteps));
else
    result.symbolIntervalSamples = m;
end
result.throughputSymbolsPerSample = 1/m;
end

function value = gather(signal, validMask, rows, columns, name)
% double() is applied last so a fixed-point run returns the same layout as
% a double run and can be compared with the golden vectors directly.
signal = signal(:);
validMask = validMask(:);
selected = signal(validMask(1:numel(signal)));
expected = rows*columns;
if numel(selected) ~= expected
    error("lora_sim:StageSampleCount", ...
        "Stage %s produced %d valid samples, expected %d", ...
        name, numel(selected), expected);
end
value = reshape(double(selected), rows, columns);
end

function value = pick(signal, validMask, expected, name)
signal = signal(:);
validMask = validMask(:);
selected = signal(validMask(1:numel(signal)));
if numel(selected) ~= expected
    error("lora_sim:DecisionCount", ...
        "Signal %s produced %d decisions, expected %d", ...
        name, numel(selected), expected);
end
value = double(selected(:));
end
