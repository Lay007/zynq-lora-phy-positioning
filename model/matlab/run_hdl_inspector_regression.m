function report = run_hdl_inspector_regression(filePath, options)
%RUN_HDL_INSPECTOR_REGRESSION End-to-end check of a GHDL CI16 capture.
%
% The same file produced by the self-checking HDL package testbench is read
% through the Inspector loader, analysed by inspect_iq_capture, and compared
% sample-by-sample with the MATLAB golden chirp.

arguments
    filePath (1,1) string
    options.ReportPath (1,1) string = ""
end

metadata = lora_phy.parse_hdl_recording_name(filePath);
[iq, loadInfo] = lora_phy.load_iq_capture(filePath, "auto");

expectedSymbolCount = 10;
expectedSampleCount = round(expectedSymbolCount * metadata.symbolSamples);
assert(loadInfo.format == "ci16", "HDL capture must be loaded as CI16");
assert(loadInfo.sampleCount == expectedSampleCount, ...
    "Expected %d complex samples, got %d", ...
    expectedSampleCount, loadInfo.sampleCount);

inspection = lora_phy.inspect_iq_capture(iq, metadata.sampleRateHz);
assert(inspection.estimatedSpreadingFactor == metadata.spreadingFactor, ...
    "Inspector SF mismatch: expected SF%d, got SF%d", ...
    metadata.spreadingFactor, inspection.estimatedSpreadingFactor);
assert(abs(inspection.estimatedBandwidthHz-metadata.bandwidthHz) < 1, ...
    "Inspector BW mismatch: expected %.0f Hz, got %.0f Hz", ...
    metadata.bandwidthHz, inspection.estimatedBandwidthHz);

% An ideal baseband HDL capture is centred at DC. Keep the tolerance loose
% enough to reflect the exploratory carrier estimator rather than DDS error.
carrierToleranceHz = 0.04 * metadata.bandwidthHz;
assert(abs(inspection.estimatedCarrierOffsetHz) <= carrierToleranceHz, ...
    "Inspector carrier offset is unexpectedly large: %.1f Hz", ...
    inspection.estimatedCarrierOffsetHz);

golden = lora_phy.compare_iq_to_golden( ...
    iq, metadata.sampleRateHz, metadata.spreadingFactor, metadata.bandwidthHz, ...
    StartIndex=1, Symbol=metadata.referenceSymbol, ...
    Direction=metadata.referenceDirection, SearchRadiusSamples=0);
assert(golden.passed, ...
    "MATLAB golden comparison failed: EVM %.6f%%, corr %.9f, phase %.6f deg", ...
    golden.evmPercent, golden.correlation, golden.rmsPhaseErrorDegrees);

profile = lora_phy.match_lora_profile( ...
    inspection.estimatedSpreadingFactor, inspection.estimatedBandwidthHz, 0);
assert(profile.projectReferenceCompatible, ...
    "Inspector PHY profile is not compatible with project reference SX1262");

report = struct;
report.fileName = metadata.fileName;
report.format = loadInfo.format;
report.sampleCount = loadInfo.sampleCount;
report.spreadingFactor = inspection.estimatedSpreadingFactor;
report.bandwidthHz = inspection.estimatedBandwidthHz;
report.measuredOccupiedBandwidthHz = inspection.measuredOccupiedBandwidthHz;
report.carrierOffsetHz = inspection.estimatedCarrierOffsetHz;
report.residualCfoHz = inspection.residualCfoHz;
report.preambleScore = inspection.preambleScore;
report.goldenEvmPercent = golden.evmPercent;
report.goldenCorrelation = golden.correlation;
report.goldenRmsPhaseErrorDegrees = golden.rmsPhaseErrorDegrees;
report.goldenMaxPhaseErrorDegrees = golden.maxPhaseErrorDegrees;
report.goldenMaxNormalizedSampleError = golden.maxNormalizedSampleError;
report.goldenPassed = golden.passed;
report.mode = string(profile.modeSummary);
report.projectReferenceRadio = profile.projectReferenceRadio;
report.projectReferenceCompatible = profile.projectReferenceCompatible;
report.compatibleRadios = string(profile.compatibilitySummary);

fprintf("HDL Inspector end-to-end regression PASS\n");
fprintf("  file: %s\n", char(report.fileName));
fprintf("  samples: %d complex CI16\n", report.sampleCount);
fprintf("  detected: SF%d / BW %.0f kHz\n", ...
    report.spreadingFactor, report.bandwidthHz/1e3);
fprintf("  occupied BW: %.3f kHz\n", report.measuredOccupiedBandwidthHz/1e3);
fprintf("  carrier offset: %+.3f Hz\n", report.carrierOffsetHz);
fprintf("  residual CFO: %+.3f Hz\n", report.residualCfoHz);
fprintf("  golden EVM: %.6f %%\n", report.goldenEvmPercent);
fprintf("  golden correlation: %.9f\n", report.goldenCorrelation);
fprintf("  RMS phase error: %.6f deg\n", report.goldenRmsPhaseErrorDegrees);
fprintf("  radio profile: %s; SX1262 compatible=%d\n", ...
    char(report.mode), report.projectReferenceCompatible);

if options.ReportPath ~= ""
    reportDirectory = fileparts(options.ReportPath);
    if reportDirectory ~= "" && ~isfolder(reportDirectory)
        mkdir(reportDirectory);
    end
    writetable(struct2table(report), options.ReportPath);
end
end
