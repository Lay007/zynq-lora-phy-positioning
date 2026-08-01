function samples = modulate_symbol(symbol, config)
%MODULATE_SYMBOL Modulate one integer as a cyclic shift of the upchirp.

validateattributes(symbol, {'numeric'}, ...
    {"scalar", "integer", ">=", 0, "<", config.symbolCount}, ...
    mfilename, "symbol");

shift = double(symbol) * config.samplesPerChip;
samples = circshift(lora_phy.reference_chirp(config), -shift);
end
