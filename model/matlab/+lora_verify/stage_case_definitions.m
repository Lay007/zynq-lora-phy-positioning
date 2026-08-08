function cases = stage_case_definitions
%STAGE_CASE_DEFINITIONS Deterministic FFT-correlator acceptance cases.
%
% Every case is fully described by this function: no random state leaks in
% from the caller. The set spans SF5/SF7/SF9/SF10/SF12, samplesPerChip
% L = 1/2/4/8, single and multi-symbol windows, AWGN, carrier offset, and
% integer plus fractional timing offsets.
%
% Fields:
%   id                       stable file/report identifier
%   spreadingFactor          5..12
%   samplesPerChip           L = Fs/BW
%   symbols                  transmitted CSS symbol indices for the window
%   bandwidthHz              nominal LoRa bandwidth
%   frequencyOffsetHz        carrier offset applied before extraction
%   fractionalDelaySamples   sub-sample delay applied to the stream
%   integerOffsetSamples     whole-sample misalignment of the window
%   snrDb                    Inf for a noiseless case
%   randomSeed               seed for the impairment model
%   note                     what the case is meant to exercise

fields = {"id", "spreadingFactor", "samplesPerChip", "symbols", ...
    "frequencyOffsetHz", "fractionalDelaySamples", ...
    "integerOffsetSamples", "snrDb", "randomSeed", "note"};

rows = {
    "sf7-l1-clean",     7,  1, [0, 45, 127],   0,      0,    0, Inf, 1001, "L=1 multi-symbol baseline"
    "sf7-l2-clean",     7,  2, [13, 100],      0,      0,    0, Inf, 1002, "L=2 multi-symbol baseline"
    "sf7-l4-clean",     7,  4, 63,             0,      0,    0, Inf, 1003, "L=4 single symbol"
    "sf7-l8-clean",     7,  8, 1,              0,      0,    0, Inf, 1004, "L=8 nominal operating point"
    "sf7-l8-awgn-p00",  7,  8, 77,             0,      0,    0,   0, 1005, "L=8 at 0 dB SNR"
    "sf7-l8-awgn-m10",  7,  8, 77,             0,      0,    0, -10, 1006, "L=8 at -10 dB SNR"
    "sf7-l8-cfo",       7,  8, 32,        1500.0,      0,    0, Inf, 1007, "carrier offset only"
    "sf7-l8-timing",    7,  8, 32,             0,   0.40,    3, Inf, 1008, "integer plus fractional timing offset"
    "sf7-l8-combined",  7,  8, [32, 96],  -900.0,   0.25,   -2,  -5, 1009, "CFO, timing offset, and noise"
    "sf5-l8-clean",     5,  8, [17, 3],        0,      0,    0, Inf, 1010, "shortest FFT with L=8"
    "sf5-l4-awgn",      5,  4, 30,             0,      0,    0,  -5, 1011, "SF5 with noise"
    "sf9-l2-clean",     9,  2, 300,            0,      0,    0, Inf, 1012, "SF9 baseline"
    "sf9-l2-combined",  9,  2, 511,        600.0,   0.75,    1,   0, 1013, "SF9 with CFO, timing, and noise"
    "sf10-l1-clean",   10,  1, 1000,           0,      0,    0, Inf, 1014, "SF10 critically sampled"
    "sf12-l1-clean",   12,  1, 4095,           0,      0,    0, Inf, 1015, "largest committed FFT length"
    };

cases = struct([]);
for k = 1:size(rows, 1)
    for f = 1:numel(fields)
        value = rows{k, f};
        if ischar(value)
            value = string(value);
        end
        cases(k, 1).(fields{f}) = value;
    end
    cases(k, 1).bandwidthHz = 125e3;
end
end
