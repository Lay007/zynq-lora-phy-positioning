function report = run_real_iq_regression(options)
%RUN_REAL_IQ_REGRESSION Push real SX1262 symbol windows through the DUT.
%
% The committed SX1262 -> ZynqSDR captures are decoded by the authoritative
% MATLAB receiver, the corrected symbol windows it consumed are extracted,
% normalized to unit RMS, and replayed through the fixed-point Simulink DUT.
%
% Two different questions are answered and never mixed:
%
%   1. Does the fixed-point DUT reproduce the floating-point correlator on
%      real signal statistics? Both sides use the nominal reference chirp,
%      so any difference is quantization.
%   2. How often does the nominal-reference correlator inside the DUT agree
%      with the packet receiver, which uses a preamble-estimated adaptive
%      reference that the DUT does not implement yet?
%
% Only the windows the decoder actually consumed are replayed. The receiver
% demodulates past the packet while searching timing, and that tail is the
% noise floor: replaying it would score argmax on noise and would stretch the
% fixed-point range analysis across seven decades for no signal.
%
% Range analysis is collected from the real windows themselves, because the
% integer bits of a fixed-point design must follow the stimulus it will see.
% The word length is the parameter carried over from the synthetic sweep.

arguments
    options.WordLength (1,1) double {mustBeInteger, mustBePositive} = 14
    options.DatasetDirectory string = string.empty
    options.GuardBits (1,1) double = 1
    options.Rounding (1,1) string = "Floor"
    options.Overflow (1,1) string = "Saturate"
    options.MaxStepsPerRun (1,1) double = 150000
    options.OutputDirectory string = string.empty
    options.WriteCsv (1,1) logical = true
    options.UseCache (1,1) logical = true
    options.Verbose (1,1) logical = true
end

simulinkRoot = fileparts(mfilename("fullpath"));
repositoryRoot = fileparts(fileparts(simulinkRoot));
addpath(simulinkRoot);
addpath(fullfile(repositoryRoot, "model", "matlab"));
if isempty(options.DatasetDirectory)
    options.DatasetDirectory = string(fullfile(repositoryRoot, "captures", ...
        "reference", "2026-08-07-heltec-v43-zynqsdr-targeted"));
end
if isempty(options.OutputDirectory)
    options.OutputDirectory = string(fullfile(repositoryRoot, "docs", "data"));
end

corpus = lora_sim.extract_real_symbol_windows(options.DatasetDirectory, ...
    UseCache=options.UseCache);
if corpus.packetCount == 0
    error("lora_sim:NoRealPackets", ...
        "No packets with symbol windows were extracted from %s", ...
        options.DatasetDirectory);
end

configurations = unique([[corpus.packets.spreadingFactor].', ...
    [corpus.packets.samplesPerChip].'], "rows");

info = struct.empty;
groupBlocks = {};
packetBlocks = {};

for row = 1:size(configurations, 1)
    spreadingFactor = configurations(row, 1);
    samplesPerChip = configurations(row, 2);
    selection = find([corpus.packets.spreadingFactor] == spreadingFactor & ...
        [corpus.packets.samplesPerChip] == samplesPerChip);
    config = lora_phy.css_config(spreadingFactor, samplesPerChip);
    m = config.samplesPerSymbol;

    allWindows = [corpus.packets(selection).windows];
    ranges = lora_sim.ranges_from_windows(allWindows, config);

    closeGeneratedModel(info);
    info = build_fft_correlator_model(SpreadingFactor=spreadingFactor, ...
        SamplesPerChip=samplesPerChip, DataType="fixed", ...
        WordLength=options.WordLength, GuardBits=options.GuardBits, ...
        Rounding=options.Rounding, Overflow=options.Overflow, ...
        Ranges=ranges, ModelName="lora_fft_correlator_real");

    totalSymbols = size(allWindows, 2);
    chunkSymbols = max(1, min(totalSymbols, ...
        floor(options.MaxStepsPerRun/m)));

    fixedSymbols = zeros(totalSymbols, 1);
    fixedConfidence = zeros(totalSymbols, 1);
    nominalSymbols = zeros(totalSymbols, 1);
    nominalConfidence = zeros(totalSymbols, 1);
    worstRelative = 0;
    worstAbsolute = 0;
    stageNames = ["fftM"; "product"; "partition"; "fftN"; "magnitudeSquared"];

    % The floating-point reference is recomputed per chunk. A whole capture
    % holds thousands of symbols and keeping every stage of all of them
    % resident would cost hundreds of megabytes for no benefit.
    % Every chunk is exactly chunkSymbols long, the short final one padded by
    % repeating its first window. A constant stimulus length keeps StopTime
    % constant, so Simulink compiles the model once per configuration instead
    % of once per chunk, which dominates the run time otherwise.
    cursor = 1;
    while cursor <= totalSymbols
        stop = min(totalSymbols, cursor+chunkSymbols-1);
        used = stop-cursor+1;
        block = allWindows(:, cursor:stop);
        if used < chunkSymbols
            block = [block, repmat(block(:, 1), 1, chunkSymbols-used)]; %#ok<AGROW>
        end
        expected = lora_phy.fft_correlator_stages(block(:), config);
        result = lora_sim.simulate_correlator(info, block(:));

        fixedSymbols(cursor:stop) = result.symbols(1:used);
        fixedConfidence(cursor:stop) = result.confidence(1:used);
        nominalSymbols(cursor:stop) = expected.symbols(1:used);
        nominalConfidence(cursor:stop) = expected.confidence(1:used);

        keep = 1:used;
        trimmedExpected = struct;
        trimmedActual = struct;
        for name = stageNames.'
            trimmedExpected.(name) = expected.(name)(:, keep);
            trimmedActual.(name) = result.(name)(:, keep);
        end
        comparison = lora_verify.compare_stages(trimmedExpected, ...
            trimmedActual, stageNames);
        worstRelative = max(worstRelative, max(comparison.RelativeRms));
        worstAbsolute = max(worstAbsolute, max(comparison.MaxAbsError));
        cursor = stop+1;
    end

    fixedVsFloat = sum(fixedSymbols == nominalSymbols);

    offset = 0;
    for k = selection
        packet = corpus.packets(k);
        count = size(packet.windows, 2);
        indices = offset+(1:count);
        offset = offset+count;
        packetFixed = fixedSymbols(indices);
        packetNominal = nominalSymbols(indices);
        packetReceiver = packet.receiverSymbols(:);
        packetBlocks{end+1} = table(string(packet.capture), ...
            packet.transmissionIndex, spreadingFactor, samplesPerChip, ...
            count, sum(packetFixed == packetNominal), ...
            sum(packetNominal == packetReceiver), ...
            sum(packetFixed == packetReceiver), packet.crcValid, ...
            VariableNames=["Capture", "Packet", "SF", "L", "Symbols", ...
            "FixedMatchesFloat", "FloatMatchesReceiver", ...
            "FixedMatchesReceiver", "ReceiverCrcValid"]); %#ok<AGROW>
    end

    receiverSymbols = vertcat(corpus.packets(selection).receiverSymbols);
    groupBlocks{end+1} = table(spreadingFactor, samplesPerChip, m, ...
        numel(selection), totalSymbols, fixedVsFloat, ...
        sum(nominalSymbols == receiverSymbols), ...
        sum(fixedSymbols == receiverSymbols), ...
        worstRelative, worstAbsolute, ...
        max(abs(fixedConfidence-nominalConfidence)), ...
        string(info.types.input.name), string(info.types.reference.name), ...
        string(info.types.product.name), ...
        string(info.types.accumulator.name), ...
        string(info.types.fftN.name), ...
        string(info.types.magnitudeSquared.name), ...
        VariableNames=["SF", "L", "M", "Packets", "Symbols", ...
        "FixedMatchesFloat", "FloatMatchesReceiver", ...
        "FixedMatchesReceiver", "WorstRelativeRms", "WorstMaxAbsError", ...
        "WorstConfidenceAbsError", "InputType", "ReferenceType", ...
        "ProductType", "AccumulatorType", "FftNType", ...
        "MagnitudeType"]); %#ok<AGROW>

    if options.Verbose
        fprintf("SF%-2d L=%d packets=%-3d symbols=%-5d fixed==float %d/%d " + ...
            "worstRel=%.3e\n", spreadingFactor, samplesPerChip, ...
            numel(selection), totalSymbols, fixedVsFloat, totalSymbols, ...
            worstRelative);
    end
end

closeGeneratedModel(info);

groups = vertcat(groupBlocks{:});
packets = vertcat(packetBlocks{:});

report = struct;
report.wordLength = options.WordLength;
report.groups = groups;
report.packets = packets;
report.packetCount = height(packets);
report.symbolCount = sum(groups.Symbols);
report.fixedMatchesFloat = sum(groups.FixedMatchesFloat);
report.floatMatchesReceiver = sum(groups.FloatMatchesReceiver);
report.fixedMatchesReceiver = sum(groups.FixedMatchesReceiver);
report.worstRelativeRms = max(groups.WorstRelativeRms);
report.passed = report.fixedMatchesFloat == report.symbolCount;

if options.WriteCsv
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(groups, fullfile(options.OutputDirectory, ...
        "simulink-m2-real-iq-groups.csv"));
    writetable(packets, fullfile(options.OutputDirectory, ...
        "simulink-m2-real-iq-packets.csv"));
end

if options.Verbose
    fprintf("\npackets=%d symbols=%d\n", report.packetCount, ...
        report.symbolCount);
    fprintf("fixed-point == floating-point : %d/%d\n", ...
        report.fixedMatchesFloat, report.symbolCount);
    fprintf("nominal reference == receiver : %d/%d\n", ...
        report.floatMatchesReceiver, report.symbolCount);
    fprintf("fixed-point == receiver       : %d/%d\n", ...
        report.fixedMatchesReceiver, report.symbolCount);
    fprintf("worst relative RMS            : %.3e\n", ...
        report.worstRelativeRms);
end
end

function closeGeneratedModel(info)
if isempty(info) || ~isfield(info, "modelName")
    return;
end
if bdIsLoaded(info.modelName)
    set_param(info.modelName, Dirty="off");
    close_system(info.modelName, 0);
end
end
