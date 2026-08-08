function result = receive_lora_stream( ...
    iq, sampleRateHz, bandwidthHz, config, options)
%RECEIVE_LORA_STREAM End-to-end receiver for a continuous configured IQ stream.

arguments
    iq (:,1) {mustBeNumeric}
    sampleRateHz (1,1) double {mustBePositive}
    bandwidthHz (1,1) double {mustBePositive}
    config (1,1) struct
    options.PreambleSymbols (1,1) double ...
        {mustBeInteger, mustBePositive} = 8
    options.SyncWord (1,1) double ...
        {mustBeInteger, mustBeNonnegative} = hex2dec("12")
    options.IqInverted (1,1) logical = false
    options.ExpectedCarrierOffsetHz (1,1) double = NaN
    options.SoftDecoding (1,1) logical = true
    options.MaximumPayloadSymbols (1,1) double ...
        {mustBeInteger, mustBePositive} = 1024
    options.MaximumCandidates (1,1) double ...
        {mustBeInteger, mustBePositive} = 128
end

required = ["spreadingFactor", "samplesPerChip", "codingRate", ...
    "payloadCrc", "explicitHeader", "lowDataRateOptimization"];
for field = required
    if ~isfield(config, field)
        error("lora_phy:MissingConfig", "Missing config field: %s", field);
    end
end
actualSamplesPerChip = sampleRateHz/bandwidthHz;
if abs(actualSamplesPerChip-config.samplesPerChip) > 1e-9
    error("lora_phy:ConfigRateMismatch", ...
        "Config samplesPerChip does not match sampleRateHz/bandwidthHz");
end
payloadLength = NaN;
if ~config.explicitHeader
    if ~isfield(config, "payloadLength")
        error("lora_phy:MissingPayloadLength", ...
            "Implicit-header reception requires config.payloadLength");
    end
    payloadLength = config.payloadLength;
end

result = lora_phy.receive_lora_packets(iq, sampleRateHz, bandwidthHz, ...
    config.spreadingFactor, PreambleSymbols=options.PreambleSymbols, ...
    SyncWord=options.SyncWord, IqInverted=options.IqInverted, ...
    LowDataRateOptimization=double(config.lowDataRateOptimization), ...
    ExpectedCarrierOffsetHz=options.ExpectedCarrierOffsetHz, ...
    SoftDecoding=options.SoftDecoding, ...
    MaximumPayloadSymbols=options.MaximumPayloadSymbols, ...
    MaximumCandidates=options.MaximumCandidates, ...
    ExplicitHeader=config.explicitHeader, PayloadLength=payloadLength, ...
    CodingRate=config.codingRate, PayloadCrc=config.payloadCrc);
result.config = config;
result.durationSeconds = numel(iq)/sampleRateHz;
result.failedCandidateCount = result.candidateCount-result.receptionCount;
result.acquiredCount = 0;
if ~isempty(result.receptions)
    result.acquiredCount = sum(arrayfun(@(item) ...
        item.preambleValid && item.syncValid, result.receptions));
end
end
