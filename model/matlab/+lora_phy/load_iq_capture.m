function [iq, info] = load_iq_capture(filePath, format)
%LOAD_IQ_CAPTURE Read headerless RTL-SDR or Pluto/GNU Radio complex IQ.

filePath = string(filePath);
if nargin < 2 || string(format) == "auto"
    [~, ~, extension] = fileparts(filePath);
    switch lower(extension)
        case {'.cu8', '.uc8'}
            format = "cu8";
        case {'.cf32', '.fc32', '.cfile'}
            format = "cf32";
        otherwise
            error("lora_phy:UnknownIqFormat", ...
                "Cannot infer IQ format from extension %s", extension);
    end
else
    format = lower(string(format));
end

if ~isfile(filePath)
    error("lora_phy:CaptureNotFound", "IQ file does not exist: %s", filePath);
end

switch format
    case "cu8"
        file = fopen(filePath, "r");
        cleanup = onCleanup(@() fclose(file));
        raw = fread(file, Inf, "uint8=>double");
        if mod(numel(raw), 2) ~= 0
            error("lora_phy:OddIqComponentCount", ...
                "CU8 capture must contain interleaved I,Q pairs");
        end
        clippedComponents = nnz(raw == 0 | raw == 255);
        iq = complex(raw(1:2:end)-127.5, raw(2:2:end)-127.5) / 127.5;
        componentCount = numel(raw);
    case "cf32"
        file = fopen(filePath, "r", "ieee-le");
        cleanup = onCleanup(@() fclose(file));
        raw = fread(file, Inf, "single=>double");
        if mod(numel(raw), 2) ~= 0
            error("lora_phy:OddIqComponentCount", ...
                "CF32 capture must contain interleaved I,Q pairs");
        end
        clippedComponents = NaN;
        iq = complex(raw(1:2:end), raw(2:2:end));
        componentCount = numel(raw);
    otherwise
        error("lora_phy:UnsupportedIqFormat", ...
            "Supported formats are auto, cu8, and cf32");
end

iq = iq(:);
info = struct;
info.filePath = filePath;
info.format = format;
info.sampleCount = numel(iq);
info.componentCount = componentCount;
info.clippedComponentFraction = clippedComponents/componentCount;
end
