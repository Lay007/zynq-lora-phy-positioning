function ranges = stage_ranges(spreadingFactor, samplesPerChip)
%STAGE_RANGES Measured dynamic range per stage for one SF/L configuration.
%
% Range analysis is driven by the committed golden vectors rather than by
% an analytical bound: every acceptance case that uses this configuration
% contributes its maximum magnitude. Complex stages report max|z|, which
% upper-bounds both the real and the imaginary part.
%
% SPECTRUMSUM and CONFIDENCE are derived from the magnitude-squared stage
% because they are DUT outputs with no golden payload of their own.

arguments
    spreadingFactor (1,1) double
    samplesPerChip (1,1) double
end

manifest = lora_verify.load_stage_manifest;
names = ["input", "conjReferenceSpectrum", "fftM", "product", ...
    "partition", "fftN", "magnitudeSquared"];

ranges = struct;
for k = 1:numel(names)
    ranges.(names(k)) = 0;
end
ranges.spectrumSum = 0;
ranges.confidence = 1;
matched = 0;

for k = 1:numel(manifest.cases)
    entry = manifest.cases(k);
    if entry.spreadingFactor ~= spreadingFactor || ...
            entry.samplesPerChip ~= samplesPerChip
        continue;
    end
    matched = matched+1;
    stored = lora_verify.read_stage_vectors( ...
        fullfile(manifest.directory, string(entry.dataFile)), entry.stages);
    for j = 1:numel(names)
        name = names(j);
        ranges.(name) = max(ranges.(name), max(abs(stored.(name)(:))));
    end
    ranges.spectrumSum = max(ranges.spectrumSum, ...
        max(sum(stored.magnitudeSquared, 1)));
end

if matched == 0
    error("lora_sim:NoRangeData", ...
        "No committed acceptance case uses SF%d with L=%d", ...
        spreadingFactor, samplesPerChip);
end
ranges.caseCount = matched;
end
