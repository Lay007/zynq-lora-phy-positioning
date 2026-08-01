function output = apply_frequency_offset(samples, frequencyOffset, initialPhase)
%APPLY_FREQUENCY_OFFSET Apply normalized CFO and initial phase.

if nargin < 3
    initialPhase = 0;
end

samples = samples(:);
n = (0:numel(samples)-1).';
rotation = exp(1j * (2*pi*frequencyOffset*n + initialPhase));
output = samples .* rotation;
end
