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
uncodedFigure = plot_uncoded_current_vs_ideal(uncoded);
exportgraphics(uncodedFigure, fullfile(imageDirectory, ...
    "css-ber-current-vs-ideal.png"), "Resolution", 180);
writetable(uncoded, fullfile(dataDirectory, ...
    "css-ber-demodulator-comparison.csv"));

idealGap = summarize_ideal_gap(uncoded, [1e-2; 1e-3]);
idealGapFigure = plot_ideal_gap(idealGap);
exportgraphics(idealGapFigure, fullfile(imageDirectory, ...
    "css-ber-ideal-gap.png"), "Resolution", 180);
writetable(idealGap, fullfile(dataDirectory, "css-ber-ideal-gap.csv"));

coded = run_coded(options.CodedSnrDb, options.CodedPacketsPerPoint, ...
    options.PayloadBytes);
codedFigure = plot_coded(coded);
exportgraphics(codedFigure, fullfile(imageDirectory, ...
    "lora-coded-ber-sf5-sf7-polyphase.png"), "Resolution", 180);
writetable(coded, fullfile(dataDirectory, ...
    "lora-coded-ber-sf5-sf7-polyphase.csv"));

settings = struct( ...
    "schema", "zynq-lora-ber-campaign-v2", ...
    "uncodedSymbolsPerPoint", options.UncodedSymbolsPerPoint, ...
    "codedPacketsPerPoint", options.CodedPacketsPerPoint, ...
    "payloadBytes", options.PayloadBytes, ...
    "uncodedSnrDb", options.UncodedSnrDb, ...
    "codedSnrDb", options.CodedSnrDb, ...
    "uncodedSeedBase", 70, ...
    "codedSeedBySf", [105; 106; 107], ...
    "confidenceInterval", "Wilson score, two-sided 95 percent");
save(fullfile(dataDirectory, "ber-polyphase-campaign.mat"), ...
    "uncoded", "coded", "idealGap", "settings");
campaign = struct("uncoded", uncoded, "coded", coded, ...
    "idealGap", idealGap, ...
    "settings", settings, "uncodedFigure", uncodedFigure, ...
    "idealGapFigure", idealGapFigure, "codedFigure", codedFigure);
end

function results = run_uncoded(snrDb, symbolsPerPoint)
rows = cell(0, 1);
samplesPerChipValues = [1, 2, 4, 8];
for samplesPerChip = samplesPerChipValues
    config = lora_phy.css_config(7, samplesPerChip);
    modes = ["single-phase", "polyphase", "matched-filter"];
    for mode = modes
        item = lora_phy.simulate_uncoded_ber( ...
            snrDb, config, symbolsPerPoint, 70+samplesPerChip, mode);
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

function figureHandle = plot_uncoded_current_vs_ideal(results)
figureHandle = figure("Color", "white", "Position", [80, 80, 1180, 820]);
layout = tiledlayout(2, 2, "TileSpacing", "compact", ...
    "Padding", "compact");
colors = lines(3);
markers = ["o", "s", "^"];
styles = ["--", "-", "-."];
legendHandles = gobjects(0);
legendLabels = ["Legacy single phase", "Current polyphase", ...
    "Ideal coherent matched filter"];
samplesPerChipValues = [1, 2, 4, 8];
modes = ["single-phase", "polyphase", "matched-filter"];
for panel = 1:4
    axesHandle = nexttile(layout);
    hold(axesHandle, "on");
    samplesPerChip = samplesPerChipValues(panel);
    for index = 1:3
        selected = results.SamplesPerChip == samplesPerChip & ...
            results.DemodulationMode == modes(index);
        subset = results(selected, :);
        shown = max(subset.BER, 0.5./subset.Bits);
        lineHandle = semilogy(axesHandle, subset.SNR_dB, shown, ...
            styles(index)+markers(index), "Color", colors(index, :), ...
            "LineWidth", 1.35, "MarkerSize", 5);
        if panel == 1
            legendHandles(end+1) = lineHandle; %#ok<AGROW>
        end
    end
    grid(axesHandle, "on");
    set(axesHandle, "YScale", "log");
    xlabel(axesHandle, "SNR per complex sample, dB");
    ylabel(axesHandle, "BER");
    title(axesHandle, sprintf("SF7, L=%d", samplesPerChip));
    ylim(axesHandle, [1e-5, 1]);
end
legendHandle = legend(legendHandles, legendLabels, ...
    "Orientation", "horizontal", "NumColumns", 3);
legendHandle.Layout.Tile = "south";
title(layout, "Current CSS demodulator versus coherent reference");
end

function summary = summarize_ideal_gap(results, targets)
rows = cell(0, 1);
for samplesPerChip = [1, 2, 4, 8]
    current = results(results.SamplesPerChip == samplesPerChip & ...
        results.DemodulationMode == "polyphase", :);
    ideal = results(results.SamplesPerChip == samplesPerChip & ...
        results.DemodulationMode == "matched-filter", :);
    for target = targets(:).'
        currentThreshold = estimate_threshold(current, target);
        idealThreshold = estimate_threshold(ideal, target);
        rows{end+1, 1} = table(samplesPerChip, target, ...
            currentThreshold, idealThreshold, ...
            currentThreshold-idealThreshold, ...
            'VariableNames', {'SamplesPerChip', 'TargetBER', ...
            'PolyphaseSNR_dB', 'MatchedFilterSNR_dB', 'Gap_dB'}); %#ok<AGROW>
    end
end
summary = vertcat(rows{:});
end

function threshold = estimate_threshold(results, target)
[snrDb, order] = sort(results.SNR_dB);
shown = max(results.BER(order), 0.5./results.Bits(order));
crossing = find(shown(1:end-1) >= target & ...
    shown(2:end) <= target, 1, "first");
if isempty(crossing)
    threshold = NaN;
    return
end
x = log10(shown(crossing:crossing+1));
threshold = interp1(x, snrDb(crossing:crossing+1), ...
    log10(target), "linear");
end

function figureHandle = plot_ideal_gap(results)
figureHandle = figure("Color", "white", "Position", [80, 80, 780, 500]);
axesHandle = axes(figureHandle);
hold(axesHandle, "on");
targets = unique(results.TargetBER, "stable");
colors = lines(numel(targets));
markers = ["o", "s"];
legendHandles = gobjects(0);
legendLabels = strings(0);
for index = 1:numel(targets)
    subset = results(results.TargetBER == targets(index), :);
    valid = isfinite(subset.Gap_dB);
    legendHandles(end+1) = plot(axesHandle, ...
        subset.SamplesPerChip(valid), subset.Gap_dB(valid), ...
        "-"+markers(index), "Color", colors(index, :), ...
        "LineWidth", 1.5, "MarkerSize", 6); %#ok<AGROW>
    legendLabels(end+1) = sprintf("BER = %g", targets(index)); %#ok<AGROW>
end
grid(axesHandle, "on");
xticks(axesHandle, [1, 2, 4, 8]);
xlabel(axesHandle, "Samples per chip, L");
ylabel(axesHandle, "Polyphase penalty to matched filter, dB");
title(axesHandle, "Measured loss from the coherent CSS reference");
legend(legendHandles, legendLabels, "Location", "northwest");
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
