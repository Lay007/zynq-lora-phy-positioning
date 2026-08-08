function spectrum = polyphase_spectrum(dechirped, samplesPerChip)
%POLYPHASE_SPECTRUM Combine every oversampling phase after CSS dechirping.
%
% Each row of the polyphase matrix is a chip-rate view of the same symbol.
% Summing their FFT powers preserves the LoRa bin mapping while avoiding the
% information loss and phase sensitivity of selecting only one row.

arguments
    dechirped (:,1) {mustBeNumeric}
    samplesPerChip (1,1) double {mustBeInteger, mustBePositive}
end
if mod(numel(dechirped), samplesPerChip) ~= 0
    error("lora_phy:InvalidSampleCount", ...
        "Dechirped sample count must be divisible by samplesPerChip");
end
symbolCount = numel(dechirped)/samplesPerChip;
chipStreams = reshape(double(dechirped), samplesPerChip, symbolCount);
phaseSpectra = fft(chipStreams, [], 2);
spectrum = sum(abs(phaseSpectra).^2, 1).';
end
