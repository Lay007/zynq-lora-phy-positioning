function filePath = generate_inspector_demo_capture(filePath)
%GENERATE_INSPECTOR_DEMO_CAPTURE Write a deterministic SF7/BW125 CF32 file.

if nargin < 1
    filePath = fullfile(tempdir, "lora-inspector-sf7-bw125.cf32");
end
config = lora_phy.css_config(7, 4);
frame = lora_phy.build_css_frame([3; 17; 64], config, 8, 2);
sampleRateHz = 500e3;
capture = [zeros(4000, 1); frame; zeros(3000, 1)];
capture = lora_phy.apply_frequency_offset(capture, 40e3/sampleRateHz);
rng(7, "twister");
capture = capture + sqrt(0.002/2)*( ...
    randn(size(capture))+1j*randn(size(capture)));

file = fopen(filePath, "w", "ieee-le");
if file < 0
    error("lora_phy:CannotCreateCapture", ...
        "Cannot create demo capture: %s", filePath);
end
cleanup = onCleanup(@() fclose(file));
interleaved = reshape([real(capture).'; imag(capture).'], [], 1);
fwrite(file, single(interleaved), "single");
end
