function result = compute_spectrogram(iq, sampleRateHz, fftLength, maxColumns)
%COMPUTE_SPECTROGRAM Toolbox-free complex-IQ short-time Fourier transform.

if nargin < 3
    fftLength = 1024;
end
if nargin < 4
    maxColumns = 800;
end
iq = iq(:);
validateattributes(sampleRateHz, {'numeric'}, {"scalar", ">", 0});
validateattributes(fftLength, {'numeric'}, ...
    {"scalar", "integer", ">=", 16});
validateattributes(maxColumns, {'numeric'}, ...
    {"scalar", "integer", ">=", 1});

windowLength = min(fftLength, numel(iq));
if windowLength < 16
    error("lora_phy:CaptureTooShort", ...
        "At least 16 IQ samples are required for a spectrogram");
end
minimumHop = max(1, floor(windowLength/4));
if numel(iq) <= windowLength
    hop = 1;
else
    hop = max(minimumHop, ...
        ceil((numel(iq)-windowLength)/max(1, maxColumns-1)));
end
starts = 1:hop:(numel(iq)-windowLength+1);
if numel(starts) > maxColumns
    starts = starts(1:maxColumns);
end

n = (0:windowLength-1).';
window = 0.5 - 0.5*cos(2*pi*n/max(1, windowLength-1));
frames = complex(zeros(fftLength, numel(starts)));
for column = 1:numel(starts)
    samples = iq(starts(column)+(0:windowLength-1)) .* window;
    frames(:, column) = fftshift(fft(samples, fftLength));
end
amplitude = abs(frames) / max(sum(window), eps);
powerDb = 20*log10(amplitude + eps);

result = struct;
result.timeSeconds = (starts(:)-1 + (windowLength-1)/2) / sampleRateHz;
result.frequencyHz = ((-fftLength/2):(fftLength/2-1)).' * ...
    sampleRateHz/fftLength;
result.powerDb = powerDb;
result.fftLength = fftLength;
result.windowLength = windowLength;
result.hopSamples = hop;
end
