# Export a minimal model for authorized LOCAL use. Derived models are not GitHub artifacts.
# Run after steps 01–05. Override MPP_DEPLOYMENT_OUT to choose a separate local destination.
export_mpp_deployment <- function(analysis_root,out_file) {
  pkgs <- c("mlr3","mlr3learners","xgboost")
  miss <- pkgs[!vapply(pkgs,requireNamespace,logical(1),quietly=TRUE)]
  if(length(miss)) stop("Missing packages: ",paste(miss,collapse=", "))
  s1 <- readRDS(file.path(analysis_root,"objects","step1_preprocessed.rds"))
  s2 <- readRDS(file.path(analysis_root,"objects","step2_lasso.rds"))
  learner <- readRDS(file.path(analysis_root,"models","final_xgboost.rds"))
  calibrator <- readRDS(file.path(analysis_root,"models","platt_xgboost.rds"))
  booster <- learner$model
  if(!inherits(booster,"xgb.Booster")) stop("Expected an XGBoost booster in the fitted learner.")
  # RDS stores an XGBoost memory snapshot, which must be restored before a portable model export.
  live_booster <- xgboost::xgb.Booster.complete(booster)
  cf <- coef(calibrator)
  calibration <- c(intercept=unname(cf[["(Intercept)"]]),slope=if("lp"%in%names(cf))unname(cf[["lp"]])else 0)
  cuts <- read.csv(file.path(analysis_root,"tables","03_classification_thresholds.csv"),fileEncoding="UTF-8-BOM")
  threshold <- cuts$Threshold[cuts$Model=="xgboost"]
  if(length(threshold)!=1L || any(!is.finite(calibration))) stop("Calibration or threshold is invalid.")
  if(!setequal(booster$feature_names,s2$selected)) stop("Selected features differ from booster features.")
  display <- c(Age="Age",Gender="Sex",Race="Race",CABG="CABG",Valve="Valve surgery",SOFA="SOFA score",CCI="Charlson index",
    Hb="Hemoglobin",WBC="White blood cell count",Plt="Platelet count",Vasopressors="Vasopressor use",
    Mechanical_Ventilation="Mechanical ventilation",MPP="Initial MPP")
  payload <- list(schema_version=1L,booster_raw=xgboost::xgb.save.raw(live_booster,raw_format="ubj"),
    prep=s1$prep[c("num_median","num_q01","num_q99","fac_mode","fac_levels","scale")],
    vars=s1$variables,numeric=s1$numeric,categorical=s1$categorical,selected=booster$feature_names,
    calibration=calibration,threshold=threshold,display=display,
    metadata=list(model="XGBoost",outcome="Classes 1 + 3 vs Classes 2 + 4 of predefined MPP trajectories",
      population="Adult ICU patients after CABG and/or valve surgery",lambda=s2$lambda,selection_rule="lambda.min; abs(coefficient) > 1e-8",
      xgboost_version=as.character(packageVersion("xgboost")),r_version=as.character(getRversion()),
      threshold_source="Maximum Youden index from calibrated training OOF predictions",
      access="Local/controlled use. MIMIC-derived model; do not upload to a public GitHub repository."))
  # Atomic values and lists only: no Learner, glm, formula, environment, patient frame or prediction object.
  check_fields <- function(x,field="payload") {
    if(is.environment(x)||is.function(x)||inherits(x,c("Learner","glm","formula","data.frame"))) stop("Unexpected object in ",field)
    if(is.list(x)) for(nm in names(x)) check_fields(x[[nm]],paste0(field,"$",nm))
  }
  check_fields(payload)
  dir.create(dirname(out_file),recursive=TRUE,showWarnings=FALSE)
  saveRDS(payload,out_file,compress="xz")
  cat("Local deployment model exported: ",out_file,"\n",sep="")
  invisible(out_file)
}
if(Sys.getenv("MPP_EXPORT_DEFINE_ONLY","0")!="1") {
  analysis_root <- Sys.getenv("MPP_ML_ROOT",file.path(getwd(),"analysis_output"))
  out_file <- Sys.getenv("MPP_DEPLOYMENT_OUT",file.path(analysis_root,"models","MPP_xgboost_deployment.rds"))
  export_mpp_deployment(analysis_root,out_file)
}
