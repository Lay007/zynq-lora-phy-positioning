function directory = generated_directory
%GENERATED_DIRECTORY Location for script-generated models and reports.
%
% Nothing here is committed. Every model is rebuilt from
% BUILD_FFT_CORRELATOR_MODEL, so deleting this directory is always safe.

simulinkRoot = fileparts(fileparts(mfilename("fullpath")));
directory = string(fullfile(simulinkRoot, "generated"));
if ~isfolder(directory)
    mkdir(directory);
end
end
