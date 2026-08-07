function [result, figureHandle] = plot_toa_accuracy(outputPath)
%PLOT_TOA_ACCURACY Visualize synthetic fractional-ToA bias and jitter.

rootDirectory = fileparts(fileparts(mfilename("fullpath")));
addpath(rootDirectory);
if nargin < 1
    repositoryRoot = fileparts(fileparts(rootDirectory));
    outputPath = fullfile(repositoryRoot, "docs", "images", ...
        "toa-accuracy-awgn.png");
end

result = lora_phy.simulate_toa_accuracy([-25; -20; -15; -10; -5], ...
    TrialsPerPoint=100, SpreadingFactor=7, SamplesPerChip=2, ...
    RandomSeed=31415);
summary = result.summary;

figureHandle = figure("Color", "white", "Position", [100, 100, 1000, 430]);
tiledlayout(1, 2, "TileSpacing", "compact", "Padding", "compact");
nexttile;
semilogy(summary.SnrDb, summary.RmsSamples, "o-", ...
    "LineWidth", 1.4, "DisplayName", "RMS");
hold on;
semilogy(summary.SnrDb, summary.P95AbsoluteSamples, "s-", ...
    "LineWidth", 1.4, "DisplayName", "95% |error|");
grid on;
xlabel("SNR, dB");
ylabel("Timing error, samples");
title("Fractional ToA accuracy");
legend("Location", "best");

nexttile;
hold on;
for snrIndex = 1:height(summary)
    errors = sort(abs(result.trials.ErrorSamples( ...
        result.trials.SnrDb == summary.SnrDb(snrIndex))));
    probability = (1:numel(errors)).'/numel(errors);
    stairs(errors, probability, "LineWidth", 1.2, ...
        "DisplayName", sprintf("%g dB", summary.SnrDb(snrIndex)));
end
grid on;
xlabel("Absolute timing error, samples");
ylabel("CDF");
title("Error distribution");
legend("Location", "southeast");

sgtitle(sprintf("CSS ToA, SF%d, Fs/BW=%d, %d trials per SNR", ...
    result.config.spreadingFactor, result.config.samplesPerChip, ...
    sum(result.trials.SnrDb == summary.SnrDb(1))));
outputDirectory = fileparts(outputPath);
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end
exportgraphics(figureHandle, outputPath, "Resolution", 160);
end
