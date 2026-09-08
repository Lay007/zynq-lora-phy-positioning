function text = describe_reference(metadata, strings)
%DESCRIBE_REFERENCE Localized description of the golden reference symbol.
%
% parse_hdl_recording_name reports an English description built into the
% metadata. This rebuilds it from the structured fields instead, so the
% Inspector table and the launcher console line stay consistent and both
% follow the selected interface language.

arguments
    metadata (1,1) struct
    strings (1,1) struct
end

if metadata.tag == "package"
    text = string(strings.referencePackage);
elseif metadata.referenceDirection == "down"
    text = string(sprintf(strings.referenceChirp, ...
        metadata.referenceSymbol, strings.directionDown));
else
    text = string(sprintf(strings.referenceChirp, ...
        metadata.referenceSymbol, strings.directionUp));
end
end
