function [waveform, info] = build_css_frame( ...
    payloadSymbols, config, upchirpCount, downchirpCount)
%BUILD_CSS_FRAME Build a research CSS frame with an acquisition preamble.

if nargin < 3
    upchirpCount = 8;
end
if nargin < 4
    downchirpCount = 2;
end

payloadSymbols = payloadSymbols(:);
if any(payloadSymbols < 0 | payloadSymbols >= config.symbolCount | ...
        payloadSymbols ~= fix(payloadSymbols))
    error("lora_phy:InvalidPayloadSymbol", ...
        "Payload symbols must be integers in the configured CSS alphabet");
end

preamble = lora_phy.preamble_waveform( ...
    config, upchirpCount, downchirpCount);
payload = lora_phy.modulate(payloadSymbols, config);
waveform = [preamble; payload];

info = struct;
info.upchirpCount = upchirpCount;
info.downchirpCount = downchirpCount;
info.preambleSamples = numel(preamble);
info.payloadSymbols = numel(payloadSymbols);
info.frameSamples = numel(waveform);
end
