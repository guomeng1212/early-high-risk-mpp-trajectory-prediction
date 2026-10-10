# Complete local analysis, retaining the original statistical workflow.
# Run from the repository root after preparing data/MIMICIV.csv and data/EICU.csv.
run_mpp_analysis <- function() {
  repo <- normalizePath(Sys.getenv("MPP_REPO_ROOT","."),winslash="/",mustWork=TRUE)
  if (!file.exists(file.path(repo,"DESCRIPTION"))) stop("Run from the repository root, or set MPP_REPO_ROOT.")
  oldwd <- getwd(); on.exit(setwd(oldwd),add=TRUE); setwd(repo)
  output <- normalizePath(Sys.getenv("MPP_ML_ROOT",file.path(repo,"analysis_output")),winslash="/",mustWork=FALSE)
  Sys.setenv(MPP_ML_ROOT=output)
  files <- c("01_preprocessing.R","02_feature_engineering.R","03_mlr3_machine_learning.R","04_SHAP.R","05_replot_DCA_png.R")
  for (f in files) {
    cat("\nRunning ", f, "\n",sep="")
    source(file.path(repo,f),local=new.env(parent=globalenv()),encoding="UTF-8")
  }
  source(file.path(repo,"06_export_deployment.R"),local=new.env(parent=globalenv()),encoding="UTF-8")
  cat("\nAll analyses completed. Local output: ",output,"\n",sep="")
}
run_mpp_analysis()
