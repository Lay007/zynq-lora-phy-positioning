function outputs = run_visualizations
%RUN_VISUALIZATIONS Generate the current MATLAB model figures.

rootDirectory = fileparts(mfilename("fullpath"));
addpath(rootDirectory);
addpath(fullfile(rootDirectory, "examples"));

[berResults, berFigure] = plot_ber_curve;
[frameResult, frameFigure] = plot_frame_acquisition;

outputs = struct;
outputs.berResults = berResults;
outputs.frameResult = frameResult;
outputs.figures = [berFigure, frameFigure];
end
