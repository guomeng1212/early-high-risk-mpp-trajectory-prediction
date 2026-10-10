# Small prediction interface; contains no training data and performs no automatic file writes.
mpp_clip <- function(p) pmin(pmax(as.numeric(p),1e-6),1-1e-6)

mpp_load_model <- function(path) {
  if (!requireNamespace("xgboost",quietly=TRUE)) stop("Install the recorded XGBoost version with 00_setup.R.")
  if (!file.exists(path)) stop("Local deployment model not found. See models/README.md and set MPP_DEPLOYMENT_MODEL.")
  z <- readRDS(path)
  required <- c("schema_version","booster_raw","prep","vars","numeric","categorical","selected","calibration","threshold","display","metadata")
  if (!is.list(z) || !all(required %in% names(z)) || !identical(z$schema_version,1L)) stop("Unsupported MPP deployment file.")
  if (!is.raw(z$booster_raw) || length(z$calibration)!=2L || any(!is.finite(z$calibration))) stop("Invalid deployment parameters.")
  if (length(z$threshold)!=1L || !is.finite(z$threshold) || z$threshold<=0 || z$threshold>=1) stop("Invalid probability threshold.")
  z$booster <- xgboost::xgb.load.raw(z$booster_raw,as_booster=TRUE)
  if (is.null(z$booster$feature_names)) z$booster$feature_names <- z$selected
  if (!identical(z$booster$feature_names,z$selected)) stop("Booster feature order does not match the export.")
  z
}

mpp_parent <- function(feature,vars) {
  hit <- vars[vapply(vars,function(v)startsWith(feature,v),logical(1))]
  if (!length(hit)) return(feature)
  hit[which.max(nchar(hit))]
}

mpp_feature_label <- function(feature,z) {
  parent <- mpp_parent(feature,z$vars); suffix <- substring(feature,nchar(parent)+1)
  label <- if (parent %in% names(z$display)) z$display[[parent]] else parent
  if (parent=="Gender") suffix <- switch(suffix,F="Female",M="Male",suffix)
  paste0(label,if(nzchar(suffix))paste0(": ",suffix)else"")
}

mpp_default_input <- function(z) {
  values <- setNames(vector("list",length(z$vars)),z$vars)
  for (v in z$numeric) values[[v]] <- unname(z$prep$num_median[[v]])
  for (v in z$categorical) values[[v]] <- unname(z$prep$fac_mode[[v]])
  as.data.frame(values,stringsAsFactors=FALSE,check.names=FALSE)
}

mpp_prepare_input <- function(newdata,z) {
  d <- as.data.frame(newdata,stringsAsFactors=FALSE,check.names=FALSE)
  if (!nrow(d)) stop("Supply at least one input row.")
  # The stored design includes all 13 candidates. Unselected WBC can be omitted.
  for (v in setdiff(z$vars,names(d))) d[[v]] <- NA
  d <- d[,z$vars,drop=FALSE]
  handled <- list()
  add_note <- function(v,kind,idx) {
    if(length(idx)) handled[[length(handled)+1L]] <<- data.frame(Row=idx,Variable=v,Handling=kind,stringsAsFactors=FALSE)
  }
  for (v in z$numeric) {
    original <- as.character(d[[v]])
    missing <- is.na(original)|trimws(original)%in%c("","NA","NaN","NULL")
    x <- suppressWarnings(as.numeric(original)); x[missing] <- NA_real_
    if(any(!missing & !is.finite(x))) stop("Non-numeric or infinite value in ",v)
    add_note(v,"Training median imputation",which(is.na(x)))
    x[is.na(x)] <- z$prep$num_median[[v]]
    outside <- which(x<z$prep$num_q01[[v]]|x>z$prep$num_q99[[v]])
    add_note(v,"Training 1st/99th percentile winsorization",outside)
    d[[v]] <- pmin(pmax(x,z$prep$num_q01[[v]]),z$prep$num_q99[[v]])
  }
  bins <- intersect(c("CABG","Valve","Vasopressors","Mechanical_Ventilation"),z$categorical)
  for (v in z$categorical) {
    x <- trimws(as.character(d[[v]]))
    if (v %in% bins) {
      upper <- toupper(x)
      x[upper%in%c("1","YES","Y","TRUE","PRESENT")] <- "Yes"
      x[upper%in%c("0","NO","N","FALSE","ABSENT")] <- "No"
      x[!upper%in%c("1","YES","Y","TRUE","PRESENT","0","NO","N","FALSE","ABSENT")] <- NA_character_
    }
    if(v=="Gender") {
      x[toupper(x)%in%c("F","FEMALE")] <- "F"
      x[toupper(x)%in%c("M","MALE")] <- "M"
    }
    missing <- is.na(x)|!nzchar(x)
    add_note(v,"Training mode imputation",which(missing)); x[missing] <- z$prep$fac_mode[[v]]
    unknown <- !x%in%z$prep$fac_levels[[v]]
    add_note(v,"Unseen category encoded as Unknown",which(unknown)); x[unknown] <- "Unknown"
    d[[v]] <- factor(x,levels=z$prep$fac_levels[[v]])
  }
  old <- options(contrasts=c("contr.treatment","contr.poly")); on.exit(options(old),add=TRUE)
  mm <- model.matrix(~.-1,data=d)
  features <- z$prep$scale$features
  extra <- setdiff(features,colnames(mm))
  if(length(extra)) mm <- cbind(mm,matrix(0,nrow(mm),length(extra),dimnames=list(NULL,extra)))
  mm <- mm[,features,drop=FALSE]
  mm <- sweep(sweep(mm,2,z$prep$scale$center,"-"),2,z$prep$scale$scale,"/")
  mm <- mm[,z$selected,drop=FALSE]
  if(any(!is.finite(mm))) stop("Non-finite predictor matrix after preprocessing.")
  list(x=mm,cleaned=d,handling=if(length(handled))do.call(rbind,handled)else data.frame(Row=integer(),Variable=character(),Handling=character()))
}

mpp_predict <- function(newdata,z,explain=FALSE) {
  prepared <- mpp_prepare_input(newdata,z)
  raw <- as.numeric(predict(z$booster,prepared$x))
  probability <- mpp_clip(plogis(z$calibration[["intercept"]]+z$calibration[["slope"]]*qlogis(mpp_clip(raw))))
  answer <- list(raw_probability=raw,probability=probability,threshold=z$threshold,
    group=ifelse(probability>=z$threshold,"High-risk (Classes 1 + 3)","Other (Classes 2 + 4)"),prepared=prepared)
  if(explain) {
    shap <- as.matrix(predict(z$booster,prepared$x,predcontrib=TRUE,approxcontrib=FALSE))
    bias <- grep("BIAS",colnames(shap),ignore.case=TRUE)
    if(!length(bias)) bias <- ncol(shap)
    margin <- as.numeric(predict(z$booster,prepared$x,outputmargin=TRUE))
    if(max(abs(rowSums(shap)-margin))>1e-4) stop("SHAP additivity check failed.")
    answer$shap_baseline <- as.numeric(shap[,bias])
    answer$shap <- shap[,-bias,drop=FALSE][,z$selected,drop=FALSE]
    answer$raw_margin <- margin
  }
  answer
}
