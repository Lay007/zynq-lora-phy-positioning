function corpus = extract_real_symbol_windows(datasetDirectory, options)
%EXTRACT_REAL_SYMBOL_WINDOWS Corrected symbol windows from committed IQ.
%
% Decodes every capture of a reference sweep with the authoritative MATLAB
% receiver and returns the corrected per-symbol windows that the
% correlator actually consumed. Those windows are the Simulink and HDL
% stimulus for the real-signal regression.
%
% Each packet's windows are scaled to unit RMS. That is the documented AGC
% assumption of the fixed-point DUT: the hardware front end is expected to
% present a normalized sample stream, and the capture gain of a particular
% recording session must not decide the word length.
%
% The result is cached, because decoding five 6-Msample captures takes
% minutes and the regression is run repeatedly.

arguments
    datasetDirectory (1,1) string
    options.CacheFile string = string.empty
    options.UseCache (1,1) logical = true
end

if isempty(options.CacheFile)
    options.CacheFile = fullfile(lora_sim.generated_directory, ...
        "real-symbol-windows.mat");
end
if options.UseCache && isfile(options.CacheFile)
    loaded = load(options.CacheFile, "corpus");
    corpus = loaded.corpus;
    return;
end

manifest = jsondecode(fileread(fullfile(datasetDirectory, "manifest.json")));
entries = struct([]);

for index = 1:numel(manifest.captures)
    item = manifest.captures(index);
    name = string(item.name);
    capturePath = fullfile(datasetDirectory, string(item.capture.path));
    [iq, ~] = lora_phy.load_iq_capture(capturePath, "cf32");
    syncWord = hex2dec(extractAfter(string(item.transmitter.sync_word), "0x"));

    receptionSet = lora_phy.receive_lora_packets(iq, ...
        item.receiver.sample_rate_hz, item.transmitter.bandwidth_hz, ...
        item.transmitter.spreading_factor, ...
        PreambleSymbols=item.transmitter.preamble_symbols, ...
        SyncWord=syncWord, IqInverted=item.transmitter.iq_inverted, ...
        ExpectedCarrierOffsetHz=item.transmitter.frequency_hz- ...
            item.receiver.center_frequency_hz, ...
        SoftDecoding=true, ReturnSymbolWindows=true);

    samplesPerChip = round(item.receiver.sample_rate_hz/ ...
        item.transmitter.bandwidth_hz);
    config = lora_phy.css_config(item.transmitter.spreading_factor, ...
        samplesPerChip);

    packets = receptionSet.packets;
    for k = 1:numel(packets)
        packet = packets(k);
        windows = packet.symbolWindows;
        if isempty(windows)
            continue;
        end
        rmsLevel = sqrt(mean(abs(windows(:)).^2));
        if rmsLevel <= 0
            continue;
        end
        entry = struct;
        entry.capture = name;
        entry.transmissionIndex = k;
        entry.spreadingFactor = config.spreadingFactor;
        entry.samplesPerChip = config.samplesPerChip;
        entry.symbolCount = config.symbolCount;
        entry.samplesPerSymbol = config.samplesPerSymbol;
        entry.bandwidthHz = item.transmitter.bandwidth_hz;
        entry.sampleRateHz = item.receiver.sample_rate_hz;
        entry.scale = 1/rmsLevel;
        entry.windows = windows*entry.scale;
        entry.receiverSymbols = packet.symbols(:);
        entry.adaptiveReference = packet.correlationReference;
        entry.crcValid = packet.decoded.crcValid;
        entries = [entries; entry]; %#ok<AGROW>
    end

    fprintf("%-22s SF%-2d L=%d packets=%d\n", name, ...
        config.spreadingFactor, config.samplesPerChip, numel(packets));
end

corpus = struct;
corpus.datasetDirectory = datasetDirectory;
corpus.packets = entries;
corpus.packetCount = numel(entries);
corpus.symbolCount = sum(arrayfun(@(e) size(e.windows, 2), entries));
corpus.normalization = "per-packet unit RMS";

directory = fileparts(options.CacheFile);
if ~isempty(directory) && ~isfolder(directory)
    mkdir(directory);
end
save(options.CacheFile, "corpus", "-v7.3");
end
