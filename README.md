# Early high-risk MPP trajectory prediction after cardiac surgery

R code for predicting membership in predefined **high-risk mean perfusion pressure (MPP) trajectories** among adult ICU patients after **coronary artery bypass grafting (CABG) and/or valve surgery**. Patients with either procedure or both are eligible for the study population.

**High-risk outcome: Class 1 + Class 3 combined. Other group: Class 2 + Class 4.** `Class` defines the outcome and is never a predictor. The model predicts trajectory-group membership, rather than MAKE30 or mortality.

[中文使用说明](README_中文.md) · [Data dictionary](data/data_dictionary.csv) · [Methods and limitations](docs/METHODS.md) · [Data and code availability](docs/DATA_AVAILABILITY.md)

## Scope

This release packages the completed MPP machine-learning analysis: preprocessing, LASSO, five classifiers, calibration, internal and external validation, exact TreeSHAP, and the revised decision-curve plot. It also supplies a local Shiny research calculator and a minimal model-export script.

The five original analysis scripts retain their statistical code, seeds, tuning ranges, selection rules and plotting logic. Only input/output paths were made configurable. Published reference tables and figures were copied from the supplied completed formal run; no models were retrained to prepare this release. File provenance is recorded in [docs/provenance.json](docs/provenance.json).

The workflow starts with one merged, trajectory-labelled row per ICU stay. Database extraction, surgery ascertainment, trajectory fitting/class assignment, Table 1 and association/survival analyses are upstream or separate analyses and are not included in this ML repository. In particular, this code does not fit the four trajectories or infer their clinical risk ranking.

## Cohorts and prediction target

| Dataset | Role | N | High-risk N | High-risk prevalence |
|---|---|---:|---:|---:|
| MIMIC-IV v3.1 | Training | 4,826 | 1,260 | 26.11% |
| MIMIC-IV v3.1 | Internal validation | 2,070 | 541 | 26.14% |
| eICU-CRD v2.0 | External validation | 4,944 | 1,923 | 38.90% |

The 6,896 MIMIC-IV stays were split once, approximately 70:30, stratified by the binary outcome. The eICU cohort was held out from fitting and tuning. The input files must already satisfy the study eligibility criteria and use corresponding trajectory labels across databases; the ML scripts do not reapply the database cohort query.

### Candidate and selected predictors

The 13 candidates are the Model 3 adjustment covariates excluding `Class`, plus initial MPP:

`Age`, `Gender`, `Race`, `CABG`, `Valve`, `SOFA`, `CCI`, `Hb`, `WBC`, `Plt`, `Vasopressors`, `Mechanical_Ventilation`, `MPP`.

Training-only LASSO used binomial deviance, 10-fold cross-validation, `alpha = 1`, `standardize = FALSE`, and `lambda.min`. The selection tolerance was `abs(coefficient) > 1e-8`.

The supplied run retained **12 original variables, represented by 13 encoded features**. **WBC was excluded**. Retained encoded features were `Age`, `GenderF`, `RaceBlack`, `RaceWhite`, `CABGYes`, `ValveYes`, `SOFA`, `CCI`, `Hb`, `Plt`, `VasopressorsYes`, `Mechanical_VentilationYes`, and `MPP`. The export/prediction interface preserves the booster’s stored feature order.

## Files

```text
00_setup.R                     Restore the recorded R dependencies
00_run_all.R                   Run the full local analysis and model export
01_preprocessing.R             Harmonize names, split, impute, encode and scale
02_feature_engineering.R       Training-cohort LASSO selection
03_mlr3_machine_learning.R     Five models, tuning, calibration and evaluation
04_SHAP.R                      Exact XGBoost TreeSHAP
05_replot_DCA_png.R             Revised DCA, threshold axis through 80%
06_export_deployment.R         Export an authorized local XGBoost model
app.R                          Local Shiny research calculator
R/predict_mpp.R                Shared preprocessing, prediction and SHAP functions
data/                          Data instructions and column dictionary only
models/                        Model-access instructions only
results/                       19 aggregate tables from the formal run
figures/                       Seven original analysis figures
environment/                   Package versions and verification records
docs/                          Methods, availability, references and provenance
tests/run_checks.R             Syntax and optional local-calculator checks
renv.lock                      R/package versions recorded during release checks
```

## Reproduce the analysis

Use R **4.4.2** for the recorded environment. The original figures use Times New Roman; this font must be installed to reproduce the typography. The source scripts use `ragg` for PNG output. Source-package installation on Windows may require the matching R build tools.

1. Obtain credentialed access to [MIMIC-IV v3.1](https://physionet.org/content/mimiciv/3.1/) and [eICU-CRD v2.0](https://physionet.org/content/eicu-crd/2.0/), then prepare the study-specific merged and trajectory-labelled files described in [data/README.md](data/README.md).
2. Put those local files at `data/MIMICIV.csv` and `data/EICU.csv`, or set `MPP_MIMIC_FILE` and `MPP_EICU_FILE` to their existing paths. Do not upload them to GitHub.
3. Start R in this repository and run:

```r
source("00_setup.R", encoding = "UTF-8")
Sys.setenv(MPP_ML_FAST = "0", MPP_ML_WORKERS = "10")
source("00_run_all.R", encoding = "UTF-8")
```

For an existing project library in a later R session, run `renv::load(project = ".")` before the analysis. The explicit setup script is used instead of an automatic `.Rprofile` bootstrap.

The full workflow is computationally intensive: 10-fold CV, random-search evaluations of 200/150/150/100 for XGBoost/random forest/SVM/k-NN, and 1,000 stratified bootstrap replicates. Logistic regression has no random-search tuning. Formal run settings are recorded in [results/03_machine_learning_settings.csv](results/03_machine_learning_settings.csv).

`MPP_ML_FAST = "1"` is only a pipeline smoke-test setting: it reduces model CV to 3 folds, tuning to 5 evaluations per tuned model, and bootstrap repetitions to 20. It retains the 10-fold LASSO step and does not reproduce the supplied formal results. Use a separate output folder for trial runs.

### Path configuration

| Environment variable | Default / meaning |
|---|---|
| `MPP_REPO_ROOT` | Current working directory for setup, runner, tests and app |
| `MPP_DATA_DIR` | `<repository>/data` |
| `MPP_MIMIC_FILE` | `<MPP_DATA_DIR>/MIMICIV.csv` |
| `MPP_EICU_FILE` | `<MPP_DATA_DIR>/EICU.csv` |
| `MPP_ML_ROOT` | `<repository>/analysis_output`; all newly generated analysis outputs |
| `MPP_ML_FAST` | `0`; formal analysis |
| `MPP_ML_WORKERS` | Automatically chosen if absent; supplied formal run used 10 |
| `MPP_DEPLOYMENT_OUT` | `<MPP_ML_ROOT>/models/MPP_xgboost_deployment.rds` |
| `MPP_DEPLOYMENT_MODEL` | Local deployment file used by the app/tests |

`results/` and `figures/` contain the supplied reference outputs. New runs write to `analysis_output/`, not those reference folders. Reproducing the exact random split also requires the original input-row order. Operating system, parallel scheduling and library differences can affect refitted results; `renv.lock` records the environment used for release validation, not a historical snapshot created during the original fit.

## Local research calculator

XGBoost is the model used for the existing SHAP analysis and calculator. The public package contains the calculator code; trained model files are provided through authorized local or controlled-access workflows. PhysioNet explicitly states that MIMIC-derived models should be treated as sensitive information and shared under the source-data agreement. See the [official model-sharing guidance](https://physionet.org/content/mimiciv/3.1/) and [models/README.md](models/README.md).

After the full local pipeline, run:

```r
renv::load(project = ".")
shiny::runApp(".", host = "127.0.0.1", launch.browser = TRUE)
```

For an already exported, authorized model, set `MPP_DEPLOYMENT_MODEL` to its absolute local path before starting the app. Without a model file, the app displays setup instructions. The calculator uses the 12 retained original variables, displays the Platt-calibrated probability, applies the training-derived Youden threshold (approximately 25.28%), and shows individual TreeSHAP contributions on the **raw log-odds** scale. Default input values are training medians/modes and must be replaced with the intended profile.

## Reference results

| Model | Internal AUROC (95% CI) | External AUROC (95% CI) |
|---|---:|---:|
| Logistic regression | 0.820 (0.797–0.841) | 0.778 (0.764–0.791) |
| XGBoost | 0.826 (0.805–0.846) | 0.768 (0.754–0.783) |
| Random forest | 0.828 (0.807–0.848) | 0.765 (0.752–0.779) |
| SVM-RBF | 0.825 (0.803–0.846) | 0.762 (0.748–0.775) |
| k-NN | 0.804 (0.782–0.825) | 0.727 (0.714–0.742) |

These are point estimates with percentile bootstrap intervals from the supplied analysis. XGBoost was selected for the existing explanations/calculator; **logistic regression had the highest external-validation AUROC** among the five models. The code does not establish that these model differences are statistically significant.

![Internal and external ROC curves](figures/03_ROC.png)

See [results/README.md](results/README.md) for all aggregate files, including AUPRC, Brier score, classification metrics, calibration, tuning and DCA outputs.

## Interpretation and methodological boundaries

- Predictor preprocessing and LASSO selection used the full MIMIC training subset before model CV. Tuning and subsequent OOF prediction used the same fold structure; Platt calibration and threshold selection also used those OOF outcomes. Training OOF metrics therefore are not a fully nested, independent assessment of the entire pipeline.
- Some predictors describe the first 24 hours. The database extraction/trajectory-fitting code was not supplied here, so the precise availability of every predictor before the intended prediction time has not been established by this repository. “Early” should not be interpreted as an ICU-admission-time implementation without a timing audit.
- The observed eICU high-risk prevalence was 38.90%, while mean calibrated predictions were 28.79%–31.24% across models. External probability calibration should be considered when interpreting transportability.
- DCA is retained as an exploratory analysis of this trajectory-classification outcome. An intervention and clinical action threshold were not defined or evaluated. Its net benefit cannot by itself establish improved patient outcomes. The updated plot displays 0%–80% on the x-axis; calculations use 1%–80%. Values outside the displayed y-range remain in the source table.
- Exact TreeSHAP explains the raw XGBoost score. It does not provide causal effects or an additive decomposition of the calibrated probability.

## Verification

```r
source("tests/run_checks.R", encoding = "UTF-8")
# Set MPP_DEPLOYMENT_MODEL before this command to also check a local model.
```

Release preparation checked all 11,840 preprocessed rows against the original saved matrices and all 7,014 held-out XGBoost predictions against the saved analysis output. Maximum absolute calibrated-probability difference was below `1e-14`; TreeSHAP additivity was checked on 48 profiles. The record is [environment/deployment_validation.csv](environment/deployment_validation.csv). These checks verify implementation consistency and do not constitute new clinical validation.

## Data, citation and license

Patient-level data, split identifiers, individual predictions/SHAP tables, fitted learners and model weights are excluded. `.gitignore` covers local cohort files and generated outputs. MIT applies to the repository code; it does not replace the source-data terms.

Use [CITATION.cff](CITATION.cff) for the software metadata. Formal dataset references are in [docs/references.bib](docs/references.bib): MIMIC-IV v3.1, DOI [10.13026/kpb9-mt58](https://doi.org/10.13026/kpb9-mt58); eICU-CRD v2.0, DOI [10.13026/C2WM1R](https://doi.org/10.13026/C2WM1R). The software repository URL and article citation should be added once they exist; this package does not invent a publication or software DOI.
