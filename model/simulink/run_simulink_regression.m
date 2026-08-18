function results = run_simulink_regression(options)
%RUN_SIMULINK_REGRESSION Single entry point for every MATLAB/Simulink check.
%
% Fails loudly: any mismatch raises an error, so
%
%   matlab -batch "cd model/simulink; run_simulink_regression"
%
% returns a nonzero exit code. That is the command the acceptance
% procedure uses.
%
% Suites:
%   toolchain  products and licenses required by M2 (seconds)
%   double     double DUT against the committed stage vectors (~15 min)
%   joint      joint timing/CFO DUT, bit-exact over the input domain
%   frequency  registered frequency-only DUT against the same golden model
%   acquisition preamble/sync acceptance FSM, exact over sequences
%   blind      blind packet-start detector, exact over sliding windows
%   metadata   coarse/fractional timestamp pairing, reset, and overflow
%   fixed      fixed-point word-length sweep (hours, opt in)
%   real       committed SX1262 symbol windows through the fixed DUT (opt in)
%
%   results = run_simulink_regression;
%   results = run_simulink_regression(Suites=["toolchain" "double" ...
%       "joint" "fixed" "real"]);

arguments
    options.Suites string = ["toolchain", "double", "joint", ...
        "frequency", "reset", "acquisition", "blind", "frontend", ...
        "framing", "sfd", "toa", "metadata"]
    options.WriteCsv (1,1) logical = true
    options.FixedWordLengths (1,:) double = [8, 10, 12, 14, 16, 18]
    options.RealWordLength (1,1) double = 16
end

simulinkRoot = fileparts(mfilename("fullpath"));
repositoryRoot = fileparts(fileparts(simulinkRoot));
addpath(simulinkRoot);
addpath(fullfile(repositoryRoot, "model", "matlab"));

known = ["toolchain", "double", "joint", "frequency", "reset", ...
    "acquisition", "blind", "frontend", "framing", "sfd", "toa", ...
    "metadata", "fixed", "real"];
unknown = setdiff(options.Suites, known);
if ~isempty(unknown)
    error("lora_sim:UnknownSuite", "Unknown suite: %s", ...
        strjoin(unknown, ", "));
end

results = struct;
problems = strings(0, 1);

if any(options.Suites == "toolchain")
    fprintf("=== toolchain ===\n");
    results.toolchain = report_toolchain;
    if ~results.toolchain.allAvailable
        problems(end+1, 1) = "Required MATLAB products are not licensed";
    end
end

if any(options.Suites == "double")
    fprintf("\n=== double FFT correlator vs MATLAB stages ===\n");
    results.double = run_correlator_regression(WriteCsv=options.WriteCsv);
    if ~results.double.passed
        problems = [problems; results.double.failures(:)];
    end
end

if any(options.Suites == "joint")
    fprintf("\n=== joint timing/CFO estimator ===\n");
    results.joint = run_joint_sync_regression(WriteCsv=options.WriteCsv);
    if ~results.joint.passed
        problems = [problems; results.joint.failures(:)];
    end
end

if any(options.Suites == "frequency")
    fprintf("\n=== carrier-frequency estimator ===\n");
    results.frequency = run_frequency_estimator_regression( ...
        WriteCsv=options.WriteCsv);
    if ~results.frequency.passed
        problems = [problems; results.frequency.failures(:)];
    end
end

if any(options.Suites == "reset")
    fprintf("\n=== reset behavior ===\n");
    results.reset = run_reset_regression(WriteCsv=options.WriteCsv);
    if ~results.reset.passed
        problems = [problems; results.reset.failures(:)];
    end
end

if any(options.Suites == "acquisition")
    fprintf("\n=== acquisition state machine ===\n");
    results.acquisition = run_acquisition_regression(WriteCsv=options.WriteCsv);
    if ~results.acquisition.passed
        problems = [problems; results.acquisition.failures(:)];
    end
end

if any(options.Suites == "blind")
    fprintf("\n=== blind packet-start detector ===\n");
    results.blind = run_blind_detector_regression(WriteCsv=options.WriteCsv);
    if ~results.blind.passed
        problems = [problems; results.blind.failures(:)];
    end
end

if any(options.Suites == "frontend")
    fprintf("\n=== composed receiver front-end ===\n");
    results.frontend = run_frontend_regression(WriteCsv=options.WriteCsv);
    if ~results.frontend.passed
        problems = [problems; results.frontend.failures(:)];
    end
end

if any(options.Suites == "framing")
    fprintf("\n=== packet framing state machine ===\n");
    results.framing = run_framing_regression(WriteCsv=options.WriteCsv);
    if ~results.framing.passed
        problems = [problems; results.framing.failures(:)];
    end
end

if any(options.Suites == "sfd")
    fprintf("\n=== SFD acceptance ===\n");
    results.sfd = run_sfd_regression(WriteCsv=options.WriteCsv);
    if ~results.sfd.passed
        problems = [problems; results.sfd.failures(:)];
    end
end

if any(options.Suites == "toa")
    fprintf("\n=== sub-sample ToA interpolator ===\n");
    results.toa = run_toa_interpolator_regression(WriteCsv=options.WriteCsv);
    if ~results.toa.passed
        problems = [problems; results.toa.failures(:)];
    end
end

if any(options.Suites == "metadata")
    fprintf("\n=== timestamp metadata contract ===\n");
    results.metadata = run_timestamp_metadata_regression( ...
        WriteCsv=options.WriteCsv);
    if ~results.metadata.passed
        problems = [problems; results.metadata.failures(:)];
    end
end

if any(options.Suites == "fixed")
    fprintf("\n=== fixed-point word-length sweep ===\n");
    results.fixed = run_fixed_point_sweep( ...
        WordLengths=options.FixedWordLengths, WriteCsv=options.WriteCsv);
    if ~results.fixed.passed
        problems(end+1, 1) = ...
            "No swept word length preserved every symbol decision";
    end
end

if any(options.Suites == "real")
    fprintf("\n=== real SX1262 symbol windows ===\n");
    results.real = run_real_iq_regression( ...
        WordLength=options.RealWordLength, WriteCsv=options.WriteCsv);
    if ~results.real.passed
        problems(end+1, 1) = sprintf( ...
            "Fixed-point DUT changed %d of %d real symbol decisions", ...
            results.real.symbolCount-results.real.fixedMatchesFloat, ...
            results.real.symbolCount);
    end
end

fprintf("\n=== summary ===\n");
if isfield(results, "double")
    fprintf("double : %d cases, worst relative RMS %.3e\n", ...
        height(results.double.summary), results.double.worstRelativeRms);
end
if isfield(results, "joint")
    fprintf("joint  : %d bin pairs, exact match\n", ...
        results.joint.totalPairs);
end
if isfield(results, "frequency")
    sf7 = results.frequency.summary.SF == 7 & ...
        results.frequency.summary.L == 8;
    fprintf("freq   : %d bin pairs exact; SF7/BW125 resolution %.3f Hz\n", ...
        results.frequency.totalPairs, ...
        results.frequency.summary.ResolutionHz(find(sf7, 1)));
end
if isfield(results, "reset")
    fprintf("reset  : %d configurations return to the power-up state\n", ...
        height(results.reset.summary));
end
if isfield(results, "acquisition")
    fprintf("acq    : %d sequences, exact match\n", ...
        results.acquisition.totalSequences);
end
if isfield(results, "blind")
    fprintf("blind  : %d symbols exact; preamble %.0f%% of alignments, " + ...
        "sync %.0f%% on the free-running grid\n", ...
        results.blind.totalSymbols, 100*results.blind.preambleRate, ...
        100*results.blind.syncRate);
end
if isfield(results, "frontend")
    fprintf("front  : %d offsets recover the same %d payload symbols\n", ...
        height(results.frontend.summary), ...
        numel(results.frontend.referencePayload));
end
if isfield(results, "framing")
    fprintf("frame  : %d symbols exact, %d packets, %d rejections\n", ...
        results.framing.summary.Symbols, ...
        results.framing.summary.PacketsCompleted, ...
        results.framing.summary.Rejections);
end
if isfield(results, "sfd")
    fprintf("sfd    : %d groups, exact match\n", results.sfd.totalGroups);
end
if isfield(results, "toa")
    fprintf("toa    : %.1f m RMS against a %.0f m sample\n", ...
        results.toa.summary.RmsAgainstTruthMetres, results.toa.metresPerSample);
end
if isfield(results, "metadata")
    fprintf("meta   : %d atomic timestamp records; reset/overflow covered\n", ...
        height(results.metadata.summary));
end
if isfield(results, "fixed")
    fprintf("fixed  : smallest decision-preserving word length %d bits\n", ...
        results.fixed.selectedWordLength);
end
if isfield(results, "real")
    fprintf("real   : %d packets, %d/%d symbols match floating point\n", ...
        results.real.packetCount, results.real.fixedMatchesFloat, ...
        results.real.symbolCount);
end

results.passed = isempty(problems);
results.problems = problems;

if ~results.passed
    error("lora_sim:RegressionFailed", ...
        "Simulink regression failed:\n  %s", ...
        strjoin(problems, newline+"  "));
end
fprintf("ALL SIMULINK REGRESSIONS PASSED\n");
end
