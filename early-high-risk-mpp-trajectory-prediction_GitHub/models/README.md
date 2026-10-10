# Local and controlled-access model files

The public repository contains **no fitted models or model weights**. The original fitted learners, preprocessing objects and calibrators may retain individual-level data. A minimal deployment object removes those embedded records, but it is still a MIMIC-derived model. PhysioNet states that derived datasets and models should be treated as sensitive and shared under the same agreement as their source. See [MIMIC-IV v3.1: Guidelines for creating derived datasets or models](https://physionet.org/content/mimiciv/3.1/).

## Export after an authorized local analysis

The full runner calls step 06 after steps 01–05. To export from an existing authorized analysis:

```r
Sys.setenv(
  MPP_ML_ROOT = "D:/authorized-study-results/MPP-analysis",
  MPP_DEPLOYMENT_OUT = "D:/authorized-study-results/local-model/MPP_xgboost_deployment.rds"
)
source("06_export_deployment.R", encoding = "UTF-8")
```

These are example paths. Step 06 expects `objects/step1_preprocessed.rds`, `objects/step2_lasso.rds`, `models/final_xgboost.rds`, `models/platt_xgboost.rds`, and `tables/03_classification_thresholds.csv` from the supplied workflow. No tuning or training is performed during export.

The deployment object stores portable XGBoost model bytes, training preprocessing summaries, selected feature names, two Platt coefficients, the fixed training-derived threshold, labels and metadata. It excludes patient data frames, identifiers, individual predictions, fitted mlr3 learners and the original glm calibration object. The fitted booster is restored from its RDS snapshot and exported using the recorded XGBoost version. The predictor aligns to the original booster feature order, which differs from the LASSO feature-list order.

## Open the local calculator

```r
Sys.setenv(MPP_DEPLOYMENT_MODEL = "D:/authorized-study-results/local-model/MPP_xgboost_deployment.rds")
shiny::runApp(".", host = "127.0.0.1", launch.browser = TRUE)
```

The separately delivered `MPP_local_runtime` folder is for the author's authorized local use and is outside the GitHub package. Do not upload it, deploy its model to a public host, or remove the ignore rules merely because the deployment object has no patient rows. A future model deposit must follow the source-data sharing route; no controlled-access deposit or accession is claimed here.
