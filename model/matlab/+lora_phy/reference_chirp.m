function chirp = reference_chirp(config, direction)
%REFERENCE_CHIRP Generate one unit-amplitude periodic CSS chirp.

if nargin < 2
    direction = "up";
end

sampleCount = config.samplesPerSymbol;
n = (0:sampleCount-1).';
phaseCycles = 0.5 * n.^2 / sampleCount - 0.5 * n;
chirp = exp(2j * pi * phaseCycles);

if direction == "down"
    chirp = conj(chirp);
elseif direction ~= "up"
    error("lora_phy:InvalidDirection", ...
        "direction must be either 'up' or 'down'");
end
end
