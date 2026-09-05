function app = lora_phy_inspector(visible)
%LORA_PHY_INSPECTOR Visual inspection and verification for IQ recordings.

if nargin < 1
    visible = "on";
end
matlabRoot = fileparts(fileparts(mfilename("fullpath")));
addpath(matlabRoot);

figureHandle = uifigure( ...
    "Name", "LoRa PHY Inspector", ...
    "Position", [80 50 1440 900], ...
    "Visible", visible);
mainGrid = uigridlayout(figureHandle, [3 1]);
mainGrid.RowHeight = {104, "1x", 210};
mainGrid.Padding = [10 10 10 10];

controls = uigridlayout(mainGrid, [2 8]);
controls.Layout.Row = 1;
controls.ColumnWidth = {"1x", 90, 78, 125, 120, 145, 120, 110};
controls.RowHeight = {24, 34};
fileLabel = uilabel(controls, "Text", "IQ recording", "FontWeight", "bold");
fileLabel.Layout.Column = 1;
formatLabel = uilabel(controls, "Text", "Format", "FontWeight", "bold");
formatLabel.Layout.Column = 3;
sampleRateLabel = uilabel(controls, "Text", "Sample rate, Hz", "FontWeight", "bold");
sampleRateLabel.Layout.Column = 4;
centreLabel = uilabel(controls, "Text", "Center frequency, Hz", "FontWeight", "bold");
centreLabel.Layout.Column = 5;
expectedLabel = uilabel(controls, "Text", "Expected carrier, Hz", "FontWeight", "bold");
expectedLabel.Layout.Column = 6;
statusLabel = uilabel(controls, ...
    "Text", "Select an IQ or HDL simulation recording");
statusLabel.Layout.Row = 1;
statusLabel.Layout.Column = [7 8];

fileField = uieditfield(controls, "text", ...
    "Placeholder", "capture.cu8, capture.cf32 or hdl_*.pcm");
fileField.Layout.Row = 2;
fileField.Layout.Column = 1;
browseButton = uibutton(controls, "Text", "Browse…", ...
    "ButtonPushedFcn", @browse_file);
browseButton.Layout.Row = 2;
browseButton.Layout.Column = 2;
formatDropDown = uidropdown(controls, ...
    "Items", ["auto", "cu8", "cf32", "ci16"], "Value", "auto");
formatDropDown.Layout.Row = 2;
formatDropDown.Layout.Column = 3;
sampleRateField = uieditfield(controls, "numeric", "Value", 1e6, "Limits", [1 Inf]);
sampleRateField.Layout.Row = 2;
sampleRateField.Layout.Column = 4;
centreField = uieditfield(controls, "numeric", "Value", 868.35e6, "Limits", [0 Inf], ...
    "Tooltip", "Set to 0 for a baseband-only recording with no RF center");
centreField.Layout.Row = 2;
centreField.Layout.Column = 5;
expectedField = uieditfield(controls, "numeric", "Value", 0, ...
    "Tooltip", "0 = unknown; otherwise used to estimate CFO");
expectedField.Layout.Row = 2;
expectedField.Layout.Column = 6;
analyzeButton = uibutton(controls, "Text", "Analyze", ...
    "FontWeight", "bold", "ButtonPushedFcn", @analyze_file);
analyzeButton.Layout.Row = 2;
analyzeButton.Layout.Column = 7;
exportButton = uibutton(controls, "Text", "Save PNG", ...
    "Enable", "off", "ButtonPushedFcn", @export_png);
exportButton.Layout.Row = 2;
exportButton.Layout.Column = 8;

plots = uigridlayout(mainGrid, [2 2]);
plots.Layout.Row = 2;
overviewAxes = uiaxes(plots); title(overviewAxes, "Full recording: spectrogram");
packetAxes = uiaxes(plots); title(packetAxes, "Detected CSS/LoRa burst");
spectrumAxes = uiaxes(plots); title(spectrumAxes, "Average spectrum");
dechirpAxes = uiaxes(plots); title(dechirpAxes, "Per-symbol dechirped FFT");

bottom = uigridlayout(mainGrid, [1 2]);
bottom.Layout.Row = 3;
bottom.ColumnWidth = {"2.4x", "1x"};
resultTable = uitable(bottom, ...
    "ColumnName", {'Parameter', 'Estimate', 'Verification / notes'}, ...
    "ColumnWidth", {210, 220, "auto"}, ...
    "Data", cell(0, 3));
symbolArea = uitextarea(bottom, "Editable", "off", ...
    "Value", "Detected symbol indices and golden metrics will appear here.", ...
    "FontName", "Consolas");

app = struct;
app.Figure = figureHandle;
app.FileField = fileField;
app.FormatDropDown = formatDropDown;
app.SampleRateField = sampleRateField;
app.CentreFrequencyField = centreField;
app.ExpectedFrequencyField = expectedField;
app.ResultTable = resultTable;
app.SymbolArea = symbolArea;
app.Analyze = @run_analysis;

    function browse_file(~, ~)
        [name, folder] = uigetfile( ...
            {"*.cu8;*.uc8;*.cf32;*.fc32;*.cfile;*.pcm;*.ci16;*.sc16", "IQ recordings"; ...
            "*.*", "All files"});
        if ~isequal(name, 0)
            fileField.Value = fullfile(folder, name);
        end
    end

    function analyze_file(~, ~)
        try
            run_analysis();
        catch exception
            statusLabel.Text = "Analysis failed";
            uialert(figureHandle, exception.message, ...
                "Could not process the recording");
        end
    end

    function result = run_analysis()
        statusLabel.Text = "Reading and analyzing…";
        drawnow;
        [iq, fileInfo] = lora_phy.load_iq_capture(fileField.Value, formatDropDown.Value);
        fs = sampleRateField.Value;
        result = lora_phy.inspect_iq_capture(iq, fs);

        profile = lora_phy.match_lora_profile( ...
            result.estimatedSpreadingFactor, result.estimatedBandwidthHz, ...
            centreField.Value);
        [golden, hdlMetadata] = try_golden_verification(iq, fileInfo, result);

        render_result(iq, result, fileInfo, profile, golden, hdlMetadata);
        exportButton.Enable = "on";
        if isempty(golden)
            statusLabel.Text = sprintf("Done: %s, %d samples", ...
                upper(fileInfo.format), fileInfo.sampleCount);
        else
            verdict = "WARN";
            if golden.passed
                verdict = "PASS";
            end
            statusLabel.Text = sprintf("Done: %s, golden %s", ...
                upper(fileInfo.format), verdict);
        end
    end

    function [golden, metadata] = try_golden_verification(iq, fileInfo, result)
        golden = [];
        metadata = [];
        if string(fileInfo.format) ~= "ci16"
            return
        end

        [~, baseName, extension] = fileparts(fileInfo.filePath);
        fullName = lower(string(baseName) + string(extension));
        if isempty(regexp(fullName, ...
                "^hdl_sf[0-9]+_bw[0-9]+k_fs[0-9]+k_[a-z0-9-]+\.pcm$", ...
                "once"))
            return
        end

        metadata = lora_phy.parse_hdl_recording_name(fileInfo.filePath);
        if abs(metadata.sampleRateHz-sampleRateField.Value) > 0.5
            error("lora_phy:HdlSampleRateMismatch", ...
                "Inspector Fs does not match the sample rate encoded in the HDL filename");
        end

        golden = lora_phy.compare_iq_to_golden( ...
            iq, metadata.sampleRateHz, metadata.spreadingFactor, metadata.bandwidthHz, ...
            StartIndex=result.alignedStartIndex, ...
            Symbol=metadata.referenceSymbol, ...
            Direction=metadata.referenceDirection);
    end

    function render_result(iq, result, fileInfo, profile, golden, hdlMetadata)
        fs = result.sampleRateHz;
        spec = result.spectrogram;
        imagesc(overviewAxes, spec.timeSeconds*1e3, spec.frequencyHz/1e3, spec.powerDb);
        axis(overviewAxes, "xy"); colorbar(overviewAxes);
        xlabel(overviewAxes, "Time, ms");
        ylabel(overviewAxes, "Frequency offset, kHz");
        hold(overviewAxes, "on");
        xline(overviewAxes, result.packetStartSeconds*1e3, "w--", "start");
        xline(overviewAxes, result.packetEndSeconds*1e3, "w--", "end");
        hold(overviewAxes, "off");

        indices = result.packetStartIndex:result.packetEndIndex;
        timeMs = (indices-result.packetStartIndex)/fs*1e3;
        packet = iq(indices);
        yyaxis(packetAxes, "left");
        plot(packetAxes, timeMs, abs(packet), "Color", [0.1 0.45 0.85]);
        ylabel(packetAxes, "Amplitude");
        yyaxis(packetAxes, "right");
        instantFrequency = [NaN; angle(packet(2:end).*conj(packet(1:end-1)))*fs/(2*pi)]/1e3;
        plot(packetAxes, timeMs, instantFrequency, ".", "MarkerSize", 3, "Color", [0.85 0.3 0.15]);
        ylabel(packetAxes, "Instantaneous frequency, kHz");
        xlabel(packetAxes, "Time from burst start, ms");
        grid(packetAxes, "on");

        plot(spectrumAxes, result.averageSpectrumFrequencyHz/1e3, ...
            result.averageSpectrumPowerDb, "LineWidth", 1);
        xlabel(spectrumAxes, "Frequency offset, kHz");
        ylabel(spectrumAxes, "Relative power, dB");
        grid(spectrumAxes, "on"); hold(spectrumAxes, "on");
        carrierKhz = result.estimatedCarrierOffsetHz/1e3;
        halfBwKhz = result.estimatedBandwidthHz/2e3;
        xline(spectrumAxes, carrierKhz, "r-", "carrier");
        xline(spectrumAxes, carrierKhz-halfBwKhz, "k--");
        xline(spectrumAxes, carrierKhz+halfBwKhz, "k--");
        hold(spectrumAxes, "off");

        imagesc(dechirpAxes, 0:2^result.estimatedSpreadingFactor-1, ...
            1:result.analyzedSymbolCount, result.dechirpedFftPowerDb, [-35 0]);
        axis(dechirpAxes, "xy"); colorbar(dechirpAxes);
        xlabel(dechirpAxes, "FFT bin / symbol index");
        ylabel(dechirpAxes, "Symbol time index");

        absoluteCarrier = centreField.Value+result.estimatedCarrierOffsetHz;
        if expectedField.Value == 0
            cfoText = sprintf("%.1f Hz residual", result.residualCfoHz);
            cfoNote = "Nominal carrier not specified";
        else
            cfoText = sprintf("%.1f Hz", absoluteCarrier-expectedField.Value);
            cfoNote = "Estimated relative to expected carrier";
        end
        clippingText = "—";
        if isfinite(fileInfo.clippedComponentFraction)
            clippingText = sprintf("%.4f %%", 100*fileInfo.clippedComponentFraction);
        end

        rows = {
            "PHY mode", char(profile.modeSummary), char(profile.semtechPacketType);
            "Compatible radios", char(profile.compatibilitySummary), char(profile.note);
            "Project reference radio", char(profile.projectReferenceRadio), "Heltec V4.3 uses SX1262";
            "Packet boundaries", sprintf("%.3f … %.3f ms", result.packetStartSeconds*1e3, result.packetEndSeconds*1e3), "Strongest energy burst";
            "Bandwidth", sprintf("%.0f kHz", result.estimatedBandwidthHz/1e3), sprintf("Measured %.1f kHz", result.measuredOccupiedBandwidthHz/1e3);
            "Spreading factor", sprintf("SF%d", result.estimatedSpreadingFactor), sprintf("Periodicity score %.3f", result.preambleScore);
            "Symbol duration", sprintf("%.3f ms", result.estimatedSymbolDurationSeconds*1e3), "2^SF / BW";
            "Carrier frequency", sprintf("%.6f MHz", absoluteCarrier/1e6), sprintf("Offset %.1f Hz", result.estimatedCarrierOffsetHz);
            "CFO", cfoText, cfoNote;
            "SNR", sprintf("%.1f dB", result.estimatedSnrDb), "Estimated from no-signal intervals";
            "Power", sprintf("%.1f dB rel. 1", result.signalPowerDbRelative), "Uncalibrated RSSI";
            "DC offset", sprintf("%.4g %+.4gj", real(result.dcOffset), imag(result.dcOffset)), "Mean complex value";
            "I/Q imbalance", sprintf("%+.2f dB", result.iqPowerImbalanceDb), "I-to-Q power ratio";
            "Clipping", clippingText, "Integer capture components at full scale";
            "Symbols in FFT", sprintf("%d", result.analyzedSymbolCount), "Diagnostic bins, not packet decode"};

        if ~isempty(golden)
            verdict = "WARN";
            if golden.passed
                verdict = "PASS";
            end
            goldenRows = {
                "Golden reference", char(hdlMetadata.referenceDescription), sprintf("MATLAB reference, start %+d samples", golden.startAdjustmentSamples);
                "Golden EVM", sprintf("%.4f %%", golden.evmPercent), sprintf("%s; threshold <= %.1f %%", verdict, golden.passThresholds.evmPercent);
                "Golden correlation", sprintf("%.8f", golden.correlation), sprintf("threshold >= %.3f", golden.passThresholds.correlation);
                "RMS phase error", sprintf("%.4f deg", golden.rmsPhaseErrorDegrees), sprintf("max %.4f deg", golden.maxPhaseErrorDegrees);
                "Peak sample error", sprintf("%.6g", golden.maxNormalizedSampleError), sprintf("gain %.3f dB", golden.gainDb)};
            rows = [rows(1:3,:); goldenRows; rows(4:end,:)]; %#ok<AGROW>
        end

        resultTable.Data = cellfun(@char, rows, "UniformOutput", false);
        symbolLines = compose("%3d: %4d", (1:numel(result.detectedSymbols)).', result.detectedSymbols);
        textLines = [{'Detected FFT bins:'}; cellstr(symbolLines)];
        if ~isempty(golden)
            textLines = [ ...
                {sprintf('Golden: %s', upper(string(verdict))); ...
                 sprintf('EVM: %.4f %%', golden.evmPercent); ...
                 sprintf('Correlation: %.8f', golden.correlation); ...
                 sprintf('RMS phase: %.4f deg', golden.rmsPhaseErrorDegrees); ...
                 ' '; ...
                 'Detected FFT bins:'}; ...
                cellstr(symbolLines)];
        end
        symbolArea.Value = textLines;
    end

    function export_png(~, ~)
        [name, folder] = uiputfile( ...
            "*.png", "Save Inspector snapshot", "lora-phy-inspector.png");
        if ~isequal(name, 0)
            exportapp(figureHandle, fullfile(folder, name));
        end
    end
end
