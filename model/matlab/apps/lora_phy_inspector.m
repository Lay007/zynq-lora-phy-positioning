function app = lora_phy_inspector(visible, options)
%LORA_PHY_INSPECTOR Visual inspection and verification for IQ recordings.
%
% lora_phy_inspector()                    English interface, window shown
% lora_phy_inspector("off")               built hidden, for tests
% lora_phy_inspector("on", Language="ru")  Russian interface
%
% Only the interface language changes; every measurement, threshold and
% golden verdict is identical between languages.

arguments
    visible (1,1) string {mustBeMember(visible, ["on", "off"])} = "on"
    options.Language (1,1) string {mustBeMember(options.Language, ["en", "ru"])} = "en"
end

matlabRoot = fileparts(fileparts(mfilename("fullpath")));
addpath(matlabRoot);
S = lora_phy.inspector_strings(options.Language);

figureHandle = uifigure( ...
    "Name", S.windowName, ...
    "Position", [80 50 1440 900], ...
    "Visible", visible);
mainGrid = uigridlayout(figureHandle, [3 1]);
mainGrid.RowHeight = {104, "1x", 210};
mainGrid.Padding = [10 10 10 10];

controls = uigridlayout(mainGrid, [2 8]);
controls.Layout.Row = 1;
controls.ColumnWidth = {"1x", 90, 78, 125, 120, 145, 120, 110};
controls.RowHeight = {24, 34};
fileLabel = uilabel(controls, "Text", S.fileLabel, "FontWeight", "bold");
fileLabel.Layout.Column = 1;
formatLabel = uilabel(controls, "Text", S.formatLabel, "FontWeight", "bold");
formatLabel.Layout.Column = 3;
sampleRateLabel = uilabel(controls, "Text", S.sampleRateLabel, "FontWeight", "bold");
sampleRateLabel.Layout.Column = 4;
centreLabel = uilabel(controls, "Text", S.centreLabel, "FontWeight", "bold");
centreLabel.Layout.Column = 5;
expectedLabel = uilabel(controls, "Text", S.expectedLabel, "FontWeight", "bold");
expectedLabel.Layout.Column = 6;
statusLabel = uilabel(controls, "Text", S.statusInitial);
statusLabel.Layout.Row = 1;
statusLabel.Layout.Column = [7 8];

fileField = uieditfield(controls, "text", "Placeholder", S.filePlaceholder);
fileField.Layout.Row = 2;
fileField.Layout.Column = 1;
browseButton = uibutton(controls, "Text", S.browseButton, ...
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
    "Tooltip", S.centreTooltip);
centreField.Layout.Row = 2;
centreField.Layout.Column = 5;
expectedField = uieditfield(controls, "numeric", "Value", 0, ...
    "Tooltip", S.expectedTooltip);
expectedField.Layout.Row = 2;
expectedField.Layout.Column = 6;
analyzeButton = uibutton(controls, "Text", S.analyzeButton, ...
    "FontWeight", "bold", "ButtonPushedFcn", @analyze_file);
analyzeButton.Layout.Row = 2;
analyzeButton.Layout.Column = 7;
exportButton = uibutton(controls, "Text", S.exportButton, ...
    "Enable", "off", "ButtonPushedFcn", @export_png);
exportButton.Layout.Row = 2;
exportButton.Layout.Column = 8;

plots = uigridlayout(mainGrid, [2 2]);
plots.Layout.Row = 2;
overviewAxes = uiaxes(plots); title(overviewAxes, S.axOverview);
packetAxes = uiaxes(plots); title(packetAxes, S.axPacket);
spectrumAxes = uiaxes(plots); title(spectrumAxes, S.axSpectrum);
dechirpAxes = uiaxes(plots); title(dechirpAxes, S.axDechirp);

bottom = uigridlayout(mainGrid, [1 2]);
bottom.Layout.Row = 3;
bottom.ColumnWidth = {"2.4x", "1x"};
resultTable = uitable(bottom, ...
    "ColumnName", {char(S.colParameter), char(S.colEstimate), char(S.colNotes)}, ...
    "ColumnWidth", {210, 220, "auto"}, ...
    "Data", cell(0, 3));
symbolArea = uitextarea(bottom, "Editable", "off", ...
    "Value", S.symbolPlaceholder, ...
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
app.Language = options.Language;

    function browse_file(~, ~)
        [name, folder] = uigetfile( ...
            {"*.cu8;*.uc8;*.cf32;*.fc32;*.cfile;*.pcm;*.ci16;*.sc16", char(S.browseIqFilter); ...
            "*.*", char(S.browseAllFilter)});
        if ~isequal(name, 0)
            fileField.Value = fullfile(folder, name);
        end
    end

    function analyze_file(~, ~)
        try
            run_analysis();
        catch exception
            statusLabel.Text = S.statusFailed;
            uialert(figureHandle, exception.message, S.alertTitle);
        end
    end

    function result = run_analysis()
        statusLabel.Text = S.statusReading;
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
            statusLabel.Text = sprintf(S.statusDoneSamples, ...
                upper(fileInfo.format), fileInfo.sampleCount);
        else
            verdict = "WARN";
            if golden.passed
                verdict = "PASS";
            end
            statusLabel.Text = sprintf(S.statusDoneGolden, ...
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
        xlabel(overviewAxes, S.labTime);
        ylabel(overviewAxes, S.labFrequencyOffset);
        hold(overviewAxes, "on");
        xline(overviewAxes, result.packetStartSeconds*1e3, "w--", S.markStart);
        xline(overviewAxes, result.packetEndSeconds*1e3, "w--", S.markEnd);
        hold(overviewAxes, "off");

        indices = result.packetStartIndex:result.packetEndIndex;
        timeMs = (indices-result.packetStartIndex)/fs*1e3;
        packet = iq(indices);
        yyaxis(packetAxes, "left");
        plot(packetAxes, timeMs, abs(packet), "Color", [0.1 0.45 0.85]);
        ylabel(packetAxes, S.labAmplitude);
        yyaxis(packetAxes, "right");
        instantFrequency = [NaN; angle(packet(2:end).*conj(packet(1:end-1)))*fs/(2*pi)]/1e3;
        plot(packetAxes, timeMs, instantFrequency, ".", "MarkerSize", 3, "Color", [0.85 0.3 0.15]);
        ylabel(packetAxes, S.labInstantFrequency);
        xlabel(packetAxes, S.labTimeFromBurst);
        grid(packetAxes, "on");

        plot(spectrumAxes, result.averageSpectrumFrequencyHz/1e3, ...
            result.averageSpectrumPowerDb, "LineWidth", 1);
        xlabel(spectrumAxes, S.labFrequencyOffset);
        ylabel(spectrumAxes, S.labRelativePower);
        grid(spectrumAxes, "on"); hold(spectrumAxes, "on");
        carrierKhz = result.estimatedCarrierOffsetHz/1e3;
        halfBwKhz = result.estimatedBandwidthHz/2e3;
        xline(spectrumAxes, carrierKhz, "r-", S.markCarrier);
        xline(spectrumAxes, carrierKhz-halfBwKhz, "k--");
        xline(spectrumAxes, carrierKhz+halfBwKhz, "k--");
        hold(spectrumAxes, "off");

        imagesc(dechirpAxes, 0:2^result.estimatedSpreadingFactor-1, ...
            1:result.analyzedSymbolCount, result.dechirpedFftPowerDb, [-35 0]);
        axis(dechirpAxes, "xy"); colorbar(dechirpAxes);
        xlabel(dechirpAxes, S.labFftBin);
        ylabel(dechirpAxes, S.labSymbolIndex);

        absoluteCarrier = centreField.Value+result.estimatedCarrierOffsetHz;
        if expectedField.Value == 0
            cfoText = sprintf(S.valueCfoResidual, result.residualCfoHz);
            cfoNote = S.noteCfoUnknown;
        else
            cfoText = sprintf(S.valueCfoAbsolute, absoluteCarrier-expectedField.Value);
            cfoNote = S.noteCfoKnown;
        end
        clippingText = "—";
        if isfinite(fileInfo.clippedComponentFraction)
            clippingText = sprintf(S.valueClipping, 100*fileInfo.clippedComponentFraction);
        end

        rows = {
            S.rowPhyMode, char(profile.modeSummary), char(profile.semtechPacketType);
            S.rowRadios, char(profile.compatibilitySummary), S.noteProfile;
            S.rowReferenceRadio, char(profile.projectReferenceRadio), S.noteReferenceRadio;
            S.rowBoundaries, sprintf(S.valueBoundaries, result.packetStartSeconds*1e3, result.packetEndSeconds*1e3), S.noteBoundaries;
            S.rowBandwidth, sprintf(S.valueBandwidth, result.estimatedBandwidthHz/1e3), sprintf(S.noteBandwidth, result.measuredOccupiedBandwidthHz/1e3);
            S.rowSpreadingFactor, sprintf("SF%d", result.estimatedSpreadingFactor), sprintf(S.noteSpreadingFactor, result.preambleScore);
            S.rowSymbolDuration, sprintf(S.valueSymbolDuration, result.estimatedSymbolDurationSeconds*1e3), S.noteSymbolDuration;
            S.rowCarrier, sprintf(S.valueCarrier, absoluteCarrier/1e6), sprintf(S.noteCarrier, result.estimatedCarrierOffsetHz);
            S.rowCfo, cfoText, cfoNote;
            S.rowSnr, sprintf(S.valueSnr, result.estimatedSnrDb), S.noteSnr;
            S.rowPower, sprintf(S.valuePower, result.signalPowerDbRelative), S.notePower;
            S.rowDcOffset, sprintf(S.valueDcOffset, real(result.dcOffset), imag(result.dcOffset)), S.noteDcOffset;
            S.rowIqImbalance, sprintf(S.valueIqImbalance, result.iqPowerImbalanceDb), S.noteIqImbalance;
            S.rowClipping, clippingText, S.noteClipping;
            S.rowSymbolsInFft, sprintf("%d", result.analyzedSymbolCount), S.noteSymbolsInFft};

        if ~isempty(golden)
            verdict = "WARN";
            if golden.passed
                verdict = "PASS";
            end
            goldenRows = {
                S.rowGoldenReference, lora_phy.describe_reference(hdlMetadata, S), sprintf(S.noteGoldenReference, golden.startAdjustmentSamples);
                S.rowGoldenEvm, sprintf(S.valueGoldenEvm, golden.evmPercent), sprintf(S.noteGoldenEvm, verdict, golden.passThresholds.evmPercent);
                S.rowGoldenCorrelation, sprintf("%.8f", golden.correlation), sprintf(S.noteGoldenCorrelation, golden.passThresholds.correlation);
                S.rowRmsPhase, sprintf(S.valueRmsPhase, golden.rmsPhaseErrorDegrees), sprintf(S.noteRmsPhase, golden.maxPhaseErrorDegrees);
                S.rowPeakError, sprintf("%.6g", golden.maxNormalizedSampleError), sprintf(S.notePeakError, golden.gainDb)};
            rows = [rows(1:3,:); goldenRows; rows(4:end,:)];
        end

        resultTable.Data = cellfun(@char, rows, "UniformOutput", false);
        symbolLines = compose("%3d: %4d", (1:numel(result.detectedSymbols)).', result.detectedSymbols);
        % Keep this a string array: the localized formats are strings, so
        % sprintf returns strings, and a cell mixing those with char vectors
        % is not a value uitextarea accepts.
        binsHeader = string(S.textDetectedBins);
        if isempty(golden)
            textLines = [binsHeader; symbolLines];
        else
            textLines = [ ...
                string(sprintf(S.textGoldenVerdict, upper(string(verdict)))); ...
                string(sprintf(S.textEvm, golden.evmPercent)); ...
                string(sprintf(S.textCorrelation, golden.correlation)); ...
                string(sprintf(S.textRmsPhase, golden.rmsPhaseErrorDegrees)); ...
                ""; ...
                binsHeader; ...
                symbolLines];
        end
        symbolArea.Value = textLines;
    end

    function export_png(~, ~)
        [name, folder] = uiputfile( ...
            "*.png", char(S.exportTitle), "lora-phy-inspector.png");
        if ~isequal(name, 0)
            exportapp(figureHandle, fullfile(folder, name));
        end
    end
end
