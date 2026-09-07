function [iq, info] = load_iq_capture(filePath, format)
%LOAD_IQ_CAPTURE Read supported complex IQ capture formats.
%
% Supported formats:
%   cu8  - uint8 interleaved I,Q (RTL-SDR)
%   cf32 - little-endian float32 interleaved I,Q (Pluto/GNU Radio)
%   ci16 - little-endian signed int16 interleaved I,Q
%
% CI16 is a conventional headerless complex-int16 stream:
%   I0, Q0, I1, Q1, ...
% Components are normalized by the full int16 scale (32768).

filePath = string(filePath);
if nargin < 2 || string(format) == "auto"
    [~, ~, extension] = fileparts(filePath);
    switch lower(extension)
        case {'.cu8', '.uc8'}
            format = "cu8";
        case {'.cf32', '.fc32', '.cfile'}
            format = "cf32";
        case {'.pcm', '.ci16', '.sc16'}
            format = "ci16";
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
    case "ci16"
        file = fopen(filePath, "r", "ieee-le");
        cleanup = onCleanup(@() fclose(file));
        raw = fread(file, Inf, "int16=>double");
        if mod(numel(raw), 2) ~= 0
            error("lora_phy:OddIqComponentCount", ...
                "CI16 capture must contain interleaved I,Q pairs");
        end
        clippedComponents = nnz(raw == -32768 | raw == 32767);
        iq = complex(raw(1:2:end), raw(2:2:end)) / 32768;
        componentCount = numel(raw);
    otherwise
        error("lora_phy:UnsupportedIqFormat", ...
            "Supported formats are auto, cu8, cf32, and ci16");
end

iq = iq(:);
info = struct;
info.filePath = filePath;
info.format = format;
info.sampleCount = numel(iq);
info.componentCount = componentCount;
info.clippedComponentFraction = clippedComponents/componentCount;
end
