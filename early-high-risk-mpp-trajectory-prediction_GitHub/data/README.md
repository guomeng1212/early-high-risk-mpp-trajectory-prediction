# Input data contract

This directory contains documentation only. Obtain MIMIC-IV v3.1 and eICU-CRD v2.0 through their official PhysioNet credentialed-access processes. The study-specific merged CSVs are not distributed.

## Required local files

- `MIMICIV.csv`: the eligible MIMIC-IV development cohort, one row per ICU stay.
- `EICU.csv`: the independently prepared eICU external-validation cohort, one row per ICU stay.

Both files must already contain the study's four-class MPP trajectory assignment. Class numbers must represent the intended corresponding phenotypes across cohorts. These scripts merge Classes 1 and 3; they do not estimate or relabel the trajectories.

Eligibility is established upstream. The intended study population is adults after CABG or valve surgery, including patients with both procedures. The existing cohort query used age >18 years, first ICU admission, and ICU stay >24 hours; these filters are not implemented by the ML loader. Apply the finalized study definitions, units and trajectory-data eligibility rules during data preparation.

## Columns and coding

Exactly 15 fields are required: `stay_id`, `Class`, and the 13 candidate predictors. See [data_dictionary.csv](data_dictionary.csv). Other fields are ignored for modelling. Use UTF-8 CSV with or without BOM. The original raw column names are accepted; the harmonized names below are also accepted. Do not include both versions of one field.

| Required harmonized name | Accepted original name | Role / expected coding |
|---|---|---|
| stay_id | stay_id | Unique, nonmissing ICU-stay identifier; never a predictor |
| Class | class; group as a fallback | 1, 2, 3, 4 or `Class 1`–`Class 4`; outcome source |
| Age | age | Numeric, years |
| Gender | gender | F / M in the supplied cohorts |
| Race | race | Asian / Black / Other / White in the supplied cohorts |
| CABG | icd2_cabg | 0/1 or No/Yes |
| Valve | icd2_valve | 0/1 or No/Yes |
| SOFA | sofa | Numeric score |
| CCI | charlson | Numeric Charlson score |
| Hb | lab_in_icu_hemoglobin_first | First ICU hemoglobin, expected g/dL |
| WBC | lab_in_icu_wbc_first | First ICU WBC, expected 10^9/L; candidate only in the supplied run |
| Plt | lab_in_icu_platelet_first | First ICU platelet count, expected 10^9/L |
| Vasopressors | drug_24h_vaso_tag | First-24-hour indicator, 0/1 or No/Yes |
| Mechanical_Ventilation | itvtn_24h_vent_tag | First-24-hour indicator, 0/1 or No/Yes |
| MPP | first_mpp | Initial MPP, expected mmHg |

The supplied MIMIC-IV file used `class`, and the supplied eICU file used `group`. `group` is used as a fallback only if neither `Class` nor `class` exists. Each row must have a valid class and stay identifier. Duplicate identifiers or missing required columns cause the script to stop.

The reader recognizes empty strings, `NA`, `NaN`, and `NULL` as missing. Binary columns recognize yes/true/present and no/false/absent aliases; unrecognized binary entries become missing. The original training pipeline trims but does not otherwise recode Gender or Race. Harmonize these categories upstream to match the study. Numeric conversion follows the preserved original script, so non-numeric text becomes missing; validate units and values before analysis.

Training medians/modes, 1st/99th percentiles, factor levels and scaling parameters are learned only from the training subset and applied to both validation cohorts. Unseen categories become `Unknown`. The numeric summaries use the units in the input and do not perform unit conversion.

## Existing file paths

```r
Sys.setenv(
  MPP_MIMIC_FILE = "D:/authorized-study-data/MIMICIV.csv",
  MPP_EICU_FILE = "D:/authorized-study-data/EICU.csv"
)
source("00_run_all.R", encoding = "UTF-8")
```

These are example paths, not files provided by this repository. Exact replication of the stored split needs the same rows in the same order. Keep identifiers, class labels, local data and individual outputs out of the public repository.
