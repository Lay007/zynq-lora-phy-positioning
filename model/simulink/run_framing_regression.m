function report = run_framing_regression(options)
%RUN_FRAMING_REGRESSION Check the framing FSM against MATLAB.
%
% Per symbol, on exact equality: the DUT and LORA_PHY.PACKET_FRAME_STEP are
% the same state machine written twice, so anything but bit-exact agreement
% is a defect rather than a tolerance question.
%
% The stimulus mixes clean packets with the two rejection paths and with
% back-to-back packets, because the property worth checking is not only that
% a packet is routed but that the machine re-arms afterwards. A framing FSM
% that parks after one packet passes every single-packet test.

arguments
    options.HeaderSymbols (1,1) double = 8
    options.PayloadSymbols (1,1) double = 5
    options.RandomEvents (1,1) double = 300
    options.RandomSeed (1,1) double = 20260813
    options.OutputDirectory string = string.empty
    options.WriteCsv (1,1) logical = true
    options.Verbose (1,1) logical = true
end

simulinkRoot = fileparts(mfilename("fullpath"));
repositoryRoot = fileparts(fileparts(simulinkRoot));
addpath(simulinkRoot);
addpath(fullfile(repositoryRoot, "model", "matlab"));
if isempty(options.OutputDirectory)
    options.OutputDirectory = string(fullfile(repositoryRoot, "docs", "data"));
end

config = lora_phy.css_config(7, 4);
events = buildEvents(options);
total = numel(events);

info = build_framing_model(HeaderSymbols=options.HeaderSymbols, ...
    ModelName="lora_framing_check");
cleanup = onCleanup(@() closeIfLoaded(info.modelName));

timeAxis = (0:total-1).';
assignin("base", "stimulusSymbolIndex", ...
    timeseries(uint16([events.symbolIndex].'), timeAxis));
assignin("base", "stimulusSymbolValid", ...
    timeseries(logical([events.symbolValid].'), timeAxis));
assignin("base", "stimulusPreambleDetected", ...
    timeseries(logical([events.preambleDetected].'), timeAxis));
assignin("base", "stimulusSyncValid", ...
    timeseries(logical([events.syncValid].'), timeAxis));
assignin("base", "stimulusSfdValid", ...
    timeseries(logical([events.sfdValid].'), timeAxis));
assignin("base", "stimulusHeaderSymbols", ...
    timeseries(uint16(options.HeaderSymbols)*ones(total, 1, "uint16"), ...
    timeAxis));
assignin("base", "stimulusPayloadSymbols", ...
    timeseries(uint16(options.PayloadSymbols)*ones(total, 1, "uint16"), ...
    timeAxis));
assignin("base", "stimulusReset", timeseries(false(total, 1), timeAxis));

if ~bdIsLoaded(info.modelName)
    load_system(info.modelPath);
end
set_param(info.modelName, StopTime=num2str(total-1));
out = sim(info.modelName);

phaseNames = ["idle", "sync", "sfd", "header", "payload"];
state = lora_phy.packet_frame_reset(struct( ...
    "headerSymbols", options.HeaderSymbols, ...
    "payloadSymbols", options.PayloadSymbols));

expected = struct("phase", zeros(total, 1), "headerValid", ...
    false(total, 1), "payloadValid", false(total, 1), ...
    "symbolOut", zeros(total, 1), "packetDone", false(total, 1), ...
    "framingFailed", false(total, 1));
for k = 1:total
    [state, step] = lora_phy.packet_frame_step(state, events(k), config);
    expected.phase(k) = find(phaseNames == step.phase)-1;
    expected.headerValid(k) = step.headerValid;
    expected.payloadValid(k) = step.payloadValid;
    expected.symbolOut(k) = double(step.symbolOut);
    expected.packetDone(k) = step.packetDone;
    expected.framingFailed(k) = step.framingFailed;
end

names = ["phase", "headerValid", "payloadValid", "symbolOut", ...
    "packetDone", "framingFailed"];
mismatches = zeros(1, numel(names));
for k = 1:numel(names)
    actual = double(out.(names(k))(:));
    mismatches(k) = sum(actual ~= double(expected.(names(k))));
end

report = struct;
report.summary = table(total, sum(expected.packetDone), ...
    sum(expected.framingFailed), sum(expected.headerValid), ...
    sum(expected.payloadValid), mismatches(1), mismatches(2), ...
    mismatches(3), mismatches(4), mismatches(5), mismatches(6), ...
    VariableNames=["Symbols", "PacketsCompleted", "Rejections", ...
    "HeaderSymbols", "PayloadSymbols", "PhaseMismatches", ...
    "HeaderMismatches", "PayloadMismatches", "SymbolMismatches", ...
    "DoneMismatches", "FailedMismatches"]);

failures = strings(0, 1);
if sum(mismatches) > 0
    failures(end+1, 1) = sprintf( ...
        "%d mismatching outputs over %d symbols", sum(mismatches), total);
end
% A regression that never completes a packet, or never rejects one, is not
% exercising the machine.
if sum(expected.packetDone) < 2
    failures(end+1, 1) = "stimulus must complete at least two packets";
end
if sum(expected.framingFailed) < 1
    failures(end+1, 1) = "stimulus must exercise a rejection path";
end
report.failures = failures;
report.passed = isempty(failures);

if options.WriteCsv
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(report.summary, fullfile(options.OutputDirectory, ...
        "simulink-m2-framing.csv"));
end

if options.Verbose
    disp(report.summary);
    if report.passed
        fprintf("Framing FSM matches MATLAB over %d symbols " + ...
            "(%d packets, %d rejections).\n", total, ...
            sum(expected.packetDone), sum(expected.framingFailed));
    else
        fprintf("FAILURES:\n  %s\n", strjoin(failures, newline+"  "));
    end
end
end

function events = buildEvents(options)
%BUILDEVENTS Clean packets, both rejection paths, and random noise.
blocks = {};
blocks{end+1} = packet(options, true, true);
blocks{end+1} = packet(options, true, true);          % back to back
blocks{end+1} = packet(options, false, true);         % sync rejected
blocks{end+1} = packet(options, true, false);         % SFD rejected
blocks{end+1} = packet(options, true, true);          % recovers afterwards

rng(options.RandomSeed, "twister");
noise = repmat(baseEvent, options.RandomEvents, 1);
for k = 1:options.RandomEvents
    noise(k).symbolIndex = randi([0, 127]);
    noise(k).symbolValid = rand > 0.1;
    noise(k).preambleDetected = rand > 0.9;
    noise(k).syncValid = rand > 0.5;
    noise(k).sfdValid = rand > 0.5;
end
blocks{end+1} = noise;

events = vertcat(blocks{:});
for k = 1:numel(events)
    events(k).symbolIndex = mod(k, 128);
end
end

function events = packet(options, syncOk, sfdOk)
count = 1+2+2+options.HeaderSymbols+options.PayloadSymbols;
events = repmat(baseEvent, count, 1);
events(1).preambleDetected = true;
if ~syncOk
    events(3).syncValid = false;
end
if ~sfdOk
    events(5).sfdValid = false;
end
end

function event = baseEvent
event = struct("symbolIndex", 0, "symbolValid", true, ...
    "preambleDetected", false, "preambleBin", 0, ...
    "syncValid", true, "sfdValid", true);
end

function closeIfLoaded(modelName)
if bdIsLoaded(modelName)
    set_param(modelName, Dirty="off");
    close_system(modelName, 0);
end
end
