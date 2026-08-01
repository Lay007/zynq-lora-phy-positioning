function result = receive_css_frame( ...
    received, payloadSymbolCount, config, upchirpCount, ...
    downchirpCount, minimumDetectionScore)
%RECEIVE_CSS_FRAME Detect, synchronize, and demodulate one research CSS frame.

if nargin < 4
    upchirpCount = 8;
end
if nargin < 5
    downchirpCount = 2;
end
if nargin < 6
    minimumDetectionScore = 0.5;
end

validateattributes(payloadSymbolCount, {'numeric'}, ...
    {'scalar', 'integer', '>=', 1}, mfilename, 'payloadSymbolCount');
received = received(:);
[startIndex, detectionScore, diagnostics] = ...
    lora_phy.detect_frame_start( ...
        received, config, upchirpCount, downchirpCount);
if detectionScore < minimumDetectionScore
    error("lora_phy:FrameNotDetected", ...
        "Best preamble score %.3f is below threshold %.3f", ...
        detectionScore, minimumDetectionScore);
end

symbolSamples = config.samplesPerSymbol;
firstUpchirp = received(startIndex:startIndex+symbolSamples-1);
frequencyOffset = lora_phy.estimate_frequency_offset( ...
    firstUpchirp, config, 0);
preambleSymbols = upchirpCount + downchirpCount;
payloadStartIndex = startIndex + preambleSymbols * symbolSamples;
payloadEndIndex = payloadStartIndex + ...
    payloadSymbolCount * symbolSamples - 1;
if payloadEndIndex > numel(received)
    error("lora_phy:CaptureTooShort", ...
        "Capture ends before the configured payload is complete");
end

payloadWaveform = received(payloadStartIndex:payloadEndIndex);
symbols = lora_phy.demodulate( ...
    payloadWaveform, config, frequencyOffset);

result = struct;
result.symbols = symbols;
result.startIndex = startIndex;
result.payloadStartIndex = payloadStartIndex;
result.frequencyOffset = frequencyOffset;
result.detectionScore = detectionScore;
result.detectorDiagnostics = diagnostics;
end
