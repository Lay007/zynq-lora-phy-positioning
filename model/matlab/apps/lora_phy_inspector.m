function app = lora_phy_inspector(visible, options)
%LORA_PHY_INSPECTOR Visual inspection and TX-checkpoint verification for IQ recordings.
%
% lora_phy_inspector()                    English interface, window shown
% lora_phy_inspector("off")               built hidden, for tests
% lora_phy_inspector("on", Language="ru")  Russian interface
%
% HDL recordings may be verified at one of five TX checkpoints. Stage can be
% inferred from the filename or overridden manually. Only stages backed by
% executable repository golden references can return PASS.

arguments
    visible (1,1) string {mustBeMember(visible, ["on", "off"])} = "on"
    options.Language (1,1) string {mustBeMember(options.Language, ["en", "ru"])} = "en"
end

matlabRoot = fileparts(fileparts(mfilename("fullpath")));
addpath(matlabRoot);
S = lora_phy.inspector_strings(options.Language);
L = local_labels(options.Language);

figureHandle = uifigure( ...
    "Name", S.windowName, ...
    "Position", [80 50 1500 930], ...
    "Visible", visible);
mainGrid = uigridlayout(figureHandle, [3 1]);
mainGrid.RowHeight = {134, "1x", 220};
mainGrid.Padding = [10 10 10 10];

controls = uigridlayout(mainGrid, [3 9]);
controls.Layout.Row = 1;
controls.ColumnWidth = {"1x", 90, 78, 125, 120, 145, 205, 120, 110};
controls.RowHeight = {24, 34, 42};

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
stageLabel = uilabel(controls, "Text", L.stageLabel, "FontWeight", "bold");
stageLabel.Layout.Column = 7;
statusLabel = uilabel(controls, "Text", S.statusInitial);
statusLabel.Layout.Row = 1;
statusLabel.Layout.Column = [8 9];

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
stageDropDown = uidropdown(controls, ...
    "Items", L.stageItems, ...
    "ItemsData", 0:5, ...
    "Value", 0, ...
    "Tooltip", L.stageTooltip);
stageDropDown.Layout.Row = 2;
stageDropDown.Layout.Column = 7;
analyzeButton = uibutton(controls, "Text", S.analyzeButton, ...
    "FontWeight", "bold", "ButtonPushedFcn", @analyze_file);
analyzeButton.Layout.Row = 2;
analyzeButton.Layout.Column = 8;
exportButton = uibutton(controls, "Text", S.exportButton, ...
    "Enable", "off", "ButtonPushedFcn", @export_png);
exportButton.Layout.Row = 2;
exportButton.Layout.Column = 9;

overallLabel = uilabel(controls, ...
    "Text", L.overallInitial, ...
    "HorizontalAlignment", "center", ...
    "FontWeight", "bold", ...
    "FontSize", 20);
overallLabel.Layout.Row = 3;
overallLabel.Layout.Column = [1 9];

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
    "ColumnWidth", {220, 220, "auto"}, ...
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
app.StageDropDown = stageDropDown;
app.OverallStatusLabel = overallLabel;
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
            overallLabel.Text = L.overallFailed;
            uialert(figureHandle, exception.message, S.alertTitle);
        end
    end

    function result = run_analysis()
        statusLabel.Text = S.statusReading;
        overallLabel.Text = L.overallRunning;
        drawnow;

        [iq, fileInfo] = lora_phy.load_iq_capture(fileField.Value, formatDropDown.Value);
        metadata = try_hdl_metadata(fileInfo);
        fs = sampleRateField.Value;

        if ~isempty(metadata)
            if abs(metadata.sampleRateHz-fs) > 0.5
                error("lora_phy:HdlSampleRateMismatch", ...
                    "Inspector Fs does not match the sample rate encoded in the HDL filename");
            end
            result = lora_phy.inspect_iq_capture(iq, fs, ...
                CandidateBandwidthHz=metadata.bandwidthHz, ...
                CandidateSpreadingFactors=metadata.spreadingFactor);
            profile = lora_phy.match_lora_profile( ...
                metadata.spreadingFactor, metadata.bandwidthHz, centreField.Value);
        else
            result = lora_phy.inspect_iq_capture(iq, fs);
            profile = lora_phy.match_lora_profile( ...
                result.estimatedSpreadingFactor, result.estimatedBandwidthHz, ...
                centreField.Value);
        end

        verification = [];
        if ~isempty(metadata)
            verification = lora_phy.verify_tx_checkpoint( ...
                iq, metadata, StageOverride=stageDropDown.Value, StartIndex=1);
        end

        render_result(iq, result, fileInfo, profile, verification, metadata);
        exportButton.Enable = "on";

        if isempty(verification)
            statusLabel.Text = sprintf(S.statusDoneSamples, ...
                upper(fileInfo.format), fileInfo.sampleCount);
            overallLabel.Text = L.overallAnalysisOnly;
        else
            statusLabel.Text = sprintf("%s: %s, TX stage %d %s", ...
                L.doneText, upper(fileInfo.format), ...
                verification.stageNumber, verification.verdict);
            if verification.verdict == "FAIL" && ~isempty(verification.failureReasons)
                overallLabel.Text = sprintf("%s: FAIL — %s", ...
                    L.overallPrefix, verification.failureReasons(1));
            else
                overallLabel.Text = sprintf("%s: %s — STAGE %d", ...
                    L.overallPrefix, verification.verdict, verification.stageNumber);
            end
        end
    end

    function metadata = try_hdl_metadata(fileInfo)
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
    end

    function render_result(iq, result, fileInfo, profile, verification, metadata)
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
        plot(packetAxes, timeMs, abs(packet));
        ylabel(packetAxes, S.labAmplitude);
        yyaxis(packetAxes, "right");
        instantFrequency = [NaN; angle(packet(2:end).*conj(packet(1:end-1)))*fs/(2*pi)]/1e3;
        plot(packetAxes, timeMs, instantFrequency, ".", "MarkerSize", 3);
        ylabel(packetAxes, S.labInstantFrequency);
        xlabel(packetAxes, S.labTimeFromBurst);
        grid(packetAxes, "on");

        plot(spectrumAxes, result.averageSpectrumFrequencyHz/1e3, ...
            result.averageSpectrumPowerDb, "LineWidth", 1);
        xlabel(spectrumAxes, S.labFrequencyOffset);
        ylabel(spectrumAxes, S.labRelativePower);
        grid(spectrumAxes, "on"); hold(spectrumAxes, "on");
        carrierKhz = result.estimatedCarrierOffsetHz/1e3;
        halfBwKhz = profile.bandwidthHz/2e3;
        xline(spectrumAxes, carrierKhz, "-", S.markCarrier);
        xline(spectrumAxes, carrierKhz-halfBwKhz, "--");
        xline(spectrumAxes, carrierKhz+halfBwKhz, "--");
        hold(spectrumAxes, "off");

        cla(dechirpAxes);
        if ~isempty(verification) && verification.stageNumber == 1 && ...
                ~isempty(verification.metrics)
            render_stage1_dechirp(iq, verification, metadata);
        else
            imagesc(dechirpAxes, 0:2^profile.spreadingFactor-1, ...
                1:result.analyzedSymbolCount, result.dechirpedFftPowerDb, [-35 0]);
            axis(dechirpAxes, "xy"); colorbar(dechirpAxes);
            title(dechirpAxes, S.axDechirp);
            xlabel(dechirpAxes, S.labFftBin);
            ylabel(dechirpAxes, S.labSymbolIndex);
        end

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
            S.rowBandwidth, sprintf(S.valueBandwidth, profile.bandwidthHz/1e3), sprintf(S.noteBandwidth, result.measuredOccupiedBandwidthHz/1e3);
            S.rowSpreadingFactor, sprintf("SF%d", profile.spreadingFactor), sprintf(S.noteSpreadingFactor, result.preambleScore);
            S.rowSymbolDuration, sprintf(S.valueSymbolDuration, profile.symbolDurationSeconds*1e3), S.noteSymbolDuration;
            S.rowCarrier, sprintf(S.valueCarrier, absoluteCarrier/1e6), sprintf(S.noteCarrier, result.estimatedCarrierOffsetHz);
            S.rowCfo, cfoText, cfoNote;
            S.rowSnr, sprintf(S.valueSnr, result.estimatedSnrDb), S.noteSnr;
            S.rowPower, sprintf(S.valuePower, result.signalPowerDbRelative), S.notePower;
            S.rowDcOffset, sprintf(S.valueDcOffset, real(result.dcOffset), imag(result.dcOffset)), S.noteDcOffset;
            S.rowIqImbalance, sprintf(S.valueIqImbalance, result.iqPowerImbalanceDb), S.noteIqImbalance;
            S.rowClipping, clippingText, S.noteClipping;
            S.rowSymbolsInFft, sprintf("%d", result.analyzedSymbolCount), S.noteSymbolsInFft};

        if ~isempty(verification)
            checkpointRows = checkpoint_rows(verification, metadata);
            rows = [checkpointRows; rows];
        end

        resultTable.Data = cellfun(@char, rows, "UniformOutput", false);
        symbolLines = compose("%3d: %4d", (1:numel(result.detectedSymbols)).', result.detectedSymbols);
        binsHeader = string(S.textDetectedBins);

        if isempty(verification)
            textLines = [binsHeader; symbolLines];
        else
            textLines = [ ...
                string(sprintf("%s: %s", L.overallPrefix, verification.verdict)); ...
                string(sprintf("TX stage: %d", verification.stageNumber)); ...
                string(verification.stageName); ...
                string(verification.summary)];
            if verification.stageNumber == 1 && ~isempty(verification.metrics)
                textLines = [textLines; ...
                    string(sprintf(L.phaseStepDiagnostic, ...
                        verification.metrics.medianPhaseIncrementErrorQ16Lsb, ...
                        verification.metrics.rmsPhaseIncrementErrorDegrees))];
            end
            if ~isempty(verification.failureReasons)
                textLines = [textLines; ""; string(L.failureHeader); verification.failureReasons];
            end
            textLines = [textLines; ""; binsHeader; symbolLines];
        end
        symbolArea.Value = textLines;
    end

    function render_stage1_dechirp(iq, v, metadata)
        m = v.metrics;
        symbolSamples = m.symbolSamples;
        range = m.bestStartIndex+(0:symbolSamples-1);
        if range(end) > numel(iq) || abs(m.complexGain) < eps
            title(dechirpAxes, L.stage1DechirpTitle);
            text(dechirpAxes, 0.5, 0.5, L.stage1DechirpUnavailable, ...
                "HorizontalAlignment", "center", "Units", "normalized");
            return
        end
        config = lora_phy.css_config(metadata.spreadingFactor, round(metadata.samplesPerChip));
        reference = lora_phy.modulate_symbol(metadata.referenceSymbol, config);
        if metadata.referenceDirection == "down"
            reference = conj(reference);
        end
        normalized = iq(range)/m.complexGain;
        dechirped = normalized(:).*conj(reference(:));
        spectrum = lora_phy.polyphase_spectrum(dechirped, config.samplesPerChip);
        spectrumDb = 10*log10(spectrum/max(max(spectrum), eps)+eps);
        plot(dechirpAxes, 0:config.symbolCount-1, spectrumDb, "LineWidth", 1);
        grid(dechirpAxes, "on");
        xlim(dechirpAxes, [0 max(config.symbolCount-1, 1)]);
        ylim(dechirpAxes, [-80 5]);
        title(dechirpAxes, L.stage1DechirpTitle);
        xlabel(dechirpAxes, S.labFftBin);
        ylabel(dechirpAxes, L.stage1DechirpY);
    end

    function rows = checkpoint_rows(v, metadata)
        rateNote = L.notChecked;
        if isfinite(v.sampleRatePassed)
            if v.stageNumber == 1
                rateNote = sprintf("%s; L=%.6g", pass_text(v.sampleRatePassed), metadata.samplesPerChip);
            else
                rateNote = pass_text(v.sampleRatePassed);
            end
        end
        countText = "—";
        countNote = L.notChecked;
        if isfinite(v.expectedSampleCount)
            countText = sprintf("%d / %d", v.sampleCount, v.expectedSampleCount);
            countNote = pass_text(v.sampleCountPassed);
        end
        contractText = L.notChecked;
        if isfinite(v.contractPassed)
            contractText = pass_text(v.contractPassed);
        end
        goldenText = L.notChecked;
        if isfinite(v.goldenPassed)
            goldenText = pass_text(v.goldenPassed);
        elseif v.verdict == "NOT VERIFIED"
            goldenText = "NOT VERIFIED";
        end

        rows = {
            L.rowOverall, v.verdict, v.summary;
            L.rowInput, "PASS", L.inputParsed;
            L.rowContract, contractText, L.contractNote;
            L.rowGolden, goldenText, L.goldenNote;
            L.rowStage, sprintf("%d", v.stageNumber), v.stageName;
            L.rowReference, lora_phy.describe_reference(metadata, S), L.repositoryGolden;
            L.rowSampleRate, sprintf("%.6f MHz", metadata.sampleRateHz/1e6), rateNote;
            L.rowSampleCount, countText, countNote};

        if v.stageNumber == 1 && ~isempty(v.metrics)
            m = v.metrics;
            rows = [rows; {
                S.rowGoldenEvm, sprintf(S.valueGoldenEvm, m.evmPercent), sprintf(S.noteGoldenEvm, v.verdict, m.passThresholds.evmPercent);
                S.rowGoldenCorrelation, sprintf("%.8f", m.correlation), sprintf(S.noteGoldenCorrelation, m.passThresholds.correlation);
                S.rowRmsPhase, sprintf(S.valueRmsPhase, m.rmsPhaseErrorDegrees), sprintf(S.noteRmsPhase, m.maxPhaseErrorDegrees);
                S.rowPeakError, sprintf("%.6g", m.maxNormalizedSampleError), sprintf(S.notePeakError, m.gainDb);
                L.rowPhaseStepQ16, sprintf("%+.4f LSB/sample", m.medianPhaseIncrementErrorQ16Lsb), L.phaseStepQ16Note;
                L.rowPhaseStepRms, sprintf("%.6f deg/sample", m.rmsPhaseIncrementErrorDegrees), L.phaseStepRmsNote;
                L.rowAlignment, sprintf("%+d samples", m.startAdjustmentSamples), L.alignmentNote}];
        elseif v.stageNumber == 2
            rows = [rows; {
                L.rowSymbols, sprintf("%d / %d", v.symbolsPassed, v.expectedSymbolCount), L.currentPackageContract;
                L.rowMeanEvm, sprintf("%.4f %%", v.meanEvmPercent), L.perSymbolMetric;
                L.rowWorstEvm, sprintf("%.4f %%", v.worstEvmPercent), "<= 1.0 %";
                L.rowWorstCorrelation, sprintf("%.8f", v.worstCorrelation), ">= 0.999";
                L.rowWorstPhase, sprintf("%.4f deg", v.worstRmsPhaseErrorDegrees), "<= 1.0 deg";
                L.rowTransitions, sprintf("%d", v.transitionsCovered), L.fullStreamCoversTransitions;
                L.rowFullStreamEvm, sprintf("%.4f %%", v.fullStreamEvmPercent), L.fullStreamMetric;
                L.rowFullStreamCorrelation, sprintf("%.8f", v.fullStreamCorrelation), L.fullStreamMetric}];
        else
            rows = [rows; {L.rowVerificationState, "NOT VERIFIED", L.missingReference}];
        end
    end

    function text = pass_text(value)
        if value
            text = "PASS";
        else
            text = "FAIL";
        end
    end

    function export_png(~, ~)
        [name, folder] = uiputfile( ...
            "*.png", char(S.exportTitle), "lora-phy-inspector.png");
        if ~isequal(name, 0)
            exportapp(figureHandle, fullfile(folder, name));
        end
    end
end

function L = local_labels(language)
if language == "ru"
    L.stageLabel = "Контрольная точка TX";
    L.stageItems = ["Авто по имени", "1 — Чирп / параметрическая Fs", "2 — Пакет 2.000 MS/s", ...
        "3 — Ресемплер 1.920 MS/s", "4 — CIC 61.440 MS/s", "5 — Перенос 61.440 MS/s"];
    L.stageTooltip = "Авто определяет точку по тегу имени HDL PCM; ручной выбор переопределяет только номер точки.";
    L.overallInitial = "ИТОГ: анализ не запускался";
    L.overallRunning = "ИТОГ: анализ...";
    L.overallFailed = "ИТОГ: FAIL";
    L.overallAnalysisOnly = "ИТОГ: только DSP-анализ — golden не выбран";
    L.overallPrefix = "ИТОГ";
    L.doneText = "Готово";
    L.rowOverall = "Совокупный результат";
    L.rowInput = "Входные данные";
    L.rowContract = "Контракт точки";
    L.rowGolden = "MATLAB golden";
    L.rowStage = "Контрольная точка TX";
    L.rowReference = "Эталон точки";
    L.rowSampleRate = "Частота дискретизации точки";
    L.rowSampleCount = "Число отсчётов";
    L.rowPhaseStepQ16 = "Ошибка шага фазы Q16";
    L.rowPhaseStepRms = "СКЗ ошибки шага фазы";
    L.rowAlignment = "Поправка границы символа";
    L.rowSymbols = "Символы package";
    L.rowMeanEvm = "Средний EVM символов";
    L.rowWorstEvm = "Худший EVM символа";
    L.rowWorstCorrelation = "Худшая корреляция";
    L.rowWorstPhase = "Худшая СКЗ ошибки фазы";
    L.rowTransitions = "Переходы между чирпами";
    L.rowFullStreamEvm = "EVM всей последовательности";
    L.rowFullStreamCorrelation = "Корреляция всей последовательности";
    L.rowVerificationState = "Состояние golden-проверки";
    L.repositoryGolden = "Исполняемый MATLAB golden из репозитория";
    L.inputParsed = "CI16 загружен; метаданные SF/BW/Fs/stage разобраны из имени";
    L.contractNote = "Геометрия Fs/BW и длина проверяются отдельно от качества golden";
    L.goldenNote = "Строгая цифровая проверка: EVM/correlation/RMS phase";
    L.phaseStepQ16Note = "Медианная signed-ошибка приращения фазы; систематические ±LSB указывают на DDS/RTL";
    L.phaseStepRmsNote = "Ошибка приращения после удаления постоянной комплексной амплитуды/фазы";
    L.alignmentNote = "Сдвиг лучшей границы относительно запрошенной";
    L.currentPackageContract = "Текущий HDL-контракт: 6×h=0, затем h=5,17,64↓,127; это ещё не полный стандартный LoRa packet";
    L.perSymbolMetric = "Посимвольная проверка";
    L.fullStreamCoversTransitions = "Полная waveform-проверка включает границы между символами";
    L.fullStreamMetric = "Одна комплексная нормировка на всю последовательность";
    L.missingReference = "Архитектура точки поддержана, но точный production reference ещё не зафиксирован в репозитории";
    L.notChecked = "не проверено";
    L.failureHeader = "Причины FAIL:";
    L.phaseStepDiagnostic = "HDL phase-step: median %+.4f Q16 LSB/sample; RMS %.6f deg/sample";
    L.stage1DechirpTitle = "Stage 1: БПФ остатка после дечирпа MATLAB golden";
    L.stage1DechirpY = "Относительная мощность, дБ";
    L.stage1DechirpUnavailable = "Недостаточно данных для Stage 1 dechirp";
else
    L.stageLabel = "TX checkpoint";
    L.stageItems = ["Auto from filename", "1 — Chirp / parametrized Fs", "2 — Package 2.000 MS/s", ...
        "3 — Resampler 1.920 MS/s", "4 — CIC 61.440 MS/s", "5 — Shift 61.440 MS/s"];
    L.stageTooltip = "Auto infers the checkpoint from the HDL PCM tag; manual selection overrides only the stage number.";
    L.overallInitial = "OVERALL: analysis not run";
    L.overallRunning = "OVERALL: analyzing...";
    L.overallFailed = "OVERALL: FAIL";
    L.overallAnalysisOnly = "OVERALL: DSP analysis only — no golden selected";
    L.overallPrefix = "OVERALL";
    L.doneText = "Done";
    L.rowOverall = "Overall result";
    L.rowInput = "Input";
    L.rowContract = "Checkpoint contract";
    L.rowGolden = "MATLAB golden";
    L.rowStage = "TX checkpoint";
    L.rowReference = "Checkpoint reference";
    L.rowSampleRate = "Checkpoint sample rate";
    L.rowSampleCount = "Sample count";
    L.rowPhaseStepQ16 = "Q16 phase-step error";
    L.rowPhaseStepRms = "RMS phase-step error";
    L.rowAlignment = "Symbol-boundary adjustment";
    L.rowSymbols = "Package symbols";
    L.rowMeanEvm = "Mean symbol EVM";
    L.rowWorstEvm = "Worst symbol EVM";
    L.rowWorstCorrelation = "Worst correlation";
    L.rowWorstPhase = "Worst RMS phase error";
    L.rowTransitions = "Chirp transitions";
    L.rowFullStreamEvm = "Full-stream EVM";
    L.rowFullStreamCorrelation = "Full-stream correlation";
    L.rowVerificationState = "Golden verification state";
    L.repositoryGolden = "Executable MATLAB golden in the repository";
    L.inputParsed = "CI16 loaded; SF/BW/Fs/stage metadata parsed from filename";
    L.contractNote = "Fs/BW geometry and length are checked separately from golden quality";
    L.goldenNote = "Strict digital check: EVM/correlation/RMS phase";
    L.phaseStepQ16Note = "Median signed phase-increment error; systematic ±LSB points to DDS/RTL";
    L.phaseStepRmsNote = "Increment error after removing one constant complex gain/phase";
    L.alignmentNote = "Best boundary shift relative to the requested start";
    L.currentPackageContract = "Current HDL contract: 6×h=0 then h=5,17,64 down,127; not yet a complete standard LoRa packet";
    L.perSymbolMetric = "Per-symbol verification";
    L.fullStreamCoversTransitions = "Full waveform verification covers symbol boundaries";
    L.fullStreamMetric = "One complex normalization for the whole stream";
    L.missingReference = "Checkpoint architecture is recognized, but the exact production reference is not yet fixed in the repository";
    L.notChecked = "not checked";
    L.failureHeader = "FAIL reasons:";
    L.phaseStepDiagnostic = "HDL phase-step: median %+.4f Q16 LSB/sample; RMS %.6f deg/sample";
    L.stage1DechirpTitle = "Stage 1: residual FFT after MATLAB-golden dechirp";
    L.stage1DechirpY = "Relative power, dB";
    L.stage1DechirpUnavailable = "Not enough data for Stage 1 dechirp";
end
end
