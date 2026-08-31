function [result, figureHandle] = plot_reference_chirps(outputPath)
%PLOT_REFERENCE_CHIRPS Visualize the floating-point CSS chirp reference.
%
% The figure compares one upchirp and one downchirp using the same
% lora_phy.reference_chirp implementation that feeds the MATLAB modem model.
% It shows I/Q samples, unwrapped phase, instantaneous frequency, and spectrum.

rootDirectory = fileparts(fileparts(mfilename("fullpath")));
addpath(rootDirectory);

if nargin < 1
    repositoryRoot = fileparts(fileparts(rootDirectory));
    outputPath = fullfile(repositoryRoot, "docs", "images", ...
        "css-reference-chirps-sf7-bw125.png");
end

config = lora_phy.css_config(7, 4);
bandwidthHz = 125e3;
sampleRateHz = bandwidthHz * config.samplesPerChip;

upchirp = lora_phy.reference_chirp(config, "up");
downchirp = lora_phy.reference_chirp(config, "down");

sampleCount = config.samplesPerSymbol;
timeMs = (0:sampleCount-1).' / sampleRateHz * 1e3;
frequencyTimeMs = ((0:sampleCount-2).' + 0.5) / sampleRateHz * 1e3;

upPhaseCycles = unwrap(angle(upchirp)) / (2*pi);
downPhaseCycles = unwrap(angle(downchirp)) / (2*pi);

upPhaseStep = angle(upchirp(2:end) .* conj(upchirp(1:end-1)));
downPhaseStep = angle(downchirp(2:end) .* conj(downchirp(1:end-1)));
upFrequencyKhz = upPhaseStep * sampleRateHz / (2*pi*1e3);
downFrequencyKhz = downPhaseStep * sampleRateHz / (2*pi*1e3);

fftLength = 2^nextpow2(8 * sampleCount);
frequencyAxisKhz = (-fftLength/2:fftLength/2-1).' ...
    * sampleRateHz / fftLength / 1e3;
upSpectrum = fftshift(fft(upchirp, fftLength));
downSpectrum = fftshift(fft(downchirp, fftLength));
upSpectrumDb = 20*log10(abs(upSpectrum) / max(abs(upSpectrum)) + eps);
downSpectrumDb = 20*log10(abs(downSpectrum) / max(abs(downSpectrum)) + eps);

figureHandle = figure("Color", "white", "Position", [100, 100, 1180, 920]);
tiledlayout(4, 2, "TileSpacing", "compact", "Padding", "compact");

nexttile;
plot(timeMs, real(upchirp), "LineWidth", 1.0);
hold on;
plot(timeMs, imag(upchirp), "LineWidth", 1.0);
grid on;
xlabel("Time, ms");
ylabel("Amplitude");
title("Upchirp: I/Q");
legend("I", "Q", "Location", "best");

nexttile;
plot(timeMs, real(downchirp), "LineWidth", 1.0);
hold on;
plot(timeMs, imag(downchirp), "LineWidth", 1.0);
grid on;
xlabel("Time, ms");
ylabel("Amplitude");
title("Downchirp: I/Q");
legend("I", "Q", "Location", "best");

nexttile;
plot(timeMs, upPhaseCycles, "LineWidth", 1.1);
grid on;
xlabel("Time, ms");
ylabel("Phase, cycles");
title("Upchirp: unwrapped phase");

nexttile;
plot(timeMs, downPhaseCycles, "LineWidth", 1.1);
grid on;
xlabel("Time, ms");
ylabel("Phase, cycles");
title("Downchirp: unwrapped phase");

nexttile;
plot(frequencyTimeMs, upFrequencyKhz, "LineWidth", 1.1);
grid on;
xlabel("Time, ms");
ylabel("Frequency, kHz");
title("Upchirp: instantaneous frequency");
ylim(0.6 * [-bandwidthHz, bandwidthHz] / 1e3);

nexttile;
plot(frequencyTimeMs, downFrequencyKhz, "LineWidth", 1.1);
grid on;
xlabel("Time, ms");
ylabel("Frequency, kHz");
title("Downchirp: instantaneous frequency");
ylim(0.6 * [-bandwidthHz, bandwidthHz] / 1e3);

nexttile;
plot(frequencyAxisKhz, upSpectrumDb, "LineWidth", 1.0);
grid on;
xlabel("Frequency, kHz");
ylabel("Relative magnitude, dB");
title("Upchirp: spectrum");
ylim([-80, 5]);

nexttile;
plot(frequencyAxisKhz, downSpectrumDb, "LineWidth", 1.0);
grid on;
xlabel("Frequency, kHz");
ylabel("Relative magnitude, dB");
title("Downchirp: spectrum");
ylim([-80, 5]);

sgtitle(sprintf("CSS reference chirps: SF%d, BW %.0f kHz, Fs %.0f kHz, %d samples/chip", ...
    config.spreadingFactor, bandwidthHz/1e3, sampleRateHz/1e3, ...
    config.samplesPerChip));

outputDirectory = fileparts(outputPath);
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end
exportgraphics(figureHandle, outputPath, "Resolution", 160);

result = struct;
result.config = config;
result.bandwidthHz = bandwidthHz;
result.sampleRateHz = sampleRateHz;
result.timeMs = timeMs;
result.frequencyTimeMs = frequencyTimeMs;
result.upchirp = upchirp;
result.downchirp = downchirp;
result.upPhaseCycles = upPhaseCycles;
result.downPhaseCycles = downPhaseCycles;
result.upFrequencyKhz = upFrequencyKhz;
result.downFrequencyKhz = downFrequencyKhz;
result.frequencyAxisKhz = frequencyAxisKhz;
result.upSpectrumDb = upSpectrumDb;
result.downSpectrumDb = downSpectrumDb;
result.outputPath = outputPath;
end
