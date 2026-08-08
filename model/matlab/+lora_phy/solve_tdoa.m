function result = solve_tdoa( ...
    receiverPositionsMeters, tdoaSeconds, options)
%SOLVE_TDOA Solve calibrated TDoA observations by weighted Gauss-Newton.
%
% Receiver 1 is the reference. MeasurementStdSeconds may be scalar or one
% value per non-reference receiver. The result exposes residuals and the
% weighted geometry condition number so ill-conditioned results are visible.

arguments
    receiverPositionsMeters (:,:) double {mustBeFinite}
    tdoaSeconds (:,1) double {mustBeFinite}
    options.InitialPositionMeters (1,:) double = zeros(1, 0)
    options.MeasurementStdSeconds (:,1) double = ones(0, 1)
    options.MeasurementCovarianceSecondsSquared (:,:) double = zeros(0, 0)
    options.PropagationSpeedMetersPerSecond (1,1) double ...
        {mustBePositive} = 299792458
    options.MaximumIterations (1,1) double ...
        {mustBeInteger, mustBePositive} = 50
    options.ToleranceMeters (1,1) double {mustBePositive} = 1e-6
    options.Damping (1,1) double {mustBeNonnegative} = 1e-9
end

receiverCount = size(receiverPositionsMeters, 1);
dimension = size(receiverPositionsMeters, 2);
if dimension < 1 || receiverCount < dimension+1
    error("lora_phy:InsufficientReceivers", ...
        "TDoA requires at least dimension + 1 receivers");
end
if numel(tdoaSeconds) ~= receiverCount-1
    error("lora_phy:ObservationCountMismatch", ...
        "tdoaSeconds must contain one value per non-reference receiver");
end
if isempty(options.InitialPositionMeters)
    position = mean(receiverPositionsMeters, 1);
elseif numel(options.InitialPositionMeters) ~= dimension || ...
        any(~isfinite(options.InitialPositionMeters))
    error("lora_phy:InitialPositionDimensionMismatch", ...
        "InitialPositionMeters must match the receiver dimension");
else
    position = options.InitialPositionMeters;
end
observationCount = receiverCount-1;
covariance = options.MeasurementCovarianceSecondsSquared;
if ~isempty(covariance)
    if ~isempty(options.MeasurementStdSeconds)
        error("lora_phy:ConflictingMeasurementUncertainty", ...
            "Specify either standard deviations or a covariance, not both");
    end
    if ~isequal(size(covariance), [observationCount, observationCount]) || ...
            any(~isfinite(covariance), "all") || ...
            norm(covariance-covariance.', "fro") > ...
            1e-12*max(norm(covariance, "fro"), eps)
        error("lora_phy:InvalidMeasurementCovariance", ...
            "Measurement covariance must be finite, square, and symmetric");
    end
    [whiteningCholesky, positiveDefinite] = chol(covariance, "lower");
    if positiveDefinite ~= 0
        error("lora_phy:InvalidMeasurementCovariance", ...
            "Measurement covariance must be positive definite");
    end
else
    standardDeviation = options.MeasurementStdSeconds;
    if isempty(standardDeviation)
        standardDeviation = ones(observationCount, 1);
    elseif isscalar(standardDeviation)
        standardDeviation = repmat(standardDeviation, observationCount, 1);
    elseif numel(standardDeviation) ~= observationCount
        error("lora_phy:UncertaintyCountMismatch", ...
            "MeasurementStdSeconds must be scalar or match tdoaSeconds");
    end
    if any(~isfinite(standardDeviation) | standardDeviation <= 0)
        error("lora_phy:InvalidMeasurementUncertainty", ...
            "MeasurementStdSeconds values must be finite and positive");
    end
    whiteningCholesky = diag(standardDeviation);
end

propagationSpeed = options.PropagationSpeedMetersPerSecond;
converged = false;
stepMeters = nan(1, dimension);
iterations = 0;
conditionNumber = Inf;
for iteration = 1:options.MaximumIterations
    iterations = iteration;
    [predicted, jacobian] = geometry(position, ...
        receiverPositionsMeters, propagationSpeed);
    residual = predicted-tdoaSeconds;
    weightedJacobian = whiteningCholesky\jacobian;
    weightedResidual = whiteningCholesky\residual;
    normalMatrix = weightedJacobian.'*weightedJacobian;
    dampingScale = max(trace(normalMatrix)/max(dimension, 1), eps);
    stepMeters = -(normalMatrix+options.Damping*dampingScale* ...
        eye(dimension))\(weightedJacobian.'*weightedResidual);
    position = position+stepMeters.';
    singularValues = svd(weightedJacobian, "econ");
    if isempty(singularValues) || singularValues(end) <= eps
        conditionNumber = Inf;
    else
        conditionNumber = singularValues(1)/singularValues(end);
    end
    if norm(stepMeters) <= options.ToleranceMeters
        converged = true;
        break
    end
end
[predicted, jacobian] = geometry(position, ...
    receiverPositionsMeters, propagationSpeed);
residual = predicted-tdoaSeconds;
weightedJacobian = whiteningCholesky\jacobian;
information = weightedJacobian.'*weightedJacobian;
if rcond(information) > eps
    covarianceMetersSquared = inv(information); %#ok<MINV>
else
    covarianceMetersSquared = nan(dimension);
end

result = struct;
result.positionMeters = position;
result.predictedTdoaSeconds = predicted;
result.residualSeconds = residual;
result.iterations = iterations;
result.converged = converged;
result.lastStepMeters = stepMeters.';
result.geometryConditionNumber = conditionNumber;
result.covarianceMetersSquared = covarianceMetersSquared;
result.measurementCovarianceSecondsSquared = ...
    whiteningCholesky*whiteningCholesky.';
result.referenceReceiver = 1;
result.propagationSpeedMetersPerSecond = propagationSpeed;
end

function [predicted, jacobian] = geometry( ...
    position, receivers, propagationSpeed)
offsets = position-receivers;
ranges = vecnorm(offsets, 2, 2);
safeRanges = max(ranges, eps);
unitVectors = offsets./safeRanges;
predicted = (ranges(2:end)-ranges(1))/propagationSpeed;
jacobian = (unitVectors(2:end, :)-unitVectors(1, :))/ ...
    propagationSpeed;
end
