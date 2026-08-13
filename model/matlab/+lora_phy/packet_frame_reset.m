function state = packet_frame_reset(state)
%PACKET_FRAME_RESET Idle framing state, keeping the configured lengths.
%
% Called both to build the initial state and to re-arm after a packet ends
% or a candidate is rejected, which is why it preserves the configured
% symbol counts instead of returning a bare struct.
%
%   state = lora_phy.packet_frame_reset(HeaderSymbols=8, PayloadSymbols=20);
%   state = lora_phy.packet_frame_reset(state);

arguments
    state struct = struct.empty
end

if isempty(state)
    state = struct("headerSymbols", 8, "payloadSymbols", 0);
end
if ~isfield(state, "headerSymbols")
    state.headerSymbols = 8;
end
if ~isfield(state, "payloadSymbols")
    state.payloadSymbols = 0;
end

state.phase = "idle";
state.remaining = 0;
state.preambleBin = 0;
if ~isfield(state, "symbolsSeen")
    state.symbolsSeen = 0;
end
end
