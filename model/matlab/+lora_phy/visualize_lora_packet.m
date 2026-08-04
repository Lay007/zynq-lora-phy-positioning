function figureHandle = visualize_lora_packet(iq, sampleRateHz, result, options)
%VISUALIZE_LORA_PACKET Show synchronization, hard decisions, and bytes.

arguments
    iq (:,1) {mustBeNumeric}
    sampleRateHz (1,1) double {mustBePositive}
    result (1,1) struct
    options.OutputPath (1,1) string = ""
    options.Visible (1,1) logical = true
end

visibility = "off";
if options.Visible
    visibility = "on";
end
figureHandle = figure("Name", "LoRa packet demodulation", ...
    "Visible", visibility, "Position", [100 100 1500 900]);
layout = tiledlayout(figureHandle, 2, 2, ...
    "TileSpacing", "compact", "Padding", "compact");

specAxes = nexttile(layout);
spec = result.inspection.spectrogram;
imagesc(specAxes, spec.timeSeconds*1e3, spec.frequencyHz/1e3, spec.powerDb);
axis(specAxes, "xy"); colorbar(specAxes);
xlabel(specAxes, "Время записи, мс");
ylabel(specAxes, "Частота после front-end shift, кГц");
title(specAxes, "Спектрограмма и структура LoRa-пакета");
hold(specAxes, "on");
symbolSamples = result.config.samplesPerSymbol;
preambleStart = result.inspection.alignedStartIndex;
boundaries = preambleStart + symbolSamples*[0, result.preambleSymbols, ...
    result.preambleSymbols+2, ...
    result.preambleSymbols+4.25+result.lowSfPaddingSymbols];
labels = ["preamble", "sync", "SFD", "payload"];
for boundary = 1:numel(boundaries)
    xline(specAxes, (boundaries(boundary)-1)/sampleRateHz*1e3, ...
        "w--", labels(boundary), "LabelVerticalAlignment", "bottom");
end
viewStart = max(1, preambleStart-2*symbolSamples);
viewEnd = min(numel(iq), result.payloadStartIndex + ...
    (result.decoded.consumedSymbolCount+2)*symbolSamples);
xlim(specAxes, ([viewStart, viewEnd]-1)/sampleRateHz*1e3);
hold(specAxes, "off");

decisionAxes = nexttile(layout);
acquisitionSymbols = [result.preambleBins; result.syncBins];
allSymbols = [double(acquisitionSymbols); double(result.symbols(:))];
stem(decisionAxes, 0:numel(allSymbols)-1, allSymbols, "filled", ...
    "MarkerSize", 3);
xline(decisionAxes, result.preambleSymbols-0.5, "k--", "sync");
xline(decisionAxes, result.preambleSymbols+1.5, "k--", "payload");
xlabel(decisionAxes, "Номер анализируемого символа");
ylabel(decisionAxes, "Решение FFT, bin");
title(decisionAxes, sprintf("Демодуляция: preamble=%d, sync=[%d %d]", ...
    result.preambleValid, result.syncBins(1), result.syncBins(2)));
ylim(decisionAxes, [-1, 2^result.config.spreadingFactor]);
grid(decisionAxes, "on");

confidenceAxes = nexttile(layout);
confidence = [result.acquisitionConfidence(:); result.symbolConfidence(:)];
plot(confidenceAxes, 0:numel(confidence)-1, confidence, ".-", ...
    "LineWidth", 1, "MarkerSize", 9);
xlabel(confidenceAxes, "Номер анализируемого символа");
ylabel(confidenceAxes, "Энергия peak / сумма FFT");
title(confidenceAxes, "Достоверность жёстких решений");
grid(confidenceAxes, "on");

textAxes = nexttile(layout);
axis(textAxes, "off");
decoded = result.decoded;
if decoded.headerValid
    headerText = sprintf("payload=%d байт, CR=4/%d, CRC=%d", ...
        decoded.header.payloadLength, decoded.header.codingRate+4, ...
        decoded.header.payloadCrc);
else
    headerText = "заголовок не прошёл checksum";
end
bytes = decoded.payload(:).';
hexLines = byte_lines(bytes, 16);
ascii = char(bytes);
ascii(ascii < 32 | ascii > 126) = '.';
formatText = char("Результат: success=%d, decoder=%s\nHeader: %s\nPayload CRC: %d\n" + ...
    "CFO относительно центра: %.1f Гц\nResidual CFO: %.1f Гц\n" + ...
    "Payload (hex):\n%s\nPayload (ASCII):\n%s");
status = sprintf(formatText, ...
    result.success, result.decodingMethod, headerText, decoded.crcValid, ...
    result.inspection.estimatedCarrierOffsetHz, ...
    result.inspection.residualCfoHz, strjoin(hexLines, newline), ascii);
text(textAxes, 0, 1, status, "VerticalAlignment", "top", ...
    "FontName", "Consolas", "Interpreter", "none");
title(textAxes, "Декодированный пакет");

if options.OutputPath ~= ""
    outputDirectory = fileparts(options.OutputPath);
    if outputDirectory ~= "" && ~isfolder(outputDirectory)
        mkdir(outputDirectory);
    end
    exportgraphics(figureHandle, options.OutputPath, "Resolution", 160);
end
end

function lines = byte_lines(bytes, width)
if isempty(bytes)
    lines = "<нет данных>";
    return
end
lineCount = ceil(numel(bytes)/width);
lines = strings(lineCount, 1);
for line = 1:lineCount
    indices = (line-1)*width+1:min(line*width, numel(bytes));
    lines(line) = strjoin(compose("%02X", bytes(indices)), " ");
end
end
