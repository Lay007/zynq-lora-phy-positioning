function results = run_tests
%RUN_TESTS Run the MATLAB floating-point model regression suite.

rootDirectory = fileparts(mfilename("fullpath"));
addpath(rootDirectory);
testDirectory = fullfile(rootDirectory, "tests");
results = runtests(testDirectory, "IncludeSubfolders", true);

if nargout == 0
    assertSuccess(results);
end
end
