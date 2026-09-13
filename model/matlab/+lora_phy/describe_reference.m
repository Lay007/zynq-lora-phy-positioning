function text = describe_reference(metadata, strings)
%DESCRIBE_REFERENCE Localized description of the selected TX checkpoint.

arguments
    metadata (1,1) struct
    strings (1,1) struct
end

if isfield(metadata, "stageNumber")
    stageNumber = metadata.stageNumber;
elseif isfield(metadata, "tag") && metadata.tag == "package"
    stageNumber = 2;
else
    stageNumber = 1;
end

switch stageNumber
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
        if strings.language == "ru"
            text = "после КИХ/ресемплера 24/25";
        else
            text = "after FIR/resampler 24/25";
        end
    case 4
        if strings.language == "ru"
            text = "после CIC-интерполятора x32";
        else
            text = "after CIC interpolator x32";
        end
    case 5
        if strings.language == "ru"
            text = "после частотного переноса";
        else
            text = "after frequency shift";
        end
    otherwise
        if strings.language == "ru"
            text = "неизвестная контрольная точка TX";
        else
            text = "unknown TX checkpoint";
        end
end
end
