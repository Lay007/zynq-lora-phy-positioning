function [state, outputs] = packet_frame_step(state, event, config)
%PACKET_FRAME_STEP One symbol through the packet framing state machine.
%
% The stage that turns "a packet is here and the grid is aligned" into a
% routed symbol stream. Explicit state in and out rather than persistent
% variables, so the same function is a pure MATLAB reference, a Simulink
% MATLAB Function block, and a thing tests can drive one symbol at a time.
%
% Phases, in order:
%
%   idle     nothing found; waits for preambleDetected
%   sync     the two sync-word symbols
%   sfd      the downchirp pair, checked against the mirrored preamble bin
%   header   HeaderSymbols symbols routed to the header decoder
%   payload  PayloadSymbols symbols routed to the payload decoder
%
% Header and payload lengths are configured rather than derived. LoRa gets
% the payload symbol count from the decoded header, which lives in software
% behind the documented interface, and inventing a second copy of that
% arithmetic in the framing path would be a good way to have two that
% disagree. The FSM's job is routing and re-arming, not packet algebra.
%
% Re-arming is the point of the state machine as much as routing is. The
% front-end realigns once per reset; without a stage that knows a packet has
% ended, a receiver acquires one packet and then ignores the radio.
%
% STATE is built by LORA_PHY.PACKET_FRAME_RESET.
% EVENT fields: symbolIndex, symbolValid, preambleDetected, preambleBin,
%   syncValid, sfdValid.
% OUTPUTS fields: phase, headerValid, payloadValid, symbolOut, packetDone,
%   framingFailed.

arguments
    state (1,1) struct
    event (1,1) struct
    config (1,1) struct %#ok<INUSA>
end

outputs = struct("phase", state.phase, "headerValid", false, ...
    "payloadValid", false, "symbolOut", uint16(0), ...
    "packetDone", false, "framingFailed", false);

if ~event.symbolValid
    return;
end

switch state.phase
    case "idle"
        if event.preambleDetected
            state.phase = "sync";
            state.remaining = 2;
            state.preambleBin = double(event.preambleBin);
        end

    case "sync"
        state.remaining = state.remaining-1;
        if state.remaining <= 0
            if event.syncValid
                state.phase = "sfd";
                state.remaining = 2;
            else
                % Not a packet after all. Re-arm rather than stall: the
                % radio keeps running whether or not this candidate was
                % real.
                state = lora_phy.packet_frame_reset(state);
                outputs.framingFailed = true;
            end
        end

    case "sfd"
        state.remaining = state.remaining-1;
        if state.remaining <= 0
            if event.sfdValid
                state.phase = "header";
                state.remaining = state.headerSymbols;
            else
                state = lora_phy.packet_frame_reset(state);
                outputs.framingFailed = true;
            end
        end

    case "header"
        outputs.headerValid = true;
        outputs.symbolOut = uint16(event.symbolIndex);
        state.remaining = state.remaining-1;
        if state.remaining <= 0
            state.phase = "payload";
            state.remaining = state.payloadSymbols;
            if state.remaining <= 0
                state = lora_phy.packet_frame_reset(state);
                outputs.packetDone = true;
            end
        end

    case "payload"
        outputs.payloadValid = true;
        outputs.symbolOut = uint16(event.symbolIndex);
        state.remaining = state.remaining-1;
        if state.remaining <= 0
            state = lora_phy.packet_frame_reset(state);
            outputs.packetDone = true;
        end

    otherwise
        error("lora_phy:InvalidFramingPhase", ...
            "Unknown framing phase '%s'", state.phase);
end

state.symbolsSeen = state.symbolsSeen+1;
outputs.phase = state.phase;
end
