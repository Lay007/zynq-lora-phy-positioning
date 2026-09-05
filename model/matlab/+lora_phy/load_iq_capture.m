function [iq, info] = load_iq_capture(filePath, format)
%LOAD_IQ_CAPTURE Read supported complex IQ capture formats.
%
% Supported formats:
%   cu8   - uint8 interleaved I,Q (RTL-SDR)
%   cf32  - little-endian float32 interleaved I,Q (Pluto/GNU Radio)
%   hdl32 - little-endian packed uint32 words {I[15:0], Q[15:0]} from HDL
%           simulation, with signed Q14-like int16 components.

filePath = string(filePath);
if nargin < 2 || string(format) == "auto"
    [~, ~, extension] = fileparts(filePath);
    switch lower(extension)
        case {'.cu8', '.uc8'}
            format = "cu8";
        case {'.cf32', '.fc32', '.cfile'}
            format = "cf32";
        case '.pcm'
            format = "hdl32";
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
    case "hdl32"
        file = fopen(filePath, "r", "ieee-le");
        cleanup = onCleanup(@() fclose(file));
        raw = fread(file, Inf, "uint32=>uint32");

        % HDL data_out is a 32-bit word {real[15:0], imag[15:0]}.
        % Because the file is little-endian, reading it directly as int16
        % would expose the halves as Q,I. Split the packed word explicitly.
        iBits = bitshift(raw, -16);
        qBits = bitand(raw, uint32(65535));
        i = double(iBits);
        q = double(qBits);
        i(i >= 32768) = i(i >= 32768) - 65536;
        q(q >= 32768) = q(q >= 32768) - 65536;

        % phase_to_sample keeps the DDS output at an approximately Q14 level.
        iq = complex(i, q) / 16384;
        clippedComponents = NaN;
        componentCount = 2*numel(raw);
    otherwise
        error("lora_phy:UnsupportedIqFormat", ...
            "Supported formats are auto, cu8, cf32, and hdl32");
end

iq = iq(:);
info = struct;
info.filePath = filePath;
info.format = format;
info.sampleCount = numel(iq);
info.componentCount = componentCount;
info.clippedComponentFraction = clippedComponents/componentCount;
end
