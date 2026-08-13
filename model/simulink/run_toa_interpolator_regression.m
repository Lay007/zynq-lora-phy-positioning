function report = run_toa_interpolator_regression(options)
%RUN_TOA_INTERPOLATOR_REGRESSION Check the ToA interpolator against MATLAB.
%
% The DUT works in fixed point and the reference in double, so unlike the
% other integer subsystems this comparison has a tolerance rather than being
% bit-exact. The tolerance is stated in metres, because that is the unit the
% result is used in: the whole block exists to turn a 1199 m sample step
% into something a position solver can use.
%
% Correlation triplets come from real chirp peaks at known sub-sample
% delays, not from synthetic numbers, so the sweep exercises the peak shape
% the interpolator was chosen for.

arguments
    options.SpreadingFactor (1,1) double = 7
    options.SamplesPerChip (1,1) double = 2
    options.LogTableBits (1,1) double = 6
    options.FractionBits (1,1) double = 12
    options.ToleranceMetres (1,1) double = 5
    options.OutputDirectory string = string.empty
    options.WriteCsv (1,1) logical = true
    options.Verbose (1,1) logical = true
end

simulinkRoot = fileparts(mfilename("fullpath"));
repositoryRoot = fileparts(fileparts(simulinkRoot));
addpath(simulinkRoot);
addpath(fullfile(repositoryRoot, "model", "matlab"));
if isempty(options.OutputDirectory)
    options.OutputDirectory = string(fullfile(repositoryRoot, "docs", "data"));
end

speedOfLight = 299792458;
config = lora_phy.css_config(options.SpreadingFactor, ...
    options.SamplesPerChip);
sampleRateHz = 125e3*options.SamplesPerChip;
metresPerSample = speedOfLight/sampleRateHz;

[triplets, truth] = buildTriplets(config, sampleRateHz);
count = size(triplets, 1);

% The DUT takes integer magnitudes, so the reference has to be given the
% same integers. Comparing it against the unquantized doubles would blame
% the DUT for input quantization: the scale factor is not a power of two, so
% the mantissas land in different table buckets and the two disagree by
% about 10 m for reasons that have nothing to do with the logic.
scaled = round(triplets*(2^24/max(triplets(:))));

expected = zeros(count, 1);
for k = 1:count
    result = lora_phy.fractional_toa_from_triplet(scaled(k, :).', ...
        LogTableBits=options.LogTableBits);
    expected(k) = result.fractionalOffsetSamples;
end

info = build_toa_interpolator_model(LogTableBits=options.LogTableBits, ...
    FractionBits=options.FractionBits, ...
    ModelName="lora_toa_interpolator_check");
cleanup = onCleanup(@() closeIfLoaded(info.modelName));

timeAxis = (0:count-1).';
assignin("base", "stimulusMagnitudeBefore", ...
    timeseries(uint32(scaled(:, 1)), timeAxis));
assignin("base", "stimulusMagnitudePeak", ...
    timeseries(uint32(scaled(:, 2)), timeAxis));
assignin("base", "stimulusMagnitudeAfter", ...
    timeseries(uint32(scaled(:, 3)), timeAxis));
assignin("base", "stimulusTripletValid", timeseries(true(count, 1), timeAxis));

if ~bdIsLoaded(info.modelName)
    load_system(info.modelPath);
end
set_param(info.modelName, StopTime=num2str(count-1));
out = sim(info.modelName);

actual = double(out.offsetSamples(:))/info.offsetScale;
valid = logical(out.offsetValid(:));

errorSamples = actual-expected;
errorMetres = abs(errorSamples)*metresPerSample;
truthErrorMetres = abs(actual-truth)*metresPerSample;

report = struct;
report.summary = table(options.SpreadingFactor, options.SamplesPerChip, ...
    options.LogTableBits, info.logTableEntries, count, sum(valid), ...
    max(abs(errorSamples)), max(errorMetres), rms(truthErrorMetres), ...
    VariableNames=["SF", "L", "LogTableBits", "LogTableEntries", ...
    "Cases", "ValidDecisions", "MaxErrorSamples", "MaxErrorMetres", ...
    "RmsAgainstTruthMetres"]);

failures = strings(0, 1);
if ~all(valid)
    failures(end+1, 1) = sprintf("%d of %d triplets reported invalid", ...
        count-sum(valid), count);
end
if max(errorMetres) > options.ToleranceMetres
    failures(end+1, 1) = sprintf( ...
        "DUT departs from MATLAB by %.1f m, tolerance %.1f m", ...
        max(errorMetres), options.ToleranceMetres);
end
% The block is worthless if it does not beat the sample it replaces.
if rms(truthErrorMetres) > metresPerSample/10
    failures(end+1, 1) = sprintf( ...
        "interpolated error %.1f m is not usefully below the %.0f m sample", ...
        rms(truthErrorMetres), metresPerSample);
end
report.failures = failures;
report.passed = isempty(failures);
report.metresPerSample = metresPerSample;

if options.WriteCsv
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(report.summary, fullfile(options.OutputDirectory, ...
        "simulink-m2-toa-interpolator.csv"));
end

if options.Verbose
    disp(report.summary);
    fprintf("one sample = %.0f m; interpolated RMS %.1f m\n", ...
        metresPerSample, rms(truthErrorMetres));
    if report.passed
        fprintf("ToA interpolator matches MATLAB within %.1f m over %d cases.\n", ...
            options.ToleranceMetres, count);
    else
        fprintf("FAILURES:\n  %s\n", strjoin(failures, newline+"  "));
    end
end
end

function [triplets, truth] = buildTriplets(config, sampleRateHz)
%BUILDTRIPLETS Real chirp correlation peaks at known sub-sample delays.
reference = lora_phy.modulate(0, config);
lead = 2*config.samplesPerSymbol;
delays = (0.05:0.05:0.95).';
triplets = zeros(numel(delays), 3);
truth = zeros(numel(delays), 1);
for k = 1:numel(delays)
    clean = [complex(zeros(lead, 1)); reference; ...
        complex(zeros(config.samplesPerSymbol, 1))];
    delayed = lora_phy.apply_channel_impairments(clean, sampleRateHz, ...
        FractionalDelaySamples=delays(k));
    correlation = conv(delayed, conj(flipud(reference)));
    [~, peak] = max(abs(correlation));
    triplets(k, :) = abs(correlation(peak+(-1:1))).';
    truth(k) = (lead+delays(k))-(peak-numel(reference));
end
end

function closeIfLoaded(modelName)
if bdIsLoaded(modelName)
    set_param(modelName, Dirty="off");
    close_system(modelName, 0);
end
end
