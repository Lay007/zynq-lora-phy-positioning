function report = run_m1_acceptance(options)
%RUN_M1_ACCEPTANCE Reproduce end-to-end floating-point receiver evidence.

arguments
    options.PacketsPerSensitivityPoint (1,1) double ...
        {mustBeInteger, mustBePositive} = 20
    options.PacketsPerMode (1,1) double ...
        {mustBeInteger, mustBePositive} = 2
    options.PacketsPerImpairment (1,1) double ...
        {mustBeInteger, mustBePositive} = 5
    options.TdoaTrialsPerPoint (1,1) double ...
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

spreadingFactors = [5, 7, 9];
snrGrids = {[-14; -12; -10; -8], ...
    [-18; -16; -14; -12], [-24; -22; -20; -18]};
sensitivity = table;
for index = 1:numel(spreadingFactors)
    sf = spreadingFactors(index);
    config = lora_phy.phy_config(sf, 8, 1);
    config.lowDataRateOptimization = 2^sf/125e3 >= 16e-3;
    current = lora_phy.simulate_lora_stream_performance( ...
        snrGrids{index}, config, ...
        PacketsPerPoint=options.PacketsPerSensitivityPoint, ...
        PayloadLength=16, RandomSeed=2000+sf);
    sensitivity = [sensitivity; current]; %#ok<AGROW>
    fprintf("M1 sensitivity SF%d complete\n", sf);
end

modeCoverage = run_lora_mode_coverage( ...
    PacketsPerMode=options.PacketsPerMode, ...
    OutputDirectory=options.OutputDirectory);

impairments = table;
config = lora_phy.phy_config(7, 8, 2);
caseNames = ["baseline"; "cfo-sfo"; "multipath-timing"; "front-end-adc"];
caseResults = cell(numel(caseNames), 1);
caseResults{1} = lora_phy.simulate_lora_stream_performance( ...
    -10, config, PacketsPerPoint=options.PacketsPerImpairment, ...
    PayloadLength=20, RandomSeed=4001);
caseResults{2} = lora_phy.simulate_lora_stream_performance( ...
    -8, config, PacketsPerPoint=options.PacketsPerImpairment, ...
    PayloadLength=20, RandomSeed=4002, FrequencyOffsetHz=1500, ...
    SampleRateOffsetPpm=20, FractionalDelaySamples=1.75);
caseResults{3} = lora_phy.simulate_lora_stream_performance( ...
    -8, config, PacketsPerPoint=options.PacketsPerImpairment, ...
    PayloadLength=20, RandomSeed=4003, ...
    FractionalDelaySamples=1.75, MultipathDelaysSamples=[0; 3.5], ...
    MultipathGains=[1; 0.2j]);
caseResults{4} = lora_phy.simulate_lora_stream_performance( ...
    -8, config, PacketsPerPoint=options.PacketsPerImpairment, ...
    PayloadLength=20, RandomSeed=4004, IqGainImbalanceDb=0.5, ...
    IqPhaseImbalanceDegrees=2, DcOffset=0.02, ...
    AdcFullScale=2, AdcBits=12);
for index = 1:numel(caseNames)
    current = caseResults{index};
    current.Case = repmat(caseNames(index), height(current), 1);
    current = movevars(current, "Case", "Before", 1);
    impairments = [impairments; current]; %#ok<AGROW>
end

tdoa = run_tdoa_acceptance( ...
    TrialsPerPoint=options.TdoaTrialsPerPoint, ...
    OutputDirectory=options.OutputDirectory, ...
    ImageDirectory=options.ImageDirectory);

writetable(sensitivity, fullfile(options.OutputDirectory, ...
    "lora-end-to-end-sensitivity.csv"));
writetable(impairments, fullfile(options.OutputDirectory, ...
    "lora-end-to-end-impairments.csv"));
figureHandle = plot_sensitivity(sensitivity);
exportgraphics(figureHandle, fullfile(options.ImageDirectory, ...
    "lora-end-to-end-sensitivity.png"), "Resolution", 180);
close(figureHandle);

report = struct("schema", "zynq-lora-m1-acceptance-v1", ...
    "sensitivity", sensitivity, "modeCoverage", modeCoverage, ...
    "impairments", impairments, "tdoa", tdoa);
save(fullfile(options.OutputDirectory, "lora-m1-acceptance.mat"), ...
    "report");
end

function figureHandle = plot_sensitivity(results)
figureHandle = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 1200, 520]);
layout = tiledlayout(1, 2, "TileSpacing", "compact", ...
    "Padding", "compact");
spreadingFactors = unique(results.SpreadingFactor).';
colours = lines(numel(spreadingFactors));
nexttile;
hold on;
for index = 1:numel(spreadingFactors)
    rows = results.SpreadingFactor == spreadingFactors(index);
    plot(results.SNR_dB(rows), results.DetectionProbability(rows), ...
        "-o", "LineWidth", 1.8, "Color", colours(index, :), ...
        "DisplayName", sprintf("SF%d", spreadingFactors(index)));
end
grid on;
ylim([-0.05, 1.05]);
xlabel("SNR per complex sample, dB");
ylabel("Acquisition probability");
title("Configured preamble acquisition");
legend("Location", "southeast");

nexttile;
hold on;
for index = 1:numel(spreadingFactors)
    rows = results.SpreadingFactor == spreadingFactors(index);
    trials = results.Transmissions(rows);
    displayPer = max(results.PER(rows), 0.5./trials);
    semilogy(results.SNR_dB(rows), displayPer, "-o", ...
        "LineWidth", 1.8, "Color", colours(index, :), ...
        "DisplayName", sprintf("SF%d", spreadingFactors(index)));
end
grid on;
xlabel("SNR per complex sample, dB");
ylabel("Packet error rate");
title("End-to-end PER");
legend("Location", "southwest");
title(layout, "Floating-point LoRa stream receiver, L=8, CR 4/5");
end
