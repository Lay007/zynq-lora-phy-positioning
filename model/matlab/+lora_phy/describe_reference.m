function text = describe_reference(metadata, strings)
%DESCRIBE_REFERENCE Localized description of the selected TX checkpoint.

arguments
    metadata (1,1) struct
    strings (1,1) struct
end

switch metadata.stageNumber
    case 1
        if metadata.referenceDirection == "down"
            text = string(sprintf(strings.referenceChirp, ...
                metadata.referenceSymbol, strings.directionDown));
        else
            text = string(sprintf(strings.referenceChirp, ...
                metadata.referenceSymbol, strings.directionUp));
        end
    case 2
        text = string(strings.referencePackage);
    case 3
        text = string(strings.referenceResampler);
    case 4
        text = string(strings.referenceCic);
    case 5
        text = string(strings.referenceMixer);
    otherwise
        text = "unknown TX checkpoint";
end
end
