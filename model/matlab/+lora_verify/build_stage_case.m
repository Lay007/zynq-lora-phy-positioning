function [window, info] = build_stage_case(definition)
%BUILD_STAGE_CASE Synthesize the aligned symbol window for one case.
%
% Two guard symbols are modulated before and after the window so that
% fractional delay and whole-sample misalignment never pull zero padding
% into the extracted window. The window is always exactly
% numel(symbols)*samplesPerSymbol samples long, which is what the FFT
% correlator and the Simulink DUT consume.

arguments
    definition (1,1) struct
end

config = lora_phy.css_config(definition.spreadingFactor, ...
    definition.samplesPerChip);
sampleRateHz = definition.bandwidthHz*config.samplesPerChip;

guardCount = 2;
guardSymbols = mod((1:guardCount).'*37, config.symbolCount);
transmitted = definition.symbols(:);
streamSymbols = [guardSymbols; transmitted; guardSymbols];
stream = lora_phy.modulate(streamSymbols, config);

impaired = lora_phy.apply_channel_impairments(stream, sampleRateHz, ...
    FrequencyOffsetHz=definition.frequencyOffsetHz, ...
    FractionalDelaySamples=definition.fractionalDelaySamples, ...
    SnrDb=definition.snrDb, ...
    RandomSeed=definition.randomSeed);

startIndex = guardCount*config.samplesPerSymbol + 1 + ...
    definition.integerOffsetSamples;
windowLength = numel(transmitted)*config.samplesPerSymbol;
stopIndex = startIndex+windowLength-1;
if startIndex < 1 || stopIndex > numel(impaired)
    error("lora_verify:WindowOutOfRange", ...
        "Case %s extracts samples outside the generated stream", ...
        definition.id);
end
window = impaired(startIndex:stopIndex);

info = struct;
info.config = config;
info.sampleRateHz = sampleRateHz;
info.guardCount = guardCount;
info.streamSymbols = streamSymbols(:).';
info.transmittedSymbols = transmitted(:).';
info.windowStartIndex = startIndex;
info.windowLength = windowLength;
end
