function [result, figureHandle] = plot_symbol_demodulation(outputPath)
%PLOT_SYMBOL_DEMODULATION Show chirp, dechirp, and FFT for CSS symbols.

rootDirectory = fileparts(fileparts(mfilename("fullpath")));
addpath(rootDirectory);
if nargin < 1
    repositoryRoot = fileparts(fileparts(rootDirectory));
    outputPath = fullfile(repositoryRoot, "docs", "images", ...
        "css-symbol-demodulation-sf7.png");
end

config = lora_phy.css_config(7, 4);
bandwidthHz = 125e3;
sampleRateHz = bandwidthHz * config.samplesPerChip;
symbols = [0; 1; 17; 42; 92; 127];
snrDb = -8;
symbolCount = numel(symbols);
sampleTimeMs = (0:config.samplesPerSymbol-1).' / sampleRateHz * 1e3;
chipIndex = (0:config.symbolCount-1).';
reference = lora_phy.reference_chirp(config);

instantaneousFrequencyKhz = zeros(config.samplesPerSymbol-1, symbolCount);
dechirpedPhaseCycles = zeros(config.symbolCount, symbolCount);
spectrumDb = zeros(symbolCount, config.symbolCount);
detected = zeros(symbolCount, 1);

for index = 1:symbolCount
    clean = lora_phy.modulate_symbol(symbols(index), config);
    phaseStep = angle(clean(2:end) .* conj(clean(1:end-1)));
    instantaneousFrequencyKhz(:, index) = ...
        phaseStep * sampleRateHz / (2*pi*1e3);

    cleanDechirped = clean .* conj(reference);
    chipRateClean = cleanDechirped(1:config.samplesPerChip:end);
    phase = unwrap(angle(chipRateClean));
    dechirpedPhaseCycles(:, index) = (phase-phase(1))/(2*pi);

    noisy = lora_phy.add_awgn(clean, snrDb, 100+index);
    noisyDechirped = noisy .* conj(reference);
    chipRateNoisy = noisyDechirped(1:config.samplesPerChip:end);
    power = abs(fft(chipRateNoisy)).^2;
    spectrumDb(index, :) = 10*log10(power/max(power) + eps);
    detected(index) = lora_phy.demodulate_symbol(noisy, config);
end

figureHandle = figure("Color", "white", "Position", [100, 100, 1050, 760]);
tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");

nexttile;
plot(sampleTimeMs(1:end-1), instantaneousFrequencyKhz, "LineWidth", 1.0);
grid on;
xlabel("Time, ms");
ylabel("Instantaneous frequency, kHz");
title("1. Cyclically shifted upchirps");
legend(compose("symbol %d", symbols), "Location", "eastoutside");

nexttile;
plot(chipIndex, dechirpedPhaseCycles, "LineWidth", 1.1);
grid on;
xlabel("Chip index");
ylabel("Unwrapped phase, cycles");
title("2. Dechirp converts each chirp to a tone");
legend(compose("symbol %d", symbols), "Location", "eastoutside");

nexttile([1, 2]);
imagesc(0:config.symbolCount-1, 1:symbolCount, spectrumDb);
set(gca, "YDir", "normal", "YTick", 1:symbolCount, ...
    "YTickLabel", compose("TX %d  ->  RX %d", symbols, detected));
xlabel("FFT bin");
ylabel("Symbol decision");
title(sprintf("3. Dechirped FFT at %.0f dB sample SNR", snrDb));
colorbarHandle = colorbar;
colorbarHandle.Label.String = "Relative power, dB";
clim([-35, 0]);
hold on;
plot(symbols, 1:symbolCount, "wo", "MarkerSize", 8, "LineWidth", 1.2);

sgtitle(sprintf("CSS symbol demodulation: SF%d, BW %.0f kHz, %d samples/chip", ...
    config.spreadingFactor, bandwidthHz/1e3, config.samplesPerChip));

outputDirectory = fileparts(outputPath);
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end
exportgraphics(figureHandle, outputPath, "Resolution", 160);

result = struct;
result.config = config;
result.bandwidthHz = bandwidthHz;
result.sampleRateHz = sampleRateHz;
result.snrDb = snrDb;
result.transmittedSymbols = symbols;
result.detectedSymbols = detected;
result.spectrumDb = spectrumDb;
end
