function result = simulate_tdoa_accuracy(noiseStdSeconds, options)
%SIMULATE_TDOA_ACCURACY Characterize calibrated 2D TDoA positioning error.

arguments
    noiseStdSeconds (:,1) double {mustBeNonnegative, mustBeFinite}
    options.TrialsPerPoint (1,1) double ...
        {mustBeInteger, mustBePositive} = 1000
    options.ReceiverPositionsMeters (:,2) double = ...
        [0, 0; 100, 0; 100, 80; 0, 80]
    options.PositionBoundsMeters (2,2) double = [10, 10; 90, 70]
    options.ReceiverDelaySeconds (:,1) double = ...
        [0; 35e-9; -20e-9; 50e-9]
    options.CalibrationErrorStdSeconds (1,1) double ...
        {mustBeNonnegative} = 0
    options.OutlierThresholdMeters (1,1) double {mustBePositive} = 10
    options.RandomSeed (1,1) double ...
        {mustBeInteger, mustBeNonnegative} = 7000
end

receivers = options.ReceiverPositionsMeters;
receiverCount = size(receivers, 1);
if receiverCount < 3
    error("lora_phy:InsufficientReceivers", ...
        "2D TDoA requires at least three receivers");
end
if any(options.PositionBoundsMeters(2, :) <= ...
        options.PositionBoundsMeters(1, :))
    error("lora_phy:InvalidPositionBounds", ...
        "The upper position bounds must exceed the lower bounds");
end
receiverDelays = options.ReceiverDelaySeconds;
if isempty(receiverDelays)
    receiverDelays = zeros(receiverCount, 1);
elseif numel(receiverDelays) ~= receiverCount
    error("lora_phy:DelayCountMismatch", ...
        "ReceiverDelaySeconds must contain one value per receiver");
end

previousState = rng;
restoreState = onCleanup(@() rng(previousState));
rng(options.RandomSeed, "twister");
rows = repmat(empty_row(), numel(noiseStdSeconds), 1);
details = cell(numel(noiseStdSeconds), 1);
for point = 1:numel(noiseStdSeconds)
    positionErrors = nan(options.TrialsPerPoint, 1);
    residualRmsSeconds = nan(options.TrialsPerPoint, 1);
    converged = false(options.TrialsPerPoint, 1);
    for trial = 1:options.TrialsPerPoint
        lower = options.PositionBoundsMeters(1, :);
        upper = options.PositionBoundsMeters(2, :);
        truePosition = lower+(upper-lower).*rand(1, 2);
        geometricTdoa = lora_phy.predict_tdoa(truePosition, receivers);
        transmitEpoch = 10+rand;
        ranges = vecnorm(receivers-truePosition, 2, 2);
        measuredToa = transmitEpoch+ranges/299792458+receiverDelays+ ...
            noiseStdSeconds(point)*randn(receiverCount, 1);
        estimatedDelays = receiverDelays+ ...
            options.CalibrationErrorStdSeconds*randn(receiverCount, 1);
        observedTdoa = lora_phy.tdoa_from_toas(measuredToa, ...
            ReceiverDelaySeconds=estimatedDelays);
        receiverVariance = noiseStdSeconds(point)^2+ ...
            options.CalibrationErrorStdSeconds^2;
        receiverVariance = max(receiverVariance, eps^2);
        tdoaCovariance = receiverVariance*( ...
            eye(receiverCount-1)+ones(receiverCount-1));
        estimate = lora_phy.solve_tdoa(receivers, observedTdoa, ...
            MeasurementCovarianceSecondsSquared=tdoaCovariance, ...
            InitialPositionMeters=mean(receivers, 1));
        converged(trial) = estimate.converged;
        if estimate.converged
            positionErrors(trial) = norm(estimate.positionMeters-truePosition);
            residualRmsSeconds(trial) = rms( ...
                estimate.predictedTdoaSeconds-geometricTdoa);
        end
    end
    validErrors = positionErrors(isfinite(positionErrors));
    row = empty_row();
    row.NoiseStdNanoseconds = noiseStdSeconds(point)*1e9;
    row.CalibrationErrorStdNanoseconds = ...
        options.CalibrationErrorStdSeconds*1e9;
    row.Trials = options.TrialsPerPoint;
    row.Converged = nnz(converged);
    row.ConvergenceRate = mean(converged);
    if ~isempty(validErrors)
        row.RmseMeters = sqrt(mean(validErrors.^2));
        row.MedianErrorMeters = median(validErrors);
        sortedErrors = sort(validErrors);
        percentileIndex = max(1, ceil(0.95*numel(sortedErrors)));
        row.P95ErrorMeters = sortedErrors(percentileIndex);
        row.OutlierRate = mean(validErrors > ...
            options.OutlierThresholdMeters);
        row.ResidualRmsNanoseconds = rms( ...
            residualRmsSeconds(isfinite(residualRmsSeconds)))*1e9;
    end
    rows(point) = row;
    details{point} = struct("positionErrorMeters", positionErrors, ...
        "residualRmsSeconds", residualRmsSeconds, ...
        "converged", converged);
end
result = struct("schema", "zynq-lora-tdoa-accuracy-v1", ...
    "summary", struct2table(rows), "details", {details}, ...
    "receiverPositionsMeters", receivers, ...
    "positionBoundsMeters", options.PositionBoundsMeters, ...
    "receiverDelaySeconds", receiverDelays, ...
    "outlierThresholdMeters", options.OutlierThresholdMeters, ...
    "randomSeed", options.RandomSeed);
end

function row = empty_row()
row = struct("NoiseStdNanoseconds", 0, ...
    "CalibrationErrorStdNanoseconds", 0, "Trials", 0, ...
    "Converged", 0, "ConvergenceRate", 0, "RmseMeters", NaN, ...
    "MedianErrorMeters", NaN, "P95ErrorMeters", NaN, ...
    "OutlierRate", NaN, "ResidualRmsNanoseconds", NaN);
end
