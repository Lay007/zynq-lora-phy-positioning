function config = css_config(spreadingFactor, samplesPerChip)
%CSS_CONFIG Create and validate CSS symbol parameters.

if nargin < 1
    spreadingFactor = 7;
end
if nargin < 2
    samplesPerChip = 1;
end

validateattributes(spreadingFactor, {'numeric'}, ...
    {"scalar", "integer", ">=", 5, "<=", 12}, mfilename, "spreadingFactor");
validateattributes(samplesPerChip, {'numeric'}, ...
    {"scalar", "integer", ">=", 1}, mfilename, "samplesPerChip");

config = struct;
config.spreadingFactor = double(spreadingFactor);
config.samplesPerChip = double(samplesPerChip);
config.symbolCount = 2^config.spreadingFactor;
config.samplesPerSymbol = config.symbolCount * config.samplesPerChip;
end
