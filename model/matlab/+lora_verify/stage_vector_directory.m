function directory = stage_vector_directory
%STAGE_VECTOR_DIRECTORY Committed location of the FFT-correlator vectors.

packageDirectory = fileparts(mfilename("fullpath"));
matlabRoot = fileparts(packageDirectory);
directory = string(fullfile(matlabRoot, "golden", "fft-correlator"));
end
