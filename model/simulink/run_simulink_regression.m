function results = run_simulink_regression(options)
%RUN_SIMULINK_REGRESSION Single entry point for every MATLAB/Simulink check.
%
% Fails loudly: any mismatch raises an error, so
%
%   matlab -batch "cd model/simulink; run_simulink_regression"
%
% returns a nonzero exit code. That is the command CI and the acceptance
% procedure use.
%
%   results = run_simulink_regression;
%   results = run_simulink_regression(Suites="double");

arguments
    options.Suites string = ["toolchain", "double"]
    options.WriteCsv (1,1) logical = true
end

simulinkRoot = fileparts(mfilename("fullpath"));
repositoryRoot = fileparts(fileparts(simulinkRoot));
addpath(simulinkRoot);
addpath(fullfile(repositoryRoot, "model", "matlab"));

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

fprintf("\n=== summary ===\n");
if isfield(results, "double")
    fprintf("double : %d cases, worst relative RMS %.3e\n", ...
        height(results.double.summary), results.double.worstRelativeRms);
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
