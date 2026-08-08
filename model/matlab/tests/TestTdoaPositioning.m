classdef TestTdoaPositioning < matlab.unittest.TestCase
    methods (Test)
        function calibratedToasUseReceiverOneAsReference(testCase)
            measured = [1; 1.25+20e-9; 0.75-10e-9];
            delays = [0; 20e-9; -10e-9];

            result = lora_phy.tdoa_from_toas(measured, ...
                ReceiverDelaySeconds=delays);

            testCase.verifyEqual(result, [0.25; -0.25], ...
                "AbsTol", 10*eps);
        end

        function noiselessTwoDimensionalPositionIsRecovered(testCase)
            receivers = [0, 0; 100, 0; 100, 80; 0, 80];
            truth = [31, 27];
            observations = lora_phy.predict_tdoa(truth, receivers);

            result = lora_phy.solve_tdoa(receivers, observations);

            testCase.verifyTrue(result.converged);
            testCase.verifyEqual(result.positionMeters, truth, ...
                "AbsTol", 1e-6);
            testCase.verifyEqual(result.residualSeconds, ...
                zeros(3, 1), "AbsTol", 1e-14);
        end

        function weightedSolverAcceptsRedundantReceivers(testCase)
            receivers = [0, 0; 120, 0; 120, 90; 0, 90; 60, 130];
            truth = [43, 51];
            observations = lora_phy.predict_tdoa(truth, receivers);
            observations = observations+[0.2; -0.1; 0.15; -0.05]*1e-9;

            result = lora_phy.solve_tdoa(receivers, observations, ...
                MeasurementStdSeconds=[1; 1; 2; 2]*1e-9);

            testCase.verifyTrue(result.converged);
            testCase.verifyLessThan(norm(result.positionMeters-truth), 0.2);
            testCase.verifySize(result.covarianceMetersSquared, [2, 2]);
        end

        function fullTdoaCovarianceAccountsForCommonReference(testCase)
            receivers = [0, 0; 100, 0; 100, 80; 0, 80];
            truth = [37, 29];
            observations = lora_phy.predict_tdoa(truth, receivers);
            receiverVariance = (1e-9)^2;
            covariance = receiverVariance*(eye(3)+ones(3));

            result = lora_phy.solve_tdoa(receivers, observations, ...
                MeasurementCovarianceSecondsSquared=covariance);

            testCase.verifyTrue(result.converged);
            testCase.verifyEqual(result.positionMeters, truth, ...
                "AbsTol", 1e-6);
            testCase.verifyEqual( ...
                result.measurementCovarianceSecondsSquared, covariance, ...
                "RelTol", 1e-12);
        end

        function simulationIsDeterministicAndReportsPositionError(testCase)
            first = lora_phy.simulate_tdoa_accuracy([0.2e-9; 1e-9], ...
                TrialsPerPoint=20, RandomSeed=91);
            second = lora_phy.simulate_tdoa_accuracy([0.2e-9; 1e-9], ...
                TrialsPerPoint=20, RandomSeed=91);

            testCase.verifyEqual(first.summary, second.summary);
            testCase.verifyEqual(first.summary.Trials, [20; 20]);
            testCase.verifyGreaterThan(first.summary.ConvergenceRate, 0.9);
            testCase.verifyGreaterThan(first.summary.RmseMeters(2), ...
                first.summary.RmseMeters(1));
        end

        function observationCountIsValidated(testCase)
            receivers = [0, 0; 1, 0; 0, 1];

            testCase.verifyError(@() lora_phy.solve_tdoa( ...
                receivers, 0), "lora_phy:ObservationCountMismatch");
        end
    end
end
