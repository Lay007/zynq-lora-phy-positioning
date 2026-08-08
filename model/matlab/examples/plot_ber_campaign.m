function campaign = plot_ber_campaign(outputDirectory, options)
%PLOT_BER_CAMPAIGN Compare CSS demodulators and coded low-SF performance.

arguments
    outputDirectory (1,1) string = ""
    options.UncodedSymbolsPerPoint (1,1) double ...
        {mustBeInteger, mustBePositive} = 4000
    options.CodedPacketsPerPoint (1,1) double ...
        {mustBeInteger, mustBePositive} = 200
    options.PayloadBytes (1,1) double ...
        {mustBeInteger, mustBePositive} = 16
    options.UncodedSnrDb (:,1) double = (-20:2:-4).'
    options.CodedSnrDb (:,1) double = (-20:2:-4).'
end
rootDirectory = fileparts(fileparts(mfilename("fullpath")));
addpath(rootDirectory);
if outputDirectory == ""
    repositoryRoot = fileparts(fileparts(rootDirectory));
    outputDirectory = fullfile(repositoryRoot, "docs");
end
imageDirectory = fullfile(outputDirectory, "images");
dataDirectory = fullfile(outputDirectory, "data");
if ~isfolder(imageDirectory)
    mkdir(imageDirectory);
end
if ~isfolder(dataDirectory)
    mkdir(dataDirectory);
end

uncoded = run_uncoded(options.UncodedSnrDb, ...
    options.UncodedSymbolsPerPoint);
uncodedFigure = plot_uncoded(uncoded);
exportgraphics(uncodedFigure, fullfile(imageDirectory, ...
    "css-ber-polyphase-comparison.png"), "Resolution", 180);
writetable(uncoded, fullfile(dataDirectory, ...
    "css-ber-polyphase-comparison.csv"));

coded = run_coded(options.CodedSnrDb, options.CodedPacketsPerPoint, ...
    options.PayloadBytes);
codedFigure = plot_coded(coded);
exportgraphics(codedFigure, fullfile(imageDirectory, ...
    "lora-coded-ber-sf5-sf7-polyphase.png"), "Resolution", 180);
writetable(coded, fullfile(dataDirectory, ...
    "lora-coded-ber-sf5-sf7-polyphase.csv"));

settings = struct( ...
    "schema", "zynq-lora-ber-campaign-v1", ...
    "uncodedSymbolsPerPoint", options.UncodedSymbolsPerPoint, ...
    "codedPacketsPerPoint", options.CodedPacketsPerPoint, ...
    "payloadBytes", options.PayloadBytes, ...
    "uncodedSnrDb", options.UncodedSnrDb, ...
    "codedSnrDb", options.CodedSnrDb, ...
    "uncodedSeedBase", 70, ...
    "codedSeedBySf", [105; 106; 107], ...
    "confidenceInterval", "Wilson score, two-sided 95 percent");
save(fullfile(dataDirectory, "ber-polyphase-campaign.mat"), ...
    "uncoded", "coded", "settings");
campaign = struct("uncoded", uncoded, "coded", coded, ...
    "settings", settings, "uncodedFigure", uncodedFigure, ...
    "codedFigure", codedFigure);
end

function results = run_uncoded(snrDb, symbolsPerPoint)
rows = cell(0, 1);
samplesPerChipValues = [1, 2, 4, 8];
for samplesPerChip = samplesPerChipValues
    config = lora_phy.css_config(7, samplesPerChip);
    for combine = [false, true]
        item = lora_phy.simulate_uncoded_ber( ...
            snrDb, config, symbolsPerPoint, 70+samplesPerChip, combine);
        rows{end+1, 1} = item; %#ok<AGROW>
    end
end
results = vertcat(rows{:});
end

function results = run_coded(snrDb, packetsPerPoint, payloadBytes)
rows = cell(0, 1);
for sf = 5:7
    config = lora_phy.phy_config(sf, 8, 1);
    item = lora_phy.simulate_coded_ber(snrDb, config, ...
        packetsPerPoint, payloadBytes, 100+sf, true, true);
    rows{end+1, 1} = item; %#ok<AGROW>
end
results = vertcat(rows{:});
end

function figureHandle = plot_uncoded(results)
figureHandle = figure("Color", "white", "Position", [80, 80, 1180, 590]);
layout = tiledlayout(1, 2, "TileSpacing", "compact", ...
    "Padding", "compact");
colors = lines(4);
markers = ["o", "s", "^", "d"];
legendHandles = gobjects(0);
legendLabels = strings(0);
metrics = ["BER", "SER"];
for panel = 1:2
    axesHandle = nexttile(layout);
    hold(axesHandle, "on");
    for index = 1:4
        samplesPerChip = 2^(index-1);
        for combine = [false, true]
            mode = "single-phase";
            style = "--";
            if combine
                mode = "polyphase";
                style = "-";
            end
            selected = results.SamplesPerChip == samplesPerChip & ...
                results.DemodulationMode == mode;
            subset = results(selected, :);
            rate = subset.(metrics(panel));
            trials = subset.Bits;
            if metrics(panel) == "SER"
                trials = subset.Symbols;
            end
            shown = max(rate, 0.5./trials);
            lineHandle = semilogy(axesHandle, subset.SNR_dB, shown, ...
                style+markers(index), "Color", colors(index, :), ...
                "LineWidth", 1.35, "MarkerSize", 5);
            if panel == 1
                legendHandles(end+1) = lineHandle; %#ok<AGROW>
                legendLabels(end+1) = sprintf("L=%d %s", ...
                    samplesPerChip, mode); %#ok<AGROW>
            end
        end
    end
    grid(axesHandle, "on");
    set(axesHandle, "YScale", "log");
    xlabel(axesHandle, "SNR per complex sample, dB");
    ylabel(axesHandle, metrics(panel));
    title(axesHandle, "Uncoded "+metrics(panel)+", SF7");
    ylim(axesHandle, [1e-5, 1]);
end
legendHandle = legend(legendHandles, legendLabels, ...
    "Orientation", "horizontal", "NumColumns", 4);
legendHandle.Layout.Tile = "south";
title(layout, "Single-phase versus polyphase CSS demodulation");
end

function figureHandle = plot_coded(results)
figureHandle = figure("Color", "white", "Position", [80, 80, 1280, 540]);
layout = tiledlayout(1, 3, "TileSpacing", "compact", ...
    "Padding", "compact");
legendHandles = gobjects(0);
legendLabels = ["Pre-FEC BER", "Hard PER", "Soft PER", ...
    "Soft payload BER"];
colors = lines(4);
for sf = 5:7
    axesHandle = nexttile(layout);
    subset = results(results.SpreadingFactor == sf, :);
    hold(axesHandle, "on");
    values = {subset.PreFecBER, subset.HardPER, subset.SoftPER, ...
        subset.SoftPayloadBER};
    trials = {subset.PreFecBits, subset.Packets, subset.Packets, ...
        subset.PayloadBits};
    styles = ["o-", "s--", "^-", "d:"];
    for metric = 1:4
        shown = max(values{metric}, 0.5./trials{metric});
        handle = semilogy(axesHandle, subset.SNR_dB, shown, ...
            styles(metric), "Color", colors(metric, :), ...
            "LineWidth", 1.4, "MarkerSize", 5);
        if sf == 5
            legendHandles(end+1) = handle; %#ok<AGROW>
        end
    end
    grid(axesHandle, "on");
    set(axesHandle, "YScale", "log");
    xlabel(axesHandle, "SNR per complex sample, dB");
    ylabel(axesHandle, "Error probability");
    title(axesHandle, sprintf("SF%d, L=8, CR 4/5", sf));
    ylim(axesHandle, [1e-5, 1]);
end
legendHandle = legend(legendHandles, legendLabels, ...
    "Orientation", "horizontal", "NumColumns", 4);
legendHandle.Layout.Tile = "south";
title(layout, "Coded LoRa packet performance, 16-byte payload");
end
