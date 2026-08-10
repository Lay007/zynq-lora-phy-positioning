function [matched, worst] = stage_vectors_match(report)
%STAGE_VECTORS_MATCH Does a stage comparison count as agreement?
%
% One predicate, used by the committed-vector test and by anything else that
% has to decide whether recomputed stages still match what was written. It
% exists as a function so the rule cannot be exact equality in one place and
% a tolerance in another.
%
% See LORA_VERIFY.STAGE_TOLERANCE for why the rule is relative RMS rather
% than bit-identity.
% The rule as it stands today: bit-identity. This is the defect the
% accompanying test reproduces, and it is fixed in the next commit.
worst = max(report.RelativeRms);
matched = max(report.MaxAbsError) == 0;
end
