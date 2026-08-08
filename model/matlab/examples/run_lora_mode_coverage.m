function modeCoverage = run_lora_mode_coverage(options)
%RUN_LORA_MODE_COVERAGE Exercise every supported SF and coding-rate pair.

arguments
    options.PacketsPerMode (1,1) double ...
        {mustBeInteger, mustBePositive} = 2
    options.OutputDirectory (1,1) string = ""
end

thisDirectory = fileparts(mfilename("fullpath"));
matlabDirectory = fileparts(thisDirectory);
repositoryRoot = fileparts(fileparts(matlabDirectory));
if options.OutputDirectory == ""
    options.OutputDirectory = fullfile(repositoryRoot, "docs", "data");
end
if ~isfolder(options.OutputDirectory)
    mkdir(options.OutputDirectory);
end

modeCoverage = table;
for spreadingFactor = 5:12
    for codingRate = 1:4
        config = lora_phy.phy_config( ...
            spreadingFactor, 4, codingRate);
        config.lowDataRateOptimization = ...
            2^spreadingFactor/125e3 >= 16e-3;
        current = lora_phy.simulate_lora_stream_performance( ...
            -4, config, PacketsPerPoint=options.PacketsPerMode, ...
            PayloadLength=16, ...
            RandomSeed=3000+100*spreadingFactor+codingRate);
        modeCoverage = [modeCoverage; current]; %#ok<AGROW>
    end
    fprintf("M1 mode coverage SF%d complete\n", spreadingFactor);
end
writetable(modeCoverage, fullfile(options.OutputDirectory, ...
    "lora-end-to-end-mode-coverage.csv"));
end
