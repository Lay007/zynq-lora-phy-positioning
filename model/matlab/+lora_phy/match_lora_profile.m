function profile = match_lora_profile(spreadingFactor, bandwidthHz, centreFrequencyHz)
%MATCH_LORA_PROFILE Match a LoRa PHY profile to common Semtech radios.
%
% The mapping is intentionally limited to modulation/frequency capability.
% It does not imply LoRaWAN regional compliance, output-power legality, or a
% validated register configuration.

if nargin < 3
    centreFrequencyHz = 0;
end

validateattributes(spreadingFactor, {'numeric'}, ...
    {'scalar', 'integer', '>=', 5, '<=', 12}, mfilename, 'spreadingFactor');
validateattributes(bandwidthHz, {'numeric'}, ...
    {'scalar', 'positive'}, mfilename, 'bandwidthHz');
validateattributes(centreFrequencyHz, {'numeric'}, ...
    {'scalar', 'nonnegative'}, mfilename, 'centreFrequencyHz');

% Semtech LoRa-family capability matrix used for engineering identification.
% Frequency limits are in Hz and BW limits in Hz. LR1121 values below describe
% its sub-GHz LoRa capability, which covers the project's 868 MHz captures.
radios = [ ...
    radio("LR1121", 150e6, 960e6, 5, 12, 62.5e3, 500e3); ...
    radio("SX1261", 150e6, 960e6, 5, 12, 7.8e3, 500e3); ...
    radio("SX1262", 150e6, 960e6, 5, 12, 7.8e3, 500e3); ...
    radio("SX1268", 410e6, 810e6, 5, 12, 7.8e3, 500e3); ...
    radio("LLCC68", 150e6, 960e6, 5, 11, 125e3, 500e3); ...
    radio("SX1272", 862e6, 1020e6, 6, 12, 125e3, 500e3); ...
    radio("SX1276", 137e6, 1020e6, 6, 12, 7.8e3, 500e3); ...
    radio("SX1278", 137e6, 525e6, 6, 12, 7.8e3, 500e3); ...
    radio("SX1280", 2400e6, 2500e6, 5, 12, 200e3, 1600e3); ...
    radio("SX1281", 2400e6, 2500e6, 5, 12, 200e3, 1600e3) ...
    ];

centreKnown = centreFrequencyHz > 0;
compatible = strings(0, 1);
for index = 1:numel(radios)
    item = radios(index);
    sfOk = spreadingFactor >= item.sfMin && spreadingFactor <= item.sfMax;
    bwOk = bandwidthHz >= item.bwMinHz && bandwidthHz <= item.bwMaxHz;
    frequencyOk = ~centreKnown || ...
        (centreFrequencyHz >= item.frequencyMinHz && ...
         centreFrequencyHz <= item.frequencyMaxHz);
    if sfOk && bwOk && frequencyOk
        compatible(end+1, 1) = item.name; %#ok<AGROW>
    end
end

profile = struct;
profile.modulation = "LoRa CSS";
profile.semtechPacketType = "PACKET_TYPE_LORA";
profile.spreadingFactor = spreadingFactor;
profile.bandwidthHz = bandwidthHz;
profile.centreFrequencyHz = centreFrequencyHz;
profile.centreFrequencyKnown = centreKnown;
profile.symbolDurationSeconds = 2^spreadingFactor / bandwidthHz;
profile.symbolRateBaud = bandwidthHz / 2^spreadingFactor;
profile.compatibleRadios = compatible;
profile.projectReferenceRadio = "SX1262";
profile.projectReferenceCompatible = any(compatible == profile.projectReferenceRadio);
profile.modeSummary = sprintf("LoRa / SF%d / BW %.0f kHz", ...
    spreadingFactor, bandwidthHz/1e3);

if centreKnown
    profile.frequencySummary = sprintf("%.3f MHz", centreFrequencyHz/1e6);
else
    profile.frequencySummary = "frequency not specified";
end

if isempty(compatible)
    profile.compatibilitySummary = "No match in the built-in Semtech table";
else
    profile.compatibilitySummary = strjoin(compatible, ", ");
end

profile.note = "LoRaWAN DR is region-dependent; this is a PHY/radio capability match.";
end

function item = radio(name, fMin, fMax, sfMin, sfMax, bwMin, bwMax)
item = struct( ...
    'name', name, ...
    'frequencyMinHz', fMin, ...
    'frequencyMaxHz', fMax, ...
    'sfMin', sfMin, ...
    'sfMax', sfMax, ...
    'bwMinHz', bwMin, ...
    'bwMaxHz', bwMax);
end
