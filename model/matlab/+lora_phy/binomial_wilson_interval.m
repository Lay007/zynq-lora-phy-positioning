function [lower, upper] = binomial_wilson_interval(errors, trials)
%BINOMIAL_WILSON_INTERVAL Two-sided 95 percent Wilson score interval.

errors = double(errors);
trials = double(trials);
if ~isequal(size(errors), size(trials)) && ~isscalar(errors) && ~isscalar(trials)
    error("lora_phy:SizeMismatch", ...
        "errors and trials must be scalar-compatible arrays");
end
if any(trials <= 0, "all") || any(errors < 0, "all") || ...
        any(errors > trials, "all")
    error("lora_phy:InvalidBinomialCounts", ...
        "Require 0 <= errors <= trials and trials > 0");
end
z = 1.95996398454005;
rate = errors./trials;
denominator = 1+z^2./trials;
centre = (rate+z^2./(2*trials))./denominator;
radius = z*sqrt(rate.*(1-rate)./trials+z^2./(4*trials.^2))./denominator;
lower = max(0, centre-radius);
upper = min(1, centre+radius);
end
