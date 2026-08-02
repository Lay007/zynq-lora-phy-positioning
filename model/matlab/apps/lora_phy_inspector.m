function app = lora_phy_inspector(visible)
%LORA_PHY_INSPECTOR Visual inspection and parameter estimation for IQ files.

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
mainGrid.RowHeight = {96, "1x", 170};
mainGrid.Padding = [10 10 10 10];

controls = uigridlayout(mainGrid, [2 8]);
controls.Layout.Row = 1;
controls.ColumnWidth = {"1x", 90, 78, 115, 96, 130, 120, 110};
controls.RowHeight = {24, 34};
fileLabel = uilabel(controls, "Text", "IQ-файл", "FontWeight", "bold");
fileLabel.Layout.Column = 1;
formatLabel = uilabel(controls, "Text", "Формат", "FontWeight", "bold");
formatLabel.Layout.Column = 3;
sampleRateLabel = uilabel(controls, "Text", "Fs, Гц", "FontWeight", "bold");
sampleRateLabel.Layout.Column = 4;
centreLabel = uilabel(controls, "Text", "Центр, Гц", "FontWeight", "bold");
centreLabel.Layout.Column = 5;
expectedLabel = uilabel(controls, "Text", "Ожид. частота, Гц", "FontWeight", "bold");
expectedLabel.Layout.Column = 6;
statusLabel = uilabel(controls, "Text", "Выберите запись RTL-SDR или PlutoSDR");
statusLabel.Layout.Row = 1;
statusLabel.Layout.Column = [7 8];

fileField = uieditfield(controls, "text", "Placeholder", "capture.cu8 или capture.cf32");
fileField.Layout.Row = 2;
fileField.Layout.Column = 1;
browseButton = uibutton(controls, "Text", "Открыть…", "ButtonPushedFcn", @browse_file);
browseButton.Layout.Row = 2;
browseButton.Layout.Column = 2;
formatDropDown = uidropdown(controls, "Items", ["auto", "cu8", "cf32"], "Value", "auto");
formatDropDown.Layout.Row = 2;
formatDropDown.Layout.Column = 3;
sampleRateField = uieditfield(controls, "numeric", "Value", 1e6, "Limits", [1 Inf]);
sampleRateField.Layout.Row = 2;
sampleRateField.Layout.Column = 4;
centreField = uieditfield(controls, "numeric", "Value", 868.35e6);
centreField.Layout.Row = 2;
centreField.Layout.Column = 5;
expectedField = uieditfield(controls, "numeric", "Value", 0, ...
    "Tooltip", "0 — неизвестно; иначе используется для оценки CFO");
expectedField.Layout.Row = 2;
expectedField.Layout.Column = 6;
analyzeButton = uibutton(controls, "Text", "Анализировать", ...
    "FontWeight", "bold", "ButtonPushedFcn", @analyze_file);
analyzeButton.Layout.Row = 2;
analyzeButton.Layout.Column = 7;
exportButton = uibutton(controls, "Text", "Сохранить PNG", ...
    "Enable", "off", "ButtonPushedFcn", @export_png);
exportButton.Layout.Row = 2;
exportButton.Layout.Column = 8;

plots = uigridlayout(mainGrid, [2 2]);
plots.Layout.Row = 2;
overviewAxes = uiaxes(plots); title(overviewAxes, "Вся запись: спектрограмма");
packetAxes = uiaxes(plots); title(packetAxes, "Найденная посылка");
spectrumAxes = uiaxes(plots); title(spectrumAxes, "Средний спектр");
dechirpAxes = uiaxes(plots); title(dechirpAxes, "Dechirp FFT по символам");

bottom = uigridlayout(mainGrid, [1 2]);
bottom.Layout.Row = 3;
bottom.ColumnWidth = {"2x", "1x"};
resultTable = uitable(bottom, ...
    "ColumnName", {'Параметр', 'Оценка', 'Комментарий'}, ...
    "ColumnWidth", {210, 150, "auto"}, ...
    "Data", cell(0, 3));
symbolArea = uitextarea(bottom, "Editable", "off", ...
    "Value", "Здесь появятся обнаруженные номера символов.", ...
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
            {"*.cu8;*.uc8;*.cf32;*.fc32;*.cfile", "IQ-записи"; "*.*", "Все файлы"});
        if ~isequal(name, 0)
            fileField.Value = fullfile(folder, name);
        end
    end

    function analyze_file(~, ~)
        try
            run_analysis();
        catch exception
            statusLabel.Text = "Ошибка анализа";
            uialert(figureHandle, exception.message, "Не удалось обработать запись");
        end
    end

    function result = run_analysis()
        statusLabel.Text = "Чтение и анализ…";
        drawnow;
        [iq, fileInfo] = lora_phy.load_iq_capture(fileField.Value, formatDropDown.Value);
        fs = sampleRateField.Value;
        result = lora_phy.inspect_iq_capture(iq, fs);
        render_result(iq, result, fileInfo);
        exportButton.Enable = "on";
        statusLabel.Text = sprintf("Готово: %s, %d отсчётов", ...
            upper(fileInfo.format), fileInfo.sampleCount);
    end

    function render_result(iq, result, fileInfo)
        fs = result.sampleRateHz;
        spec = result.spectrogram;
        imagesc(overviewAxes, spec.timeSeconds*1e3, spec.frequencyHz/1e3, spec.powerDb);
        axis(overviewAxes, "xy"); colorbar(overviewAxes);
        xlabel(overviewAxes, "Время, мс"); ylabel(overviewAxes, "Частота от центра, кГц");
        hold(overviewAxes, "on");
        xline(overviewAxes, result.packetStartSeconds*1e3, "w--", "start");
        xline(overviewAxes, result.packetEndSeconds*1e3, "w--", "end");
        hold(overviewAxes, "off");

        indices = result.packetStartIndex:result.packetEndIndex;
        timeMs = (indices-result.packetStartIndex)/fs*1e3;
        packet = iq(indices);
        yyaxis(packetAxes, "left");
        plot(packetAxes, timeMs, abs(packet), "Color", [0.1 0.45 0.85]);
        ylabel(packetAxes, "Амплитуда");
        yyaxis(packetAxes, "right");
        instantFrequency = [NaN; angle(packet(2:end).*conj(packet(1:end-1)))*fs/(2*pi)]/1e3;
        plot(packetAxes, timeMs, instantFrequency, ".", "MarkerSize", 3, "Color", [0.85 0.3 0.15]);
        ylabel(packetAxes, "Δf, кГц"); xlabel(packetAxes, "Время от начала, мс");
        grid(packetAxes, "on");

        plot(spectrumAxes, result.averageSpectrumFrequencyHz/1e3, ...
            result.averageSpectrumPowerDb, "LineWidth", 1);
        xlabel(spectrumAxes, "Частота от центра, кГц"); ylabel(spectrumAxes, "Мощность, dB rel.");
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
        xlabel(dechirpAxes, "FFT bin / номер символа"); ylabel(dechirpAxes, "Символ во времени");

        absoluteCarrier = centreField.Value+result.estimatedCarrierOffsetHz;
        if expectedField.Value == 0
            cfoText = sprintf("%.1f Гц (остаточный)", result.residualCfoHz);
            cfoNote = "Номинал неизвестен";
        else
            cfoText = sprintf("%.1f Гц", absoluteCarrier-expectedField.Value);
            cfoNote = "Оценка относительно ожидаемой частоты";
        end
        clippingText = "—";
        if isfinite(fileInfo.clippedComponentFraction)
            clippingText = sprintf("%.4f %%", 100*fileInfo.clippedComponentFraction);
        end
        rows = {
            "Границы посылки", sprintf("%.3f … %.3f мс", result.packetStartSeconds*1e3, result.packetEndSeconds*1e3), "Самый сильный энергетический пакет";
            "Полоса BW", sprintf("%.0f кГц", result.estimatedBandwidthHz/1e3), sprintf("Измерено %.1f кГц", result.measuredOccupiedBandwidthHz/1e3);
            "Spreading factor", sprintf("SF%d", result.estimatedSpreadingFactor), sprintf("Периодичность %.3f", result.preambleScore);
            "Длительность символа", sprintf("%.3f мс", result.estimatedSymbolDurationSeconds*1e3), "2^SF / BW";
            "Несущая", sprintf("%.6f МГц", absoluteCarrier/1e6), sprintf("Смещение %.1f Гц", result.estimatedCarrierOffsetHz);
            "CFO", cfoText, cfoNote;
            "SNR", sprintf("%.1f дБ", result.estimatedSnrDb), "Оценка по участкам записи без сигнала";
            "Мощность", sprintf("%.1f dB rel. 1", result.signalPowerDbRelative), "Не калиброванный RSSI";
            "DC offset", sprintf("%.4g %+.4gj", real(result.dcOffset), imag(result.dcOffset)), "Среднее комплексное значение";
            "I/Q imbalance", sprintf("%+.2f дБ", result.iqPowerImbalanceDb), "Отношение мощностей I и Q";
            "Клиппинг", clippingText, "Только для нормированного CU8";
            "Символов в FFT", sprintf("%d", result.analyzedSymbolCount), "Не означает успешное декодирование"};
        resultTable.Data = cellfun(@char, rows, "UniformOutput", false);
        symbolLines = compose("%3d: %4d", (1:numel(result.detectedSymbols)).', result.detectedSymbols);
        symbolArea.Value = [{'Обнаруженные FFT bins:'}; cellstr(symbolLines)];
    end

    function export_png(~, ~)
        [name, folder] = uiputfile("*.png", "Сохранить снимок", "lora-phy-inspector.png");
        if ~isequal(name, 0)
            exportapp(figureHandle, fullfile(folder, name));
        end
    end
end
