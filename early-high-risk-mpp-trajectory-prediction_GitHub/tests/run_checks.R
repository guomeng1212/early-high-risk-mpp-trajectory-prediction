# Syntax checks and calculator checks; no cohort data or model training is required.
# Optional: set MPP_DEPLOYMENT_MODEL to an authorized local model to exercise prediction.
repo <- normalizePath(Sys.getenv("MPP_REPO_ROOT","."),winslash="/",mustWork=TRUE)
if(!file.exists(file.path(repo,"DESCRIPTION"))) stop("Run from the repository root.")
files <- c(list.files(repo,pattern="\\.R$",full.names=TRUE),
           list.files(file.path(repo,"R"),pattern="\\.R$",full.names=TRUE),
           list.files(file.path(repo,"tests"),pattern="\\.R$",full.names=TRUE))
for(f in files) parse(file=f,encoding="UTF-8")
cat("PASS: ",length(files)," R files parse.\n",sep="")

source(file.path(repo,"R","predict_mpp.R"),encoding="UTF-8")
stopifnot(identical(mpp_clip(c(0,.5,1)),c(1e-6,.5,1-1e-6)))
model_path <- Sys.getenv("MPP_DEPLOYMENT_MODEL","")
if(!nzchar(model_path)) {
  cat("SKIP: local model checks (set MPP_DEPLOYMENT_MODEL to enable).\n")
} else {
  z <- mpp_load_model(model_path)
  stopifnot(setequal(unique(vapply(z$selected,mpp_parent,character(1),vars=z$vars)),setdiff(z$vars,"WBC")))
  # Synthetic profiles around the stored training summary values; no patient rows.
  profile <- mpp_default_input(z)
  profile$CABG <- "Yes"
  baseline <- mpp_predict(profile,z,explain=TRUE)
  stopifnot(length(baseline$probability)==1L,is.finite(baseline$probability),
            baseline$probability>0,baseline$probability<1,
            ncol(baseline$shap)==length(z$selected),
            abs(sum(baseline$shap)+baseline$shap_baseline-baseline$raw_margin)<1e-4)
  reordered <- mpp_predict(profile[,rev(names(profile)),drop=FALSE],z)
  omitted_wbc <- mpp_predict(profile[,setdiff(names(profile),"WBC"),drop=FALSE],z)
  extreme_wbc <- profile; extreme_wbc$WBC <- 1e9
  stopifnot(identical(baseline$probability,reordered$probability),
            identical(baseline$probability,omitted_wbc$probability),
            identical(baseline$probability,mpp_predict(extreme_wbc,z)$probability))
  missing <- profile; missing$MPP <- NA_real_
  with_median <- profile; with_median$MPP <- z$prep$num_median[["MPP"]]
  stopifnot(identical(mpp_predict(missing,z)$probability,mpp_predict(with_median,z)$probability))
  extreme <- profile; extreme$MPP <- 1e9
  at_boundary <- profile; at_boundary$MPP <- z$prep$num_q99[["MPP"]]
  stopifnot(identical(mpp_predict(extreme,z)$probability,mpp_predict(at_boundary,z)$probability))
  binary_alias <- profile; binary_alias$CABG <- 1
  stopifnot(identical(mpp_predict(binary_alias,z)$probability,baseline$probability))
  invalid_binary <- profile; invalid_binary$CABG <- "invalid"
  mode_binary <- profile; mode_binary$CABG <- z$prep$fac_mode[["CABG"]]
  stopifnot(identical(mpp_predict(invalid_binary,z)$probability,mpp_predict(mode_binary,z)$probability))
  unknown <- profile; unknown$Race <- "Previously unseen category"
  unknown_result <- mpp_predict(unknown,z)
  stopifnot(as.character(unknown_result$prepared$cleaned$Race)=="Unknown")
  old_options <- options(contrasts=c("contr.sum","contr.poly"))
  tryCatch(stopifnot(identical(mpp_predict(profile,z)$probability,baseline$probability)),
           finally=options(old_options))
  invalid <- profile; invalid$MPP <- Inf
  stopifnot(inherits(try(mpp_predict(invalid,z),silent=TRUE),"try-error"))
  batch <- mpp_predict(rbind(profile,with_median,at_boundary),z,explain=TRUE)
  stopifnot(length(batch$probability)==3L,nrow(batch$shap)==3L,
            max(abs(rowSums(batch$shap)+batch$shap_baseline-batch$raw_margin))<1e-4)
  cat("PASS: local model feature order, calibration, missing values, winsorization, categorical handling, batch prediction and exact TreeSHAP.\n")
}
cat("Checks completed. These checks do not refit the manuscript analysis.\n")
