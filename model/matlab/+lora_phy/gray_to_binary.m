function binary = gray_to_binary(gray)
%GRAY_TO_BINARY Convert unsigned Gray labels to binary labels.

binary = uint16(gray(:));
shifted = bitshift(binary, -1);
while any(shifted)
    binary = bitxor(binary, shifted);
    shifted = bitshift(shifted, -1);
end
end
