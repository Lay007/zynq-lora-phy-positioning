function report = report_toolchain(outputPath)
%REPORT_TOOLCHAIN Verify the products and licenses required by M2.
%
% Presence in `ver` is not treated as proof: every feature is also checked
% out. Two products are licensed under legacy feature names, which is why
% the table carries the feature string explicitly:
%
%   HDL Coder    -> Simulink_HDL_Coder   (not "HDL_Coder")
%   HDL Verifier -> eda_simulator_link   (not "HDL_Verifier")
%
% Usage:
%   report = report_toolchain;
%   report = report_toolchain("toolchain.json");

arguments
    outputPath string = string.empty
end

required = [ ...
    "Simulink",               "SIMULINK",             "simulink"; ...
    "Fixed-Point Designer",   "Fixed_Point_Toolbox",  "fixedpoint"; ...
    "HDL Coder",              "Simulink_HDL_Coder",   "hdlcoder"; ...
    "DSP HDL Toolbox",        "DSP_HDL_Toolbox",      "dsphdl"; ...
    "DSP System Toolbox",     "Signal_Blocks",        "dsp"; ...
    "HDL Verifier",           "eda_simulator_link",   "hdlverifier"; ...
    "Communications Toolbox", "Communication_Toolbox", "comm"; ...
    "Simulink Coder",         "Real-Time_Workshop",   "simulinkcoder"; ...
    "Embedded Coder",         "RTW_Embedded_Coder",   "embeddedcoder"];

rowCount = size(required, 1);
product = strings(rowCount, 1);
feature = strings(rowCount, 1);
installedVersion = strings(rowCount, 1);
licenseTest = false(rowCount, 1);
licenseCheckout = false(rowCount, 1);

for k = 1:rowCount
    product(k) = required(k, 1);
    feature(k) = required(k, 2);
    installedVersion(k) = "absent";
    try
        info = ver(required(k, 3));
        if ~isempty(info)
            installedVersion(k) = string(info(1).Version);
        end
    catch
        % Leave the version as "absent"; the license columns decide.
    end
    licenseTest(k) = logical(license("test", feature(k)));
    if licenseTest(k)
        licenseCheckout(k) = logical(license("checkout", feature(k)));
    end
end

report = struct;
report.matlabRoot = string(matlabroot);
report.matlabVersion = string(version);
report.matlabRelease = string(version("-release"));
report.architecture = string(computer("arch"));
report.checkedAt = string(datetime("now", Format="uuuu-MM-dd HH:mm:ss"));
report.products = table(product, feature, installedVersion, ...
    licenseTest, licenseCheckout, ...
    VariableNames=["Product", "Feature", "Version", "LicenseTest", ...
    "LicenseCheckout"]);
report.allAvailable = all(licenseCheckout);

fprintf("MATLAB %s (%s) on %s\n", report.matlabVersion, ...
    report.matlabRelease, report.architecture);
disp(report.products);
if report.allAvailable
    fprintf("All M2 products licensed and checked out.\n");
else
    missing = product(~licenseCheckout);
    fprintf("MISSING: %s\n", strjoin(missing, ", "));
end

if ~isempty(outputPath)
    payload = struct;
    payload.matlabRoot = report.matlabRoot;
    payload.matlabVersion = report.matlabVersion;
    payload.matlabRelease = report.matlabRelease;
    payload.architecture = report.architecture;
    payload.checkedAt = report.checkedAt;
    payload.allAvailable = report.allAvailable;
    payload.products = table2struct(report.products);
    file = fopen(outputPath, "w");
    if file < 0
        error("lora_sim:ToolchainReportFile", "Cannot open %s", outputPath);
    end
    cleanup = onCleanup(@() fclose(file));
    fprintf(file, "%s\n", jsonencode(payload, "PrettyPrint", true));
end
end
