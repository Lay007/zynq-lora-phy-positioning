function report = run_synthesis(options)
%RUN_SYNTHESIS Out-of-context Vivado synthesis of the generated DUTs.
%
% The first numbers in this project that describe silicon rather than
% inferred operators. Everything published before this was HDL Coder's
% count of operators in the generated code, which does not translate into
% LUT/FF/DSP/BRAM and was always labelled as such.
%
%   report = run_synthesis;
%   report = run_synthesis(Part="xc7z010clg225-1");
%
% Out-of-context on purpose. There is no board wrapper, no clocking, and no
% AXI, so anything else would measure parts of the design that do not exist
% yet. These numbers describe the DUTs alone and will move once wrapped.
%
% Fmax is derived, not requested: synthesis runs against a probe period and
% Fmax = 1/(probe - WNS). A negative slack against an aggressive probe is
% still a valid measurement of what the design achieves.

arguments
    options.Part (1,1) string = "xc7z020clg400-1"
    options.ProbePeriodNs (1,1) double = 5
    options.Targets (1,:) string = ["fft-correlator-fixed", ...
        "blind-detector", "acquisition", "joint-timing-cfo"]
    options.VivadoPath (1,1) string = "g:\Xilinx\Vivado\2021.1\bin\vivado.bat"
    options.OutputDirectory string = string.empty
    options.WriteCsv (1,1) logical = true
    options.Verbose (1,1) logical = true
end

simulinkRoot = fileparts(mfilename("fullpath"));
repositoryRoot = fileparts(fileparts(simulinkRoot));
if isempty(options.OutputDirectory)
    options.OutputDirectory = string(fullfile(repositoryRoot, "docs", "data"));
end
if ~isfile(options.VivadoPath)
    error("lora_sim:NoVivado", "Vivado not found at %s", options.VivadoPath);
end

generatedRoot = fullfile(repositoryRoot, "fpga", "generated");
buildRoot = fullfile(repositoryRoot, "fpga", "build");
if ~isfolder(buildRoot)
    mkdir(buildRoot);
end
tclScript = fullfile(repositoryRoot, "fpga", "scripts", "synth_ooc.tcl");

rows = {};
failures = strings(0, 1);

for target = options.Targets
    sourceDirectory = findVerilogDirectory(fullfile(generatedRoot, target));
    if sourceDirectory == ""
        failures(end+1, 1) = target+": no generated Verilog"; %#ok<AGROW>
        continue;
    end

    workDirectory = fullfile(buildRoot, target);
    if isfolder(workDirectory)
        rmdir(workDirectory, "s");
    end
    mkdir(workDirectory);
    resultFile = fullfile(workDirectory, "synth.txt");

    command = sprintf('"%s" -mode batch -nojournal -nolog -source "%s" ' + ...
        "-tclargs ""%s"" ""%s"" %g ""%s""", options.VivadoPath, tclScript, ...
        sourceDirectory, options.Part, options.ProbePeriodNs, resultFile);
    previous = cd(workDirectory);
    cleanup = onCleanup(@() cd(previous));
    [status, output] = system(command);
    clear cleanup;

    if status ~= 0 || ~isfile(resultFile)
        failures(end+1, 1) = target+": synthesis failed"; %#ok<AGROW>
        if options.Verbose
            fprintf("%-22s FAILED\n%s\n", target, tail(output, 25));
        end
        continue;
    end

    values = readKeyValues(resultFile);
    rows{end+1} = table(target, string(options.Part), ...
        options.ProbePeriodNs, values.luts, values.registers, ...
        values.bram_tiles, values.dsps, values.carry4, values.wns_ns, ...
        values.achieved_period_ns, values.fmax_mhz, ...
        VariableNames=["Target", "Part", "ProbePeriodNs", "LUTs", ...
        "Registers", "BramTiles", "DSPs", "Carry4", "WnsNs", ...
        "AchievedPeriodNs", "FmaxMHz"]); %#ok<AGROW>

    if options.Verbose
        fprintf("%-22s LUT=%-6d FF=%-6d BRAM=%-5g DSP=%-4d Fmax=%.1f MHz\n", ...
            target, values.luts, values.registers, values.bram_tiles, ...
            values.dsps, values.fmax_mhz);
    end
end

report = struct;
report.summary = vertcat(rows{:});
report.failures = failures;
report.passed = isempty(failures) && ~isempty(rows);
report.part = options.Part;
report.synthesized = true;
report.placedAndRouted = false;

if options.WriteCsv && ~isempty(rows)
    if ~isfolder(options.OutputDirectory)
        mkdir(options.OutputDirectory);
    end
    writetable(report.summary, fullfile(options.OutputDirectory, ...
        "simulink-m3-synthesis.csv"));
end

if options.Verbose
    fprintf("\n");
    if ~isempty(rows)
        disp(report.summary);
    end
    if report.passed
        fprintf("Synthesis only. Not placed, not routed, no power figure, " + ...
            "and no board wrapper: these are out-of-context results.\n");
    else
        fprintf("FAILURES:\n  %s\n", strjoin(failures, newline+"  "));
    end
end
end

function directory = findVerilogDirectory(root)
%FINDVERILOGDIRECTORY HDL Coder nests the Verilog one level under the target.
directory = "";
if ~isfolder(root)
    return;
end
if ~isempty(dir(fullfile(root, "*.v")))
    directory = string(root);
    return;
end
entries = dir(root);
for k = 1:numel(entries)
    if entries(k).isdir && ~startsWith(entries(k).name, ".")
        candidate = fullfile(root, entries(k).name);
        if ~isempty(dir(fullfile(candidate, "*.v")))
            directory = string(candidate);
            return;
        end
    end
end
end

function values = readKeyValues(path)
values = struct("luts", NaN, "registers", NaN, "bram_tiles", NaN, ...
    "dsps", NaN, "carry4", NaN, "wns_ns", NaN, ...
    "achieved_period_ns", NaN, "fmax_mhz", NaN);
lines = string(splitlines(strtrim(fileread(path))));
for k = 1:numel(lines)
    parts = split(lines(k), "=");
    if numel(parts) == 2 && isfield(values, parts(1))
        values.(parts(1)) = str2double(parts(2));
    end
end
end

function text = tail(output, count)
lines = string(splitlines(string(output)));
lines = lines(max(1, numel(lines)-count+1):end);
text = strjoin(lines, newline);
end
