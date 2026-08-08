function tdoaSeconds = tdoa_from_toas(toaSeconds, options)
%TDOA_FROM_TOAS Calibrate receiver timestamps and form TDoA observations.
%
% Receiver 1 is the reference. ReceiverDelaySeconds contains the fixed delay
% of every receive channel. Subtracting it from the measured ToA removes the
% calibrated cable, RF, ADC, and DSP contribution before differencing.

arguments
    toaSeconds (:,1) double {mustBeFinite}
    options.ReceiverDelaySeconds (:,1) double = zeros(0, 1)
end

if numel(toaSeconds) < 2
    error("lora_phy:InsufficientToa", ...
        "toaSeconds must contain at least two receiver timestamps");
end
receiverDelaySeconds = options.ReceiverDelaySeconds;
if isempty(receiverDelaySeconds)
    receiverDelaySeconds = zeros(size(toaSeconds));
elseif numel(receiverDelaySeconds) ~= numel(toaSeconds)
    error("lora_phy:DelayCountMismatch", ...
        "ReceiverDelaySeconds must contain one value per receiver");
end
calibratedToa = toaSeconds-receiverDelaySeconds;
tdoaSeconds = calibratedToa(2:end)-calibratedToa(1);
end
