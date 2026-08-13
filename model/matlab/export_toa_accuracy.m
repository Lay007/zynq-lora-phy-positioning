function summary = export_toa_accuracy(options)
%EXPORT_TOA_ACCURACY Publish fractional-ToA accuracy against SNR.
%
% Writes docs/data/toa-interpolator-accuracy.csv so the metre figures quoted
% in the acceptance documents have a committed table behind them.
%
% Samples are converted to metres at the campaign's own sample rate, because
% "0.0088 samples" is not a number anyone can act on and 10.6 m is.
%
% These are synthetic AWGN results. They are not a bench characteristic and
% must never be quoted as one: no cable calibration, no multipath, and no
% hardware clock is involved.

arguments
    options.SnrDb (1,:) double = [20 10 0 -5 -10]
    options.Trials (1,1) double {mustBeInteger, mustBePositive} = 200
    options.OutputDirectory string = string.empty
    options.WriteCsv (1,1) logical = true
    options.Verbose (1,1) logical = true
end

matlabRoot = fileparts(mfilename("fullpath"));
repositoryRoot = fileparts(fileparts(matlabRoot));
addpath(matlabRoot);
if isempty(options.OutputDirectory)
    options.OutputDirectory = string(fullfile(repositoryRoot, "docs", "data"));
end

speedOfLight = 299792458;
rows = cell(numel(options.SnrDb), 1);
for k = 1:numel(options.SnrDb)
    result = lora_phy.simulate_toa_accuracy(options.SnrDb(k), ...
        Trials=options.Trials);
    entry = result.summary;
    metresPerSample = speedOfLight/result.sampleRateHz;
    rows{k} = table(options.SnrDb(k), result.sampleRateHz, ...
        options.Trials, entry.BiasSamples, entry.StdSamples, ...
        entry.RmsSamples, entry.P95AbsoluteSamples, ...
        entry.StdSamples*metresPerSample, ...
        entry.P95AbsoluteSamples*metresPerSample, metresPerSample, ...
        VariableNames=["SnrDb", "SampleRateHz", "Trials", "BiasSamples", ...
        "StdSamples", "RmsSamples", "P95AbsoluteSamples", "StdMetres", ...
        "P95Metres", "CoarseStepMetres"]);
    if options.Verbose
        fprintf("SNR %-5d std %.4f sa = %6.1f m   p95 %6.1f m\n", ...
            options.SnrDb(k), entry.StdSamples, ...
            entry.StdSamples*metresPerSample, ...
            entry.P95AbsoluteSamples*metresPerSample);
    end
end

summary = vertcat(rows{:});
if options.WriteCsv
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(summary, fullfile(options.OutputDirectory, ...
        "toa-interpolator-accuracy.csv"));
end
if options.Verbose
    fprintf("coarse timestamp step %.0f m; fractional ToA is what makes " + ...
        "TDoA usable at all.\n", summary.CoarseStepMetres(1));
end
end
