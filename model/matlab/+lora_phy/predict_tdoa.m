function tdoaSeconds = predict_tdoa( ...
    positionMeters, receiverPositionsMeters, options)
%PREDICT_TDOA Predict geometric TDoA relative to receiver 1.

arguments
    positionMeters (1,:) double {mustBeFinite}
    receiverPositionsMeters (:,:) double {mustBeFinite}
    options.PropagationSpeedMetersPerSecond (1,1) double ...
        {mustBePositive} = 299792458
end

dimension = size(receiverPositionsMeters, 2);
if numel(positionMeters) ~= dimension
    error("lora_phy:PositionDimensionMismatch", ...
        "Position and receiver dimensions must match");
end
if size(receiverPositionsMeters, 1) < dimension+1
    error("lora_phy:InsufficientReceivers", ...
        "TDoA requires at least dimension + 1 receivers");
end
rangesMeters = vecnorm(receiverPositionsMeters-positionMeters, 2, 2);
tdoaSeconds = (rangesMeters(2:end)-rangesMeters(1))/ ...
    options.PropagationSpeedMetersPerSecond;
end
