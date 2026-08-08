function result = run_tdoa_acceptance(options)
%RUN_TDOA_ACCEPTANCE Reproduce calibrated 2D TDoA Monte Carlo evidence.

arguments
    options.TrialsPerPoint (1,1) double ...
        {mustBeInteger, mustBePositive} = 1000
    options.OutputDirectory (1,1) string = ""
    options.ImageDirectory (1,1) string = ""
end

thisDirectory = fileparts(mfilename("fullpath"));
matlabDirectory = fileparts(thisDirectory);
repositoryRoot = fileparts(fileparts(matlabDirectory));
if options.OutputDirectory == ""
    options.OutputDirectory = fullfile(repositoryRoot, "docs", "data");
end
if options.ImageDirectory == ""
    options.ImageDirectory = fullfile(repositoryRoot, "docs", "images");
end
if ~isfolder(options.OutputDirectory)
    mkdir(options.OutputDirectory);
end
if ~isfolder(options.ImageDirectory)
    mkdir(options.ImageDirectory);
end

result = lora_phy.simulate_tdoa_accuracy( ...
    [0.2e-9; 1e-9; 5e-9], TrialsPerPoint=options.TrialsPerPoint, ...
    RandomSeed=7000);
writetable(result.summary, fullfile(options.OutputDirectory, ...
    "tdoa-positioning-accuracy.csv"));
save(fullfile(options.OutputDirectory, "tdoa-positioning-accuracy.mat"), ...
    "result");

figureHandle = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 1050, 460]);
layout = tiledlayout(1, 2, "TileSpacing", "compact", ...
    "Padding", "compact");
nexttile;
loglog(result.summary.NoiseStdNanoseconds, ...
    result.summary.RmseMeters, "-o", "LineWidth", 1.8, ...
    "DisplayName", "RMSE");
hold on;
loglog(result.summary.NoiseStdNanoseconds, ...
    result.summary.P95ErrorMeters, "-s", "LineWidth", 1.8, ...
    "DisplayName", "95th percentile");
grid on;
xlabel("Per-receiver timestamp noise, ns RMS");
ylabel("2D position error, m");
title("Position accuracy");
legend("Location", "northwest");

nexttile;
plot(result.summary.NoiseStdNanoseconds, ...
    result.summary.ConvergenceRate, "-o", "LineWidth", 1.8);
grid on;
set(gca, "XScale", "log");
ylim([0, 1.05]);
xlabel("Per-receiver timestamp noise, ns RMS");
ylabel("Converged solutions / trials");
title("Gauss-Newton convergence");
title(layout, sprintf( ...
    "Calibrated 2D TDoA, four receivers, %d trials per point", ...
    options.TrialsPerPoint));
exportgraphics(figureHandle, fullfile(options.ImageDirectory, ...
    "tdoa-positioning-accuracy.png"), "Resolution", 180);
close(figureHandle);
end
