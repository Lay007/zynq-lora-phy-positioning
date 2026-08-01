function config = phy_config(spreadingFactor, samplesPerChip, codingRate)
%PHY_CONFIG Create parameters for the floating-point LoRa PHY packet model.

if nargin < 1
    spreadingFactor = 7;
end
if nargin < 2
    samplesPerChip = 2;
end
if nargin < 3
    codingRate = 1;
end

config = lora_phy.css_config(spreadingFactor, samplesPerChip);
validateattributes(codingRate, {'numeric'}, ...
    {"scalar", "integer", ">=", 1, "<=", 4}, mfilename, "codingRate");

config.codingRate = double(codingRate);
config.payloadCrc = true;
config.explicitHeader = true;
config.lowDataRateOptimization = false;
end
