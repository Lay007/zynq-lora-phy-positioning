function [result, figureHandle] = plot_frame_acquisition(outputPath)
%PLOT_FRAME_ACQUISITION Visualize chirp, timing score, and payload FFT.

rootDirectory = fileparts(fileparts(mfilename("fullpath")));
addpath(rootDirectory);
if nargin < 1
    repositoryRoot = fileparts(fileparts(rootDirectory));
    outputPath = fullfile( ...
        repositoryRoot, "docs", "images", "css-frame-acquisition-sf7.png");
end

config = lora_phy.css_config(7, 2);
bandwidthHz = 125e3;
sampleRateHz = bandwidthHz * config.samplesPerChip;
payload = [0; 3; 17; 42; 92; 127];
[frame, frameInfo] = lora_phy.build_css_frame(payload, config);
trueCfoHz = 180;
impaired = lora_phy.apply_frequency_offset( ...
    frame, trueCfoHz / sampleRateHz, 0.4);
impaired = lora_phy.add_awgn(impaired, 8, 19);
leadingSamples = 73;
capture = [zeros(leadingSamples, 1); impaired; zeros(40, 1)];
result = lora_phy.receive_css_frame( ...
    capture, numel(payload), config);

upchirp = lora_phy.reference_chirp(config);
timeMs = (0:config.samplesPerSymbol-1).' / sampleRateHz * 1e3;
instantaneousFrequencyKhz = [NaN; diff(unwrap(angle(upchirp)))] / ...
    (2*pi) * sampleRateHz / 1e3;
payloadSamples = capture(result.payloadStartIndex: ...
    result.payloadStartIndex+config.samplesPerSymbol-1);
n = (0:config.samplesPerSymbol-1).';
compensated = payloadSamples .* exp(-2j*pi*result.frequencyOffset*n);
dechirped = compensated .* conj(upchirp);
spectrum = abs(fft(dechirped(1:config.samplesPerChip:end))).^2;
spectrumDb = 10*log10(spectrum / max(spectrum) + eps);

figureHandle = figure("Color", "white", "Position", [100, 100, 1000, 700]);
tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");

nexttile;
plot(timeMs, real(upchirp), "DisplayName", "I");
hold on;
plot(timeMs, imag(upchirp), "DisplayName", "Q");
grid on;
xlabel("Time, ms");
ylabel("Amplitude");
title("Reference upchirp");
legend("Location", "best");

nexttile;
plot(timeMs, instantaneousFrequencyKhz, "LineWidth", 1.2);
grid on;
xlabel("Time, ms");
ylabel("Instantaneous frequency, kHz");
title(sprintf("BW = %.0f kHz", bandwidthHz/1e3));

nexttile;
diagnostics = result.detectorDiagnostics;
plot(diagnostics.candidateStartIndices-1, diagnostics.scores, ...
    "LineWidth", 1.2);
hold on;
xline(result.startIndex-1, "--", "Detected start");
xline(leadingSamples, ":", "True start");
grid on;
xlabel("Candidate start, samples");
ylabel("Normalized score");
title(sprintf("Preamble acquisition, score %.3f", result.detectionScore));

nexttile;
plot(0:config.symbolCount-1, spectrumDb, "LineWidth", 1.2);
hold on;
xline(payload(1), "--", sprintf("Detected symbol %d", result.symbols(1)));
grid on;
xlabel("FFT bin / symbol index");
ylabel("Relative power, dB");
title(sprintf("Dechirped payload FFT, CFO estimate %.1f Hz", ...
    result.frequencyOffset * sampleRateHz));
ylim([-60, 5]);

sgtitle(sprintf("CSS frame: %d+%d preamble chirps, %d payload symbols", ...
    frameInfo.upchirpCount, frameInfo.downchirpCount, numel(payload)));

outputDirectory = fileparts(outputPath);
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end
exportgraphics(figureHandle, outputPath, "Resolution", 160);
end
