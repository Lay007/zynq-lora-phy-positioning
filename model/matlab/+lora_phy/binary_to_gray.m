function gray = binary_to_gray(binary)
%BINARY_TO_GRAY Convert unsigned binary labels to Gray labels.

binary = uint16(binary(:));
gray = bitxor(binary, bitshift(binary, -1));
end
