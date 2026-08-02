function outputs = run_visualizations
%RUN_VISUALIZATIONS Generate the current MATLAB model figures.

rootDirectory = fileparts(mfilename("fullpath"));
addpath(rootDirectory);
addpath(fullfile(rootDirectory, "examples"));

[berResults, berFigure] = plot_ber_curve;
[frameResult, frameFigure] = plot_frame_acquisition;
[codedCr1, codedCr4, codedFigure] = plot_coded_ber;
[symbolResult, symbolFigure] = plot_symbol_demodulation;

outputs = struct;
outputs.berResults = berResults;
outputs.frameResult = frameResult;
outputs.codedCr1 = codedCr1;
outputs.codedCr4 = codedCr4;
outputs.symbolResult = symbolResult;
outputs.figures = [berFigure, frameFigure, codedFigure, symbolFigure];
end
