function ranges = ranges_from_windows(windows, config, options)
%RANGES_FROM_WINDOWS Range analysis over an arbitrary stimulus corpus.
%
% Same field layout as LORA_SIM.STAGE_RANGES, but collected from the given
% symbol windows instead of the committed synthetic vectors. This is what
% the real-IQ regression uses: the integer bits of a fixed-point design
% must follow the signal the design will actually see.
%
% Windows are processed in blocks. A full real capture holds thousands of
% symbols, and materializing every intermediate stage at once would cost
% hundreds of megabytes for a set of maxima.

arguments
    windows (:,:) {mustBeNumeric}
    config (1,1) struct
    options.BlockSymbols (1,1) double {mustBeInteger, mustBePositive} = 256
end

names = ["input", "conjReferenceSpectrum", "fftM", "product", ...
    "partition", "fftN"];
ranges = struct;
for k = 1:numel(names)
    ranges.(names(k)) = 0;
end
ranges.magnitudeSquared = 0;
ranges.spectrumSum = 0;
ranges.confidence = 1;

total = size(windows, 2);
cursor = 1;
while cursor <= total
    stop = min(total, cursor+options.BlockSymbols-1);
    block = windows(:, cursor:stop);
    stages = lora_phy.fft_correlator_stages(block(:), config);
    for k = 1:numel(names)
        name = names(k);
        ranges.(name) = max(ranges.(name), max(abs(stages.(name)(:))));
    end
    ranges.magnitudeSquared = max(ranges.magnitudeSquared, ...
        max(stages.magnitudeSquared(:)));
    ranges.spectrumSum = max(ranges.spectrumSum, ...
        max(sum(stages.magnitudeSquared, 1)));
    cursor = stop+1;
end

ranges.caseCount = total;
end
