# Environment and verification

- `../renv.lock`: R 4.4.2 and the installed package dependency versions recorded during preparation of this release.
- `package_versions.csv`: direct dependency versions in that environment.
- `sessionInfo.txt`: environment of model export and prediction-parity verification, not a historical full-analysis session dump.
- `deployment_validation.csv`: aggregate parity/additivity checks against the saved original analysis objects.
- `release_checks.txt`: syntax and local research-calculator checks performed for this code package.

All 11,840 raw records stored in the original preprocessing object were passed through the new calculator preprocessing functions; the resulting selected matrices matched exactly. The 7,014 internal/external XGBoost calibrated probabilities matched the saved analysis probabilities with maximum absolute error below 1e-14. Training OOF probabilities were not compared with the final deployed model, because OOF values come from separate fold models. TreeSHAP additivity was checked for 16 profiles from each cohort, with maximum absolute error below 1e-4.

The local app was additionally checked with synthetic input profiles. Syntax/calculator checks do not rerun feature selection or full model fitting. Dependency restoration requires network access and was not repeated in a clean external environment during packaging. Historical package state cannot be reconstructed beyond the supplied records; this lock file captures the environment verified for the release.
