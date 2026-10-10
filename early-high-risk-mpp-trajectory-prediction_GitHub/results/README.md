# Reference aggregate results

These 19 CSV files are unchanged copies from the supplied completed formal MPP analysis. Hashes are recorded in `docs/provenance.json`. New analyses write to `analysis_output/tables/`; this directory is the reference record.

| File | Contents |
|---|---|
| 01_cohort_summary.csv | Cohort sizes, high-risk counts and prevalence |
| 02_LASSO_CV_source.csv | Lambda grid, CV deviance, error bars and glmnet nonzero counts |
| 02_LASSO_path_source.csv | Coefficient paths used for the LASSO figure |
| 02_LASSO_selected_features.csv | Selected encoded features and coefficients |
| 03_best_hyperparameters.csv | Final fitted hyperparameter values |
| 03_calibration_source.csv | Ten-bin calibration-curve summaries |
| 03_calibration_statistics.csv | Prevalence, mean predictions and evaluation calibration intercept/slope |
| 03_classification_thresholds.csv | Model-specific training OOF Youden thresholds |
| 03_DCA_source.csv | Net benefit for five models, treat-all and treat-none; 1%–80% threshold grid |
| 03_machine_learning_settings.csv | Formal CV, tuning, bootstrap, worker and seed settings |
| 03_performance_bootstrap_ci.csv | 95% percentile bootstrap intervals for AUROC, AUPRC and Brier score |
| 03_performance_metrics.csv | All eight performance metrics by cohort and model |
| 03_tuning_xgboost.csv | XGBoost aggregate tuning archive |
| 03_tuning_ranger.csv | Random-forest aggregate tuning archive |
| 03_tuning_svm.csv | SVM aggregate tuning archive |
| 03_tuning_kknn.csv | k-NN aggregate tuning archive |
| 04_XGBoost_SHAP_importance.csv | Encoded-feature mean absolute SHAP and ranking |
| 06_confusion_counts.csv | Aggregate confusion counts from the original audit |
| 06_original_variable_selection.csv | Selection status of the 13 original candidate variables |

The two `06_` tables were supplied by the original collection/audit step; their prefix is independent of the new `06_export_deployment.R`. Steps 01–05 reproduce the principal analysis outputs. A separate audit-generation utility is not needed to train or evaluate the models.

Training OOF, internal validation and external validation have distinct roles and must not be pooled as independent validation estimates. AUROC differences are descriptive; no paired significance comparison is supplied. The reported AUPRC implements average precision, while random-search tuning uses mlr3's PR-AUC measure.

The SHAP importance table is an aggregate summary. Individual identifiers, predictions, feature values, SHAP-value tables and preprocessing workbooks are deliberately absent. The original patient-level files remain necessary to regenerate some analyses in an authorized local environment.
