classdef TestPacketFraming < matlab.unittest.TestCase
    %TESTPACKETFRAMING Symbol routing and re-arming after a packet.

    methods (Test)
        function aWholePacketIsRoutedThenRearmed(testCase)
            config = lora_phy.css_config(7, 4);
            state = testCase.freshState(8, 5);

            [state, log] = testCase.drive(state, config, ...
                testCase.packetEvents(8, 5));

            testCase.verifyEqual(sum([log.headerValid]), 8);
            testCase.verifyEqual(sum([log.payloadValid]), 5);
            testCase.verifyEqual(sum([log.packetDone]), 1);
            testCase.verifyEqual(sum([log.framingFailed]), 0);
            testCase.verifyEqual(state.phase, "idle", ...
                "the FSM must re-arm once the packet ends");
        end

        function twoPacketsBackToBackAreBothRouted(testCase)
            % The failure this stage exists to prevent: acquiring one packet
            % and then ignoring the radio. The front-end realigns once per
            % reset, so re-arming has to happen here.
            config = lora_phy.css_config(7, 4);
            state = testCase.freshState(8, 5);
            events = [testCase.packetEvents(8, 5); ...
                testCase.packetEvents(8, 5)];

            [state, log] = testCase.drive(state, config, events);

            testCase.verifyEqual(sum([log.packetDone]), 2);
            testCase.verifyEqual(sum([log.headerValid]), 16);
            testCase.verifyEqual(sum([log.payloadValid]), 10);
            testCase.verifyEqual(state.phase, "idle");
        end

        function symbolsAreRoutedInOrderAndUnchanged(testCase)
            config = lora_phy.css_config(7, 4);
            state = testCase.freshState(3, 4);
            events = testCase.packetEvents(3, 4);
            for k = 1:numel(events)
                events(k).symbolIndex = k;
            end

            [~, log] = testCase.drive(state, config, events);

            header = [log([log.headerValid]).symbolOut];
            payload = [log([log.payloadValid]).symbolOut];
            % Event 1 is the symbol the detector asserts on, 2-3 are the
            % sync word and 4-5 the SFD, so the header starts at 6.
            testCase.verifyEqual(double(header), 6:8, ...
                "header symbols follow the detection symbol, sync and SFD");
            testCase.verifyEqual(double(payload), 9:12);
        end

        function aRejectedSyncWordRearmsInsteadOfStalling(testCase)
            config = lora_phy.css_config(7, 4);
            state = testCase.freshState(8, 5);
            events = testCase.packetEvents(8, 5);
            events(3).syncValid = false;   % second sync symbol

            [state, log] = testCase.drive(state, config, events);

            testCase.verifyEqual(sum([log.framingFailed]), 1);
            testCase.verifyEqual(sum([log.headerValid]), 0);
            testCase.verifyEqual(state.phase, "idle");
        end

        function aRejectedSfdRearmsInsteadOfStalling(testCase)
            config = lora_phy.css_config(7, 4);
            state = testCase.freshState(8, 5);
            events = testCase.packetEvents(8, 5);
            events(5).sfdValid = false;    % second SFD symbol

            [state, log] = testCase.drive(state, config, events);

            testCase.verifyEqual(sum([log.framingFailed]), 1);
            testCase.verifyEqual(sum([log.headerValid]), 0);
            testCase.verifyEqual(state.phase, "idle");
        end

        function invalidSymbolsDoNotAdvanceTheMachine(testCase)
            config = lora_phy.css_config(7, 4);
            state = testCase.freshState(8, 5);
            event = testCase.baseEvent;
            event.symbolValid = false;
            event.preambleDetected = true;

            [after, outputs] = lora_phy.packet_frame_step(state, event, config);

            testCase.verifyEqual(after.phase, "idle");
            testCase.verifyEqual(after.symbolsSeen, state.symbolsSeen);
            testCase.verifyFalse(outputs.headerValid);
        end

        function anEmptyPayloadStillCompletesThePacket(testCase)
            config = lora_phy.css_config(7, 4);
            state = testCase.freshState(2, 0);

            [state, log] = testCase.drive(state, config, ...
                testCase.packetEvents(2, 0));

            testCase.verifyEqual(sum([log.packetDone]), 1);
            testCase.verifyEqual(sum([log.payloadValid]), 0);
            testCase.verifyEqual(state.phase, "idle");
        end
    end

    methods (Static, Access = private)
        function state = freshState(headerSymbols, payloadSymbols)
            state = lora_phy.packet_frame_reset( ...
                struct("headerSymbols", headerSymbols, ...
                    "payloadSymbols", payloadSymbols));
        end

        function event = baseEvent
            event = struct("symbolIndex", 0, "symbolValid", true, ...
                "preambleDetected", false, "preambleBin", 0, ...
                "syncValid", true, "sfdValid", true);
        end

        function events = packetEvents(headerSymbols, payloadSymbols)
            %PACKETEVENTS One clean packet: detect, sync, SFD, header, payload.
            events = TestPacketFraming.baseEvent;
            events(1).preambleDetected = true;
            total = 1+2+2+headerSymbols+payloadSymbols;
            for k = 2:total
                events(k) = TestPacketFraming.baseEvent;
            end
            events = events(:);
        end

        function [state, log] = drive(state, config, events)
            log = [];
            for k = 1:numel(events)
                [state, outputs] = lora_phy.packet_frame_step( ...
                    state, events(k), config);
                if isempty(log)
                    log = outputs;
                else
                    log(k) = outputs; %#ok<AGROW>
                end
            end
        end
    end
end
