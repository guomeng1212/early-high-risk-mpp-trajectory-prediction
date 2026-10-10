# ============================================================
# 01 Preprocessing: MIMIC-IV development + eICU validation
# Outcome: high-risk MPP trajectory (Classes 1 + 3 vs Classes 2 + 4)
# Predictors: Model 3 baseline covariates + initial MPP (13 variables)
# Class defines Target only; it is never a predictor.
# ============================================================
suppressPackageStartupMessages({library(data.table); library(openxlsx)})
set.seed(20260902)

ROOT <- Sys.getenv("MPP_ML_ROOT", file.path(getwd(),"analysis_output"))
DIRS <- file.path(ROOT, c("code","objects","tables","figures","models","logs"))
invisible(lapply(DIRS, dir.create, recursive=TRUE, showWarnings=FALSE))

DATA_DIR <- Sys.getenv("MPP_DATA_DIR", file.path(getwd(), "data"))
PATHS <- c(
  MIMIC_IV=Sys.getenv("MPP_MIMIC_FILE", file.path(DATA_DIR,"MIMICIV.csv")),
  eICU=Sys.getenv("MPP_EICU_FILE", file.path(DATA_DIR,"EICU.csv"))
)

# Rename raw columns using the user's common naming convention.
# Optional columns are renamed when present; only stay_id, Class and VARS are required.
rename_map <- c(
  Class="class", Age="age", Gender="gender", Race="race", ICU_Type="icu_type",
  BMI="bmi", Weight="weight", Height="height", HbA1c="hba1c",
  SOFA="sofa", OASIS="oasis", CCI="charlson", CABG="icd2_cabg", Valve="icd2_valve",
  Hypertension="icd2_hypertension", COPD="icd2_copd", Diabetes="icd2_diabetes",
  HF="icd2_hf", Stroke="icd2_stroke", AF="icd2_af", AMI="icd2_ami", CKD="icd2_ckd",
  Liver_Disease="icd_liver", CABG_Vessel_Count="cabg_vessel_count",
  MAP="vs_24h_map_min", Heart_Rate="vs_24h_heart_rate_max",
  Resp_Rate="vs_24h_resp_rate_max", Temperature="vs_24h_temp_max",
  Hb="lab_in_icu_hemoglobin_first", WBC="lab_in_icu_wbc_first", Plt="lab_in_icu_platelet_first",
  ALT="lab_in_icu_alt_first", AST="lab_in_icu_ast_first", TBil="lab_in_icu_tbil_first",
  Albumin="lab_in_icu_alb_first", INR="lab_in_icu_inr_first", APTT="lab_in_icu_aptt_first",
  Cre="creatinine", PH="lab_in_icu_ph_first", PO2="lab_in_icu_po2_first",
  PCO2="lab_in_icu_pco2_first", HCO3="lab_in_icu_hco3_first", Lactate="lab_in_icu_lactate_first",
  Na="lab_in_icu_na_first", K="lab_in_icu_k_first", Ca="lab_in_icu_ca_first", Cl="lab_in_icu_cl_first",
  eGFR="egfr", First_MAP="first_map", First_CVP="first_cvp", MPP="first_mpp",
  MPP_Time="first_mpp_time", MPP_24h_N="mpp_24h_n",
  Mechanical_Ventilation="itvtn_24h_vent_tag", RRT="itvtn_24h_rrt_tag", Vasopressors="drug_24h_vaso_tag",
  MAKE30="make30", Death30="death30", New_RRT30="new_rrt30", PRD30="prd30",
  Baseline_SCr="baseline_scr", Final_SCr="final_scr", Day30_LOS="day30_los", Day30_Outcome="day30_outcome",
  ICU_LOS="icu_los", ICU_Outcome="icu_outcome", Hos_LOS="hos_los", Hos_Outcome="hos_outcome"
)
# Model 3 excluding Class (12 covariates), plus initial MPP = 13 candidates.
VARS <- c("Age","Gender","Race","CABG","Valve","SOFA","CCI","Hb","WBC","Plt",
          "Vasopressors","Mechanical_Ventilation","MPP")
NUMS <- c("Age","SOFA","CCI","Hb","WBC","Plt","MPP")
BINS <- c("CABG","Valve","Vasopressors","Mechanical_Ventilation")
FACS <- c("Gender","Race",BINS)

norm_binary <- function(x){
  z <- toupper(trimws(as.character(x)))
  out <- ifelse(z %chin% c("1","YES","Y","TRUE","PRESENT"),"Yes",
         ifelse(z %chin% c("0","NO","N","FALSE","ABSENT"),"No",NA_character_))
  factor(out, levels=c("No","Yes"))
}

read_cohort <- function(path, cohort){
  d <- fread(path, na.strings=c("","NA","NaN","NULL"), showProgress=FALSE)
  if(anyDuplicated(names(d))) stop(cohort,": duplicated column names")
  # Current files: MIMIC-IV uses class; eICU uses group. Also accept renamed Class.
  if(!any(c("Class","class") %in% names(d)) && "group" %in% names(d)) setnames(d,"group","class")
  for(nm in names(rename_map)){
    old <- rename_map[[nm]]
    if(old %in% names(d)){
      if(nm %in% names(d)) stop(cohort,": both ",old," and ",nm," are present")
      setnames(d,old,nm)
    }
  }
  need <- c("stay_id","Class",VARS)
  absent <- setdiff(need,names(d)); if(length(absent)) stop(cohort," missing: ",paste(absent,collapse=", "))
  d <- d[, ..need]
  if(anyNA(d$stay_id) || any(!nzchar(trimws(as.character(d$stay_id))))) stop(cohort,": missing stay_id")
  if(anyDuplicated(d$stay_id)) stop(cohort,": duplicated stay_id")
  class_text <- sub("^Class[[:space:]]*","",trimws(as.character(d$Class)),ignore.case=TRUE)
  if(anyNA(class_text) || any(!class_text %chin% as.character(1:4))) stop(cohort,": invalid trajectory class; expected 1-4 or Class 1-Class 4")
  class_num <- as.integer(class_text)
  d[, `:=`(Cohort=cohort, Class=factor(paste("Class",class_num),levels=paste("Class",1:4)),
            Target=factor(ifelse(class_num %in% c(1L,3L),"HighRisk","Other"),levels=c("Other","HighRisk")))]
  for(v in NUMS) set(d,j=v,value=suppressWarnings(as.numeric(d[[v]])))
  for(v in BINS) set(d,j=v,value=norm_binary(d[[v]]))
  for(v in c("Gender","Race")) set(d,j=v,value=factor(trimws(as.character(d[[v]]))))
  d[, c("stay_id","Cohort","Class","Target",VARS), with=FALSE]
}

raw <- lapply(names(PATHS), function(nm) read_cohort(PATHS[[nm]],nm)); names(raw) <- names(PATHS)

# Stratified 70/30 split of MIMIC-IV, fixed once and saved.
idx <- unlist(lapply(levels(raw$MIMIC_IV$Target), function(y){
  ii <- which(raw$MIMIC_IV$Target==y); sample(ii, floor(0.70*length(ii)))
}),use.names=FALSE)
idx <- sort(idx)
split_raw <- list(
  train=copy(raw$MIMIC_IV[idx]), internal=copy(raw$MIMIC_IV[-idx]),
  eicu=copy(raw$eICU)
)

mode1 <- function(x){z<-na.omit(as.character(x)); if(!length(z)) return("Unknown"); names(sort(table(z),decreasing=TRUE))[1]}
prep <- list(
  num_median=setNames(vapply(NUMS,function(v)median(split_raw$train[[v]],na.rm=TRUE),numeric(1)),NUMS),
  num_q01=setNames(vapply(NUMS,function(v)quantile(split_raw$train[[v]],.01,na.rm=TRUE,type=7),numeric(1)),NUMS),
  num_q99=setNames(vapply(NUMS,function(v)quantile(split_raw$train[[v]],.99,na.rm=TRUE,type=7),numeric(1)),NUMS),
  fac_mode=setNames(vapply(FACS,function(v)mode1(split_raw$train[[v]]),character(1)),FACS),
  fac_levels=lapply(FACS,function(v){z<-unique(c(as.character(split_raw$train[[v]]),"Unknown")); sort(z[!is.na(z)&nzchar(z)])})
)
names(prep$fac_levels) <- FACS

clean_one <- function(d, learn_scale=FALSE, scale_par=NULL){
  d <- copy(d)
  for(v in NUMS){
    x<-d[[v]]; x[is.na(x)]<-prep$num_median[[v]]
    x<-pmin(pmax(x,prep$num_q01[[v]]),prep$num_q99[[v]]); set(d,j=v,value=x)
  }
  for(v in FACS){
    x<-as.character(d[[v]]); x[is.na(x)|!nzchar(x)]<-prep$fac_mode[[v]]
    x[!x %in% prep$fac_levels[[v]]]<-"Unknown"; set(d,j=v,value=factor(x,levels=prep$fac_levels[[v]]))
  }
  mm <- model.matrix(~.-1, data=as.data.frame(d[,..VARS]))
  if(learn_scale){
    center<-colMeans(mm); scale<-apply(mm,2,sd); scale[!is.finite(scale)|scale==0]<-1
    scale_par<-list(center=center,scale=scale,features=colnames(mm))
  } else {
    add<-setdiff(scale_par$features,colnames(mm)); if(length(add)) mm<-cbind(mm,matrix(0,nrow(mm),length(add),dimnames=list(NULL,add)))
    mm<-mm[,scale_par$features,drop=FALSE]
  }
  mm<-sweep(sweep(mm,2,scale_par$center,"-"),2,scale_par$scale,"/")
  list(x=mm, y=d$Target, id=d$stay_id, class=d$Class, scale=scale_par)
}

ztrain <- clean_one(split_raw$train,TRUE); prep$scale <- ztrain$scale
processed <- list(train=ztrain)
for(nm in c("internal","eicu")) processed[[nm]] <- clean_one(split_raw[[nm]],FALSE,prep$scale)

cohort_summary <- rbindlist(lapply(names(split_raw),function(nm){
  d<-split_raw[[nm]]; data.table(Dataset=nm,N=nrow(d),HighRisk=sum(d$Target=="HighRisk"),Prevalence=mean(d$Target=="HighRisk"))
}))
missing_summary <- rbindlist(lapply(names(raw),function(nm){
  d<-raw[[nm]]; data.table(Cohort=nm,Variable=VARS,Missing_N=vapply(VARS,function(v)sum(is.na(d[[v]])),integer(1)),
                          Missing_pct=100*vapply(VARS,function(v)mean(is.na(d[[v]])),numeric(1)))
}))
split_ids <- rbindlist(lapply(names(split_raw),function(nm)data.table(Dataset=nm,stay_id=split_raw[[nm]]$stay_id,Class=split_raw[[nm]]$Class,Target=split_raw[[nm]]$Target)))

obj <- list(processed=processed, raw=split_raw, prep=prep, variables=VARS,
            numeric=NUMS, categorical=FACS, paths=PATHS, root=ROOT,
            outcome_definition="Classes 1 + 3 (high-risk MPP trajectory) vs Classes 2 + 4")
saveRDS(obj,file.path(ROOT,"objects","step1_preprocessed.rds"))
write.xlsx(list(Cohort_summary=cohort_summary,Missingness=missing_summary,Split_IDs=split_ids),
           file.path(ROOT,"tables","01_preprocessing_QC.xlsx"),overwrite=TRUE)
fwrite(cohort_summary,file.path(ROOT,"tables","01_cohort_summary.csv"))
cat("Step 1 complete. Output:",ROOT,"\n")
print(cohort_summary)
