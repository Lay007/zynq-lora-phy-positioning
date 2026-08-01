function [results, figureHandle] = plot_ber_curve(outputPath)
%PLOT_BER_CURVE Simulate and visualize uncoded CSS BER/SER versus sample SNR.

rootDirectory = fileparts(fileparts(mfilename("fullpath")));
addpath(rootDirectory);
if nargin < 1
    repositoryRoot = fileparts(fileparts(rootDirectory));
    outputPath = fullfile( ...
        repositoryRoot, "docs", "images", "css-ber-sf7.png");
end

config = lora_phy.css_config(7, 2);
snrDb = (-20:2:0).';
results = lora_phy.simulate_uncoded_ber(snrDb, config, 4000, 7);

berDisplayFloor = 0.5 ./ results.Bits;
serDisplayFloor = 0.5 ./ results.Symbols;
berForPlot = max(results.BER, berDisplayFloor);
serForPlot = max(results.SER, serDisplayFloor);

figureHandle = figure("Color", "white", "Position", [100, 100, 820, 520]);
berLine = semilogy(results.SNR_dB, berForPlot, "o-", ...
    "LineWidth", 1.5, "MarkerSize", 6, "DisplayName", "Uncoded BER");
hold on;
serLine = semilogy(results.SNR_dB, serForPlot, "s--", ...
    "LineWidth", 1.5, "MarkerSize", 6, "DisplayName", "SER");
grid on;
xlabel("SNR per complex sample, dB");
ylabel("Error probability");
title(sprintf("CSS Monte Carlo, SF%d, %d samples/chip", ...
    config.spreadingFactor, config.samplesPerChip));
legend("Location", "southwest");
ylim([1e-5, 1]);

zeroErrorPoints = results.BER == 0;
if any(zeroErrorPoints)
    scatter(results.SNR_dB(zeroErrorPoints), ...
        berForPlot(zeroErrorPoints), 48, "o", "filled", ...
        "MarkerFaceColor", berLine.Color, ...
        "MarkerEdgeColor", berLine.Color, ...
        "HandleVisibility", "off");
    text(results.SNR_dB(find(zeroErrorPoints, 1)), ...
        berForPlot(find(zeroErrorPoints, 1)) * 1.8, ...
        "Filled markers: zero observed errors", ...
        "FontSize", 9, "HorizontalAlignment", "center");
end
zeroSymbolErrorPoints = results.SER == 0;
if any(zeroSymbolErrorPoints)
    scatter(results.SNR_dB(zeroSymbolErrorPoints), ...
        serForPlot(zeroSymbolErrorPoints), 48, "s", "filled", ...
        "MarkerFaceColor", serLine.Color, ...
        "MarkerEdgeColor", serLine.Color, ...
        "HandleVisibility", "off");
end

outputDirectory = fileparts(outputPath);
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end
exportgraphics(figureHandle, outputPath, "Resolution", 160);

[imageDirectory, baseName] = fileparts(outputPath);
dataDirectory = fullfile(fileparts(imageDirectory), "data");
if ~isfolder(dataDirectory)
    mkdir(dataDirectory);
end
writetable(results, fullfile(dataDirectory, baseName + ".csv"));
end
