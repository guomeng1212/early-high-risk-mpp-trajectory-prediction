# Methods represented by the supplied code

## Input and preprocessing

MIMIC-IV v3.1 supplied the development and internal-validation cohorts; eICU-CRD v2.0 supplied external validation. The workflow reads the already eligible, merged, trajectory-labelled cohorts. HighRisk is Classes 1 and 3 combined; Other is Classes 2 and 4. The class and stay identifier never enter the predictor matrix. CABG and valve surgery are separate predictors; the intended surgical population includes either procedure or both.

With seed 20260902, MIMIC-IV was split within binary-outcome strata using `floor(0.70 * n_stratum)` training records. Missing numeric values were imputed with training medians, followed by winsorization at training 1st/99th percentiles. Categorical values were imputed with training modes; unseen categories were mapped to Unknown. `model.matrix(~ . - 1)` generated the design. Columns were centred and scaled with training means/SDs, with a denominator of 1 for nonfinite or zero SD. The exact categorical coding is determined by R's treatment contrasts and factor ordering in the original run; it is not an assertion that every category is separately retained.

## Feature selection

Thirteen candidate original variables comprised the Model 3 covariates excluding Class plus initial MPP. A binomial LASSO used `cv.glmnet`, alpha 1, 10 folds, deviance, and `standardize=FALSE` because the design was already scaled. The supplied `lambda.min` was approximately 0.00160449. The code retained coefficients with absolute value above 1e-8, excluding the intercept. This retained 13 encoded features representing 12 original variables; WBC was excluded. The CV plot's nonzero counts come directly from glmnet and can differ from this tolerance-based retained count because of coefficients extremely close to zero.

## Five-model development

All five classifiers used the selected training design. Logistic regression used `maxit=500`. XGBoost, random forest, radial SVM and k-NN were tuned by random search with 200, 150, 150 and 100 evaluations, respectively. A fixed stratified 10-fold scheme and `mlr3`'s `classif.prauc` tuning measure were used. The original ranges remain in `03_mlr3_machine_learning.R`. Random forest used 1,500 trees. The selected parameter values and complete aggregate tuning archives are in `results/`.

After tuning, the fitted hyperparameters were used in another resampling operation with the same folds to obtain OOF raw probabilities. Platt calibration fitted a binomial glm of the binary outcome on the logit of clipped OOF probabilities. A nonfinite coefficient triggered an intercept-only fallback. The probability clip was [1e-6, 1-1e-6]. The classification threshold maximized the Youden index on calibrated training OOF predictions. Final models were refitted on the full training subset; the stored calibrator and threshold were applied to internal and external validation without refitting there.

The training OOF calibration intercept/slope printed in the reference evaluation table are evaluation regressions on already calibrated probabilities. They are not the coefficients required to export the original Platt calibrator. Step 06 reads the actual fitted calibration object and retains its numeric coefficients.

## Evaluation and figures

The code reports AUROC, AUPRC, Brier score, sensitivity, specificity, PPV, NPV and F1. The final reported AUPRC uses a rank-based average-precision calculation in the preserved script; the tuning measure is mlr3's PR-AUC, so their numerical definitions should not be assumed identical. AUROC, AUPRC and Brier intervals use 1,000 outcome-stratified percentile bootstrap replicates with fixed predictions. These intervals do not refit the full pipeline or include feature-selection/tuning uncertainty. Calibration curves summarize ten prediction-rank groups. Reported calibration intercept and slope come from a joint logistic regression of the outcome on the logit of calibrated probabilities.

DCA net benefit is `TP / N - FP / N * pt / (1 - pt)`, with treat-all and treat-none comparators. The grid is 0.01–0.80 by 0.01, plotted across 0–0.80 and a net-benefit display range of -0.02–0.40. The final PNG is 10.8 × 6.2 inches at 600 dpi. Values outside the view are preserved in the aggregate source table. The supplied update to DCA only concerns this existing exploratory analysis and its presentation.

The SHAP script uses exact TreeSHAP (`predcontrib=TRUE`, `approxcontrib=FALSE`) for the final XGBoost model. Up to 1,000 MIMIC internal-validation rows were sampled with seed 20260902. Encoded-feature importance is mean absolute SHAP. The beeswarm uses raw model log-odds contributions and a feature-specific clipped colour scale based on the 5th/95th percentiles. Individual SHAP values, feature values and identifiers remain local; the public package contains the importance summary and figures.

## Limits that must remain explicit

1. Preprocessing and LASSO were performed on the whole training subset before model cross-validation. This preserved workflow is not fully nested CV of the entire pipeline. Tuning and OOF generation reused folds, and calibration/threshold fitting reused OOF outcomes. Training OOF performance is therefore more limited than independent validation.
2. Trajectory extraction, class correspondence between databases and the complete predictor timestamps are upstream dependencies not included here. SOFA and intervention variables may use first-24-hour information. A claim of prediction at ICU admission requires verifying that each predictor precedes the prediction time and that the outcome's trajectory window follows it.
3. High-risk membership is a predefined trajectory endpoint. The model does not directly estimate death or MAKE30. SHAP does not establish causal effects, and DCA without a specified intervention does not establish improved clinical outcomes.
4. External calibration differs from internal calibration. All five models' mean eICU predictions are below the observed 38.90% prevalence. No external recalibration or new threshold selection was performed for this packaging task.
5. The original merged datasets, row order, eligibility definitions, label-generation procedure, versioned environment and random seeds are needed for exact reproducibility. This repository provides the ML component and reports its boundaries rather than claiming an end-to-end raw-database reconstruction.
