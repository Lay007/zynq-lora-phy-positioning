function report = validate_inspector_reference_captures(outputPath)
%VALIDATE_INSPECTOR_REFERENCE_CAPTURES Regress Inspector on curated OTA IQ.
%
% The selected files are stored through Git LFS. Callers must materialize the
% LFS objects before running this function. Carrier offset is measured relative
% to the capture centre; CFO is then measured relative to the nominal TX RF.

matlabRoot = fileparts(fileparts(mfilename("fullpath")));
repoRoot = fileparts(fileparts(matlabRoot));
addpath(matlabRoot);

if nargin < 1 || strlength(string(outputPath)) == 0
    outputPath = fullfile(repoRoot, "docs", "data", ...
        "inspector-reference-captures.csv");
end

cases = [ ...
    make_case("LR1121 SF7/BW125", ...
        "LR1121", ...
        "captures/reference/2026-08-02-lr1121-zynqsdr-sf7-bw125/iq.cf32", ...
        1e6, 868349998, 868100000, 7, 125e3, 185); ...
    make_case("SX1262 SF7/BW125", ...
        "SX1262", ...
        "captures/reference/2026-08-03-heltec-v43-zynqsdr-mode-sweep/sf7-bw125.cf32", ...
        1e6, 868350000, 868100000, 7, 125e3, 801); ...
    make_case("SX1262 SF10/BW125", ...
        "SX1262", ...
        "captures/reference/2026-08-03-heltec-v43-zynqsdr-mode-sweep/sf10-bw125.cf32", ...
        1e6, 868350000, 868100000, 10, 125e3, 451); ...
    make_case("SX1262 SF7/BW250", ...
        "SX1262", ...
        "captures/reference/2026-08-03-heltec-v43-zynqsdr-mode-sweep/sf7-bw250.cf32", ...
        1e6, 868350000, 868100000, 7, 250e3, -1811) ...
    ];

rowCount = numel(cases);
caseName = strings(rowCount, 1);
sourceRadio = strings(rowCount, 1);
expectedSf = zeros(rowCount, 1);
detectedSf = zeros(rowCount, 1);
expectedBwHz = zeros(rowCount, 1);
detectedBwHz = zeros(rowCount, 1);
expectedCarrierOffsetHz = zeros(rowCount, 1);
carrierOffsetHz = zeros(rowCount, 1);
expectedCfoHz = zeros(rowCount, 1);
cfoHz = zeros(rowCount, 1);
snrDb = zeros(rowCount, 1);
compatibleRadios = strings(rowCount, 1);
pass = false(rowCount, 1);

for index = 1:rowCount
    item = cases(index);
    path = fullfile(repoRoot, item.relativePath);
    if ~isfile(path)
        error("lora_phy:ReferenceCaptureMissing", ...
            "Reference capture is not materialized: %s", path);
    end
    fileInfo = dir(path);
    if fileInfo.bytes < 1024
        error("lora_phy:ReferenceCaptureIsLfsPointer", ...
            ["Reference capture still looks like a Git LFS pointer: %s. " ...
             "Run git lfs pull for the selected file."], path);
    end

    [iq, ~] = lora_phy.load_iq_capture(path, "cf32");
    result = lora_phy.inspect_iq_capture(iq, item.sampleRateHz);
    absoluteCarrierHz = item.centreFrequencyHz + result.estimatedCarrierOffsetHz;
    measuredCfoHz = absoluteCarrierHz - item.transmitFrequencyHz;
    nominalCarrierOffsetHz = item.transmitFrequencyHz-item.centreFrequencyHz;
    expectedMeasuredCarrierOffsetHz = nominalCarrierOffsetHz+item.expectedCfoHz;
    profile = lora_phy.match_lora_profile( ...
        result.estimatedSpreadingFactor, result.estimatedBandwidthHz, ...
        absoluteCarrierHz);

    sfOk = result.estimatedSpreadingFactor == item.expectedSf;
    bwOk = result.estimatedBandwidthHz == item.expectedBwHz;
    carrierOk = abs(result.estimatedCarrierOffsetHz-expectedMeasuredCarrierOffsetHz) <= 3000;
    cfoOk = abs(measuredCfoHz-item.expectedCfoHz) <= 3000;
    snrOk = result.estimatedSnrDb >= 20;
    sourceCompatible = any(profile.compatibleRadios == item.sourceRadio);

    caseName(index) = item.name;
    sourceRadio(index) = item.sourceRadio;
    expectedSf(index) = item.expectedSf;
    detectedSf(index) = result.estimatedSpreadingFactor;
    expectedBwHz(index) = item.expectedBwHz;
    detectedBwHz(index) = result.estimatedBandwidthHz;
    expectedCarrierOffsetHz(index) = expectedMeasuredCarrierOffsetHz;
    carrierOffsetHz(index) = result.estimatedCarrierOffsetHz;
    expectedCfoHz(index) = item.expectedCfoHz;
    cfoHz(index) = measuredCfoHz;
    snrDb(index) = result.estimatedSnrDb;
    compatibleRadios(index) = profile.compatibilitySummary;
    pass(index) = sfOk && bwOk && carrierOk && cfoOk && snrOk && sourceCompatible;

    fprintf(["Inspector %-20s: SF%d BW %.0f kHz carrier %+.1f kHz " ...
        "CFO %+.1f Hz SNR %.1f dB -> %s\n"], ...
        item.name, result.estimatedSpreadingFactor, ...
        result.estimatedBandwidthHz/1e3, result.estimatedCarrierOffsetHz/1e3, ...
        measuredCfoHz, result.estimatedSnrDb, pass_fail(pass(index)));
end

report = table(caseName, sourceRadio, expectedSf, detectedSf, ...
    expectedBwHz, detectedBwHz, expectedCarrierOffsetHz, carrierOffsetHz, ...
    expectedCfoHz, cfoHz, snrDb, compatibleRadios, pass);

outputPath = string(outputPath);
outputDirectory = fileparts(outputPath);
if strlength(outputDirectory) > 0 && ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end
writetable(report, outputPath);

assert(all(pass), ...
    "LoRa PHY Inspector regression failed for one or more reference captures");
end

function item = make_case(name, sourceRadio, relativePath, fs, centre, tx, sf, bw, cfo)
item = struct( ...
    "name", string(name), ...
    "sourceRadio", string(sourceRadio), ...
    "relativePath", string(relativePath), ...
    "sampleRateHz", double(fs), ...
    "centreFrequencyHz", double(centre), ...
    "transmitFrequencyHz", double(tx), ...
    "expectedSf", double(sf), ...
    "expectedBwHz", double(bw), ...
    "expectedCfoHz", double(cfo));
end

function text = pass_fail(value)
if value
    text = "PASS";
else
    text = "FAIL";
end
end
