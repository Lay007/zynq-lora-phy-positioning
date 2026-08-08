function [stream, truth, metadata] = build_lora_stream( ...
    payloads, config, bandwidthHz, options)
%BUILD_LORA_STREAM Place complete LoRa packets in a continuous IQ stream.

arguments
    payloads (:,1) cell
    config (1,1) struct
    bandwidthHz (1,1) double {mustBePositive}
    options.PreambleSymbols (1,1) double ...
        {mustBeInteger, mustBePositive} = 8
    options.SyncWord (1,1) double ...
        {mustBeInteger, mustBeNonnegative} = hex2dec("12")
    options.IqInverted (1,1) logical = false
    options.LeadingSilenceSeconds (1,1) double {mustBeNonnegative} = 0.02
    options.TrailingSilenceSeconds (1,1) double {mustBeNonnegative} = 0.02
    options.InterPacketGapSeconds (:,1) double {mustBeNonnegative} = 0.02
    options.Amplitudes (:,1) double = zeros(0, 1)
    options.InitialPhasesRadians (:,1) double = zeros(0, 1)
    options.RandomSeed (1,1) double ...
        {mustBeInteger, mustBeNonnegative} = 0
end

packetCount = numel(payloads);
if packetCount < 1
    error("lora_phy:EmptyPacketStream", ...
        "At least one payload is required");
end
sampleRateHz = bandwidthHz*config.samplesPerChip;
gaps = expand_parameter(options.InterPacketGapSeconds, ...
    max(packetCount-1, 0), "InterPacketGapSeconds");
amplitudes = expand_parameter(options.Amplitudes, packetCount, "Amplitudes");
if isempty(options.Amplitudes)
    amplitudes = ones(packetCount, 1);
end
if any(amplitudes <= 0)
    error("lora_phy:InvalidAmplitude", "Amplitudes must be positive");
end
phases = expand_parameter(options.InitialPhasesRadians, ...
    packetCount, "InitialPhasesRadians");
if isempty(options.InitialPhasesRadians)
    previousState = rng;
    restoreState = onCleanup(@() rng(previousState));
    rng(options.RandomSeed, "twister");
    phases = 2*pi*rand(packetCount, 1)-pi;
end

packets = cell(packetCount, 1);
packetInfo = cell(packetCount, 1);
for packet = 1:packetCount
    [packets{packet}, packetInfo{packet}] = lora_phy.build_lora_packet( ...
        uint8(payloads{packet}(:)), config, ...
        PreambleSymbols=options.PreambleSymbols, ...
        SyncWord=options.SyncWord, IqInverted=options.IqInverted, ...
        Amplitude=amplitudes(packet), ...
        InitialPhaseRadians=phases(packet));
end

leadingSamples = round(options.LeadingSilenceSeconds*sampleRateHz);
trailingSamples = round(options.TrailingSilenceSeconds*sampleRateHz);
gapSamples = round(gaps*sampleRateHz);
totalSamples = leadingSamples+trailingSamples+ ...
    sum(cellfun(@numel, packets))+sum(gapSamples);
stream = complex(zeros(totalSamples, 1));
rows = repmat(empty_truth_row(), packetCount, 1);
cursor = leadingSamples+1;
for packet = 1:packetCount
    indices = cursor+(0:numel(packets{packet})-1);
    stream(indices) = stream(indices)+packets{packet};
    info = packetInfo{packet};
    row = empty_truth_row();
    row.PacketIndex = packet;
    row.StartIndex = cursor;
    row.EndIndex = indices(end);
    row.PreambleStartIndex = cursor+info.preambleStartIndex-1;
    row.PayloadStartIndex = cursor+info.payloadStartIndex-1;
    row.Payload = {uint8(payloads{packet}(:))};
    row.Amplitude = amplitudes(packet);
    row.InitialPhaseRadians = phases(packet);
    rows(packet) = row;
    cursor = indices(end)+1;
    if packet < packetCount
        cursor = cursor+gapSamples(packet);
    end
end
truth = struct2table(rows);
metadata = struct;
metadata.sampleRateHz = sampleRateHz;
metadata.bandwidthHz = bandwidthHz;
metadata.durationSeconds = numel(stream)/sampleRateHz;
metadata.leadingSamples = leadingSamples;
metadata.trailingSamples = trailingSamples;
metadata.gapSamples = gapSamples;
metadata.preambleSymbols = options.PreambleSymbols;
metadata.syncWord = uint8(options.SyncWord);
metadata.iqInverted = options.IqInverted;
metadata.config = config;
end

function values = expand_parameter(values, count, name)
values = double(values(:));
if count == 0
    values = zeros(0, 1);
elseif isempty(values)
    return
elseif isscalar(values)
    values = repmat(values, count, 1);
elseif numel(values) ~= count
    error("lora_phy:StreamParameterLength", ...
        "%s must be scalar or contain %d values", name, count);
end
end

function row = empty_truth_row()
row = struct("PacketIndex", 0, "StartIndex", 0, "EndIndex", 0, ...
    "PreambleStartIndex", 0, "PayloadStartIndex", 0, ...
    "Payload", {cell(1, 1)}, "Amplitude", 0, ...
    "InitialPhaseRadians", 0);
end
