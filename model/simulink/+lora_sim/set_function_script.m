function set_function_script(blockPath, lines)
%SET_FUNCTION_SCRIPT Install MATLAB Function block code from a string array.

arguments
    blockPath (1,1) string
    lines string
end

configuration = get_param(blockPath, "MATLABFunctionConfiguration");
configuration.FunctionScript = strjoin(lines(:), newline);
end
