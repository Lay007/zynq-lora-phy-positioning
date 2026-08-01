function waveform = preamble_waveform(config, upchirpCount, downchirpCount)
%PREAMBLE_WAVEFORM Build a known CSS acquisition preamble.
%
% This research preamble is not a complete LoRa standard preamble. The
% upchirp/downchirp transition provides an unambiguous timing marker for the
% floating-point synchronization model.

if nargin < 2
    upchirpCount = 8;
end
if nargin < 3
    downchirpCount = 2;
end

validateattributes(upchirpCount, {'numeric'}, ...
    {'scalar', 'integer', '>=', 2}, mfilename, 'upchirpCount');
validateattributes(downchirpCount, {'numeric'}, ...
    {'scalar', 'integer', '>=', 1}, mfilename, 'downchirpCount');

upchirp = lora_phy.reference_chirp(config, "up");
downchirp = lora_phy.reference_chirp(config, "down");
waveform = [repmat(upchirp, upchirpCount, 1); ...
    repmat(downchirp, downchirpCount, 1)];
end
