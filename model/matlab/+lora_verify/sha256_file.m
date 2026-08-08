function digest = sha256_file(filePath)
%SHA256_FILE Lowercase hexadecimal SHA-256 of a file's bytes.

file = fopen(filePath, "r");
if file < 0
    error("lora_verify:ChecksumFile", "Cannot open %s", filePath);
end
cleanup = onCleanup(@() fclose(file));
bytes = fread(file, Inf, "*uint8");

engine = java.security.MessageDigest.getInstance("SHA-256");
engine.update(bytes);
raw = typecast(engine.digest(), "uint8");
digest = string(lower(sprintf("%02x", raw)));
end
