function [waveform, info] = build_lora_packet(payload, config, options)
%BUILD_LORA_PACKET Build a complete floating-point LoRa packet waveform.

arguments
    payload (:,1) {mustBeNumeric}
    config (1,1) struct
    options.PreambleSymbols (1,1) double ...
        {mustBeInteger, mustBePositive} = 8
    options.SyncWord (1,1) double ...
        {mustBeInteger, mustBeNonnegative} = hex2dec("12")
    options.IqInverted (1,1) logical = false
    options.AddLowSfPadding (1,1) logical = true
    options.Amplitude (1,1) double {mustBePositive} = 1
    options.InitialPhaseRadians (1,1) double = 0
end

if options.SyncWord > 255
    error("lora_phy:InvalidSyncWord", "SyncWord must fit one byte");
end
payload = uint8(payload(:));
encoded = lora_phy.encode_packet(payload, config);
upchirp = lora_phy.reference_chirp(config, "up");
downchirp = lora_phy.reference_chirp(config, "down");
syncNibbles = double([bitshift(uint8(options.SyncWord), -4); ...
    bitand(uint8(options.SyncWord), 15)]);
syncSymbols = mod(8*syncNibbles, config.symbolCount);
syncWaveform = [lora_phy.modulate_symbol(syncSymbols(1), config); ...
    lora_phy.modulate_symbol(syncSymbols(2), config)];
quarterChirpSamples = config.samplesPerSymbol/4;
if quarterChirpSamples ~= fix(quarterChirpSamples)
    error("lora_phy:InvalidQuarterChirp", ...
        "The configured CSS symbol must contain an integer quarter chirp");
end
sfd = [downchirp; downchirp; downchirp(1:quarterChirpSamples)];
lowSfPaddingSymbols = 0;
if options.AddLowSfPadding && config.spreadingFactor < 7
    lowSfPaddingSymbols = 2;
    sfd = [sfd; repmat(upchirp, lowSfPaddingSymbols, 1)];
end
preamble = repmat(upchirp, options.PreambleSymbols, 1);
payloadWaveform = lora_phy.modulate(encoded.symbols, config);
waveform = [preamble; syncWaveform; sfd; payloadWaveform];
waveform = options.Amplitude*waveform*exp(1j*options.InitialPhaseRadians);
if options.IqInverted
    waveform = conj(waveform);
end

info = struct;
info.payload = payload;
info.encoded = encoded;
info.preambleSymbols = options.PreambleSymbols;
info.syncWord = uint8(options.SyncWord);
info.syncSymbols = syncSymbols;
info.iqInverted = options.IqInverted;
info.lowSfPaddingSymbols = lowSfPaddingSymbols;
info.preambleStartIndex = 1;
info.syncStartIndex = numel(preamble)+1;
info.sfdStartIndex = info.syncStartIndex+numel(syncWaveform);
info.payloadStartIndex = info.sfdStartIndex+numel(sfd);
info.packetEndIndex = numel(waveform);
info.packetSamples = numel(waveform);
end
