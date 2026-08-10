function tolerance = stage_tolerance
%STAGE_TOLERANCE Acceptance threshold for stage vectors against the model.
%
% Relative RMS, not absolute error, and deliberately not exact equality.
%
% The committed vectors are written by one machine and checked on others.
% Recomputing the same stages with a different FFT implementation lands a
% few last bits away: measured on Linux CI against vectors generated on
% Windows, the worst absolute difference was 7.3e-12 on stages whose values
% reach 1e6, which is about 1e-16 relative. That is double rounding, not a
% different answer.
%
% An earlier version of the check required bit-identity. It passed only on
% the machine that generated the vectors and failed every CI run from the
% day it was added, which is the whole reason this constant exists in one
% place rather than inline.
%
% 1e-12 is four orders above the rounding actually observed and eight below
% anything an algorithmic change would produce, so it separates the two
% without being tuned to either. It is the same threshold the Simulink
% acceptance uses, so the project has one number for "the model agrees".
tolerance = 1e-12;
end
