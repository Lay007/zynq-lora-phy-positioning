function output = analyze_iq_capture( ...
    filePath, format, sampleRateHz, centreFrequencyHz, ...
    expectedFrequencyHz, outputDirectory)
%ANALYZE_IQ_CAPTURE Create unattended JSON, MAT, and PNG IQ-analysis reports.

arguments
    filePath (1,1) string
    format (1,1) string
    sampleRateHz (1,1) double {mustBePositive}
    centreFrequencyHz (1,1) double
    expectedFrequencyHz (1,1) double
    outputDirectory (1,1) string
end

[iq, fileInfo] = lora_phy.load_iq_capture(filePath, format);
result = lora_phy.inspect_iq_capture(iq, sampleRateHz);
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end
[~, captureName] = fileparts(filePath);
basePath = fullfile(outputDirectory, captureName + "-inspection");
pngPath = basePath + ".png";
matPath = basePath + ".mat";
jsonPath = basePath + ".json";

absoluteCarrierHz = centreFrequencyHz + result.estimatedCarrierOffsetHz;
if expectedFrequencyHz == 0
    cfoHz = result.residualCfoHz;
    cfoReference = "residual after estimated carrier removal";
else
    cfoHz = absoluteCarrierHz-expectedFrequencyHz;
    cfoReference = "expected transmitter frequency";
end

summary = struct;
summary.schema = "zynq-lora-iq-inspection-v1";
summary.capture_path = filePath;
summary.sample_format = fileInfo.format;
summary.sample_count = fileInfo.sampleCount;
summary.sample_rate_hz = sampleRateHz;
summary.centre_frequency_hz = centreFrequencyHz;
summary.expected_frequency_hz = expectedFrequencyHz;
summary.packet_start_seconds = result.packetStartSeconds;
summary.packet_end_seconds = result.packetEndSeconds;
summary.estimated_bandwidth_hz = result.estimatedBandwidthHz;
summary.measured_occupied_bandwidth_hz = result.measuredOccupiedBandwidthHz;
summary.estimated_spreading_factor = result.estimatedSpreadingFactor;
summary.estimated_symbol_duration_seconds = ...
    result.estimatedSymbolDurationSeconds;
summary.estimated_carrier_hz = absoluteCarrierHz;
summary.estimated_carrier_offset_hz = result.estimatedCarrierOffsetHz;
summary.cfo_hz = cfoHz;
summary.cfo_reference = cfoReference;
summary.estimated_snr_db = result.estimatedSnrDb;
summary.signal_power_db_relative = result.signalPowerDbRelative;
summary.noise_power_db_relative = result.noisePowerDbRelative;
summary.dc_offset_i = real(result.dcOffset);
summary.dc_offset_q = imag(result.dcOffset);
summary.iq_power_imbalance_db = result.iqPowerImbalanceDb;
summary.clipped_component_fraction = fileInfo.clippedComponentFraction;
summary.preamble_score = result.preambleScore;
summary.detected_fft_bins = result.detectedSymbols(:).';
summary.analysis_png = pngPath;
summary.analysis_mat = matPath;

jsonFile = fopen(jsonPath, "w");
if jsonFile < 0
    error("lora_phy:CannotCreateReport", ...
        "Cannot create analysis report: %s", jsonPath);
end
jsonCleanup = onCleanup(@() fclose(jsonFile));
fwrite(jsonFile, jsonencode(summary, PrettyPrint=true), "char");
fwrite(jsonFile, newline, "char");
clear jsonCleanup

figureHandle = figure( ...
    "Name", "LoRa PHY inspection: " + captureName, ...
    "Visible", "off", "Position", [100 100 1500 850]);
figureCleanup = onCleanup(@() close(figureHandle));
layout = tiledlayout(figureHandle, 2, 2, ...
    "TileSpacing", "compact", "Padding", "compact");

overviewAxes = nexttile(layout);
spec = result.spectrogram;
imagesc(overviewAxes, spec.timeSeconds*1e3, spec.frequencyHz/1e3, spec.powerDb);
axis(overviewAxes, "xy"); colorbar(overviewAxes);
xlabel(overviewAxes, "Time, ms"); ylabel(overviewAxes, "Offset frequency, kHz");
title(overviewAxes, "Capture spectrogram");
hold(overviewAxes, "on");
xline(overviewAxes, result.packetStartSeconds*1e3, "w--", "start");
xline(overviewAxes, result.packetEndSeconds*1e3, "w--", "end");
hold(overviewAxes, "off");

packetAxes = nexttile(layout);
indices = result.packetStartIndex:result.packetEndIndex;
timeMs = (indices-result.packetStartIndex)/sampleRateHz*1e3;
packet = iq(indices);
yyaxis(packetAxes, "left");
plot(packetAxes, timeMs, abs(packet), "Color", [0.1 0.45 0.85]);
ylabel(packetAxes, "Magnitude");
yyaxis(packetAxes, "right");
instantFrequency = [NaN; angle(packet(2:end).*conj(packet(1:end-1))) ...
    *sampleRateHz/(2*pi)]/1e3;
plot(packetAxes, timeMs, instantFrequency, ".", ...
    "MarkerSize", 3, "Color", [0.85 0.3 0.15]);
ylabel(packetAxes, "Instantaneous frequency, kHz");
xlabel(packetAxes, "Time from burst start, ms");
title(packetAxes, sprintf("Strongest burst: SF%d, BW %.0f kHz", ...
    result.estimatedSpreadingFactor, result.estimatedBandwidthHz/1e3));
grid(packetAxes, "on");

spectrumAxes = nexttile(layout);
plot(spectrumAxes, result.averageSpectrumFrequencyHz/1e3, ...
    result.averageSpectrumPowerDb, "LineWidth", 1);
xlabel(spectrumAxes, "Offset frequency, kHz");
ylabel(spectrumAxes, "Power, dB relative");
title(spectrumAxes, sprintf("Carrier %.6f MHz, SNR %.1f dB", ...
    absoluteCarrierHz/1e6, result.estimatedSnrDb));
grid(spectrumAxes, "on"); hold(spectrumAxes, "on");
carrierKhz = result.estimatedCarrierOffsetHz/1e3;
halfBwKhz = result.estimatedBandwidthHz/2e3;
xline(spectrumAxes, carrierKhz, "r-", "carrier");
xline(spectrumAxes, carrierKhz-halfBwKhz, "k--");
xline(spectrumAxes, carrierKhz+halfBwKhz, "k--");
hold(spectrumAxes, "off");

dechirpAxes = nexttile(layout);
imagesc(dechirpAxes, 0:2^result.estimatedSpreadingFactor-1, ...
    1:result.analyzedSymbolCount, result.dechirpedFftPowerDb, [-35 0]);
axis(dechirpAxes, "xy"); colorbar(dechirpAxes);
xlabel(dechirpAxes, "FFT bin / hard symbol decision");
ylabel(dechirpAxes, "Symbol in time");
title(dechirpAxes, "Dechirped FFT by symbol");

exportgraphics(figureHandle, pngPath, "Resolution", 150);
save(matPath, "result", "summary", "fileInfo");

output = struct;
output.summary = summary;
output.result = result;
output.pngPath = pngPath;
output.matPath = matPath;
output.jsonPath = jsonPath;
end
