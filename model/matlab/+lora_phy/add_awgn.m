function noisy = add_awgn(samples, snrDb, randomSeed)
%ADD_AWGN Add circular complex white Gaussian noise without toolboxes.

samples = samples(:);
if isempty(samples)
    noisy = samples;
    return;
end

signalPower = mean(abs(samples).^2);
if signalPower == 0
    error("lora_phy:ZeroSignal", "Cannot define SNR for an all-zero signal");
end

if nargin >= 3
    previousState = rng;
    restoreState = onCleanup(@() rng(previousState));
    rng(randomSeed, "twister");
end

noisePower = signalPower / 10^(snrDb/10);
scale = sqrt(noisePower/2);
noise = scale * (randn(size(samples)) + 1j*randn(size(samples)));
noisy = samples + noise;
end
