# ============================================================
# 04 Exact TreeSHAP for XGBoost on MIMIC-IV internal validation
# Outcome: high-risk MPP trajectory (Classes 1 + 3 vs Classes 2 + 4)
# ============================================================
pkgs<-c("data.table","ggplot2","ragg","xgboost","scales","openxlsx")
miss<-pkgs[!vapply(pkgs,requireNamespace,logical(1),quietly=TRUE)];if(length(miss))stop("Missing R packages: ",paste(miss,collapse=", "))
suppressPackageStartupMessages({library(data.table);library(ggplot2)});set.seed(20260902)
ROOT<-Sys.getenv("MPP_ML_ROOT",file.path(getwd(),"analysis_output"))
OBJ<-file.path(ROOT,"objects");TAB<-file.path(ROOT,"tables");FIG<-file.path(ROOT,"figures")
z<-readRDS(file.path(OBJ,"step3_models.rds"));s2<-z$step2

extract_booster<-function(x){
  if(inherits(x,"xgb.Booster"))return(x)
  if(inherits(x,"Learner"))return(extract_booster(x$model))
  if(is.list(x))for(v in x){ans<-try(extract_booster(v),silent=TRUE);if(!inherits(ans,"try-error"))return(ans)}
  stop("xgb.Booster not found")
}
booster<-extract_booster(z$models$xgboost)
di<-s2$preprocessed$processed$internal;x<-as.matrix(di$x);ids<-di$id
if(nrow(x)>1000){ii<-sort(sample(seq_len(nrow(x)),1000));x<-x[ii,,drop=FALSE];ids<-ids[ii]}
if(!setequal(booster$feature_names,colnames(x)))stop("XGBoost feature names do not match internal matrix")
x<-x[,booster$feature_names,drop=FALSE]
sh<-as.matrix(predict(booster,x,predcontrib=TRUE,approxcontrib=FALSE))
bias<-grep("BIAS",colnames(sh),ignore.case=TRUE);if(!length(bias))bias<-ncol(sh)
sh<-sh[,-bias,drop=FALSE];sh<-sh[,colnames(x),drop=FALSE]

display<-c(Age="Age",Gender="Gender",Race="Race",CABG="CABG",Valve="Valve",
  SOFA="SOFA",CCI="CCI",Hb="Hb",WBC="WBC",Plt="Plt",
  Vasopressors="Vasopressors",Mechanical_Ventilation="Mechanical ventilation",MPP="Initial MPP")
parent<-function(f){hit<-names(display)[vapply(names(display),function(v)startsWith(f,v),logical(1))];if(!length(hit))f else hit[which.max(nchar(hit))]}
label<-function(f){p<-parent(f);suffix<-sub(paste0("^",p),"",f);paste0(if(p%in%names(display))display[[p]] else p,if(nzchar(suffix))paste0(": ",gsub("_"," ",suffix))else"")}
imp<-data.table(Feature=colnames(sh),MeanAbsSHAP=colMeans(abs(sh)))
imp[,`:=`(Parent=vapply(Feature,parent,character(1)),Label=vapply(Feature,label,character(1)))];setorder(imp,-MeanAbsSHAP);imp[,Rank:=.I]
top<-head(imp$Feature,15);sv<-as.data.table(sh[,top,drop=FALSE]);sv[,Row:=.I];sv<-melt(sv,id.vars="Row",variable.name="Feature",value.name="SHAP")
xv<-as.data.table(x[,top,drop=FALSE]);xv[,Row:=.I];xv<-melt(xv,id.vars="Row",variable.name="Feature",value.name="FeatureValue")
long<-merge(sv,xv,by=c("Row","Feature"),sort=FALSE);long[,`:=`(ID=ids[Row],Label=vapply(as.character(Feature),label,character(1)))]
long[,FeatureColour:={lo<-quantile(FeatureValue,.05,na.rm=TRUE);hi<-quantile(FeatureValue,.95,na.rm=TRUE);if(is.finite(lo)&&is.finite(hi)&&hi>lo)pmin(pmax((FeatureValue-lo)/(hi-lo),0),1) else rep(.5,.N)},by=Feature]
ord<-rev(imp[Feature%in%top]$Label);long[,Label:=factor(Label,levels=ord)]
fwrite(imp,file.path(TAB,"04_XGBoost_SHAP_importance.csv"),bom=TRUE);fwrite(long,file.path(TAB,"04_XGBoost_SHAP_values_internal.csv"),bom=TRUE)

theme_p<-theme_bw(base_size=11,base_family="Times New Roman")+theme(text=element_text(family="Times New Roman",colour="black"),plot.title=element_text(size=15,face="bold",hjust=.5),plot.subtitle=element_text(size=12,hjust=.5),panel.grid.minor=element_blank(),plot.margin=margin(8,10,8,8))
bar<-imp[Feature%in%top];bar[,Label:=factor(Label,levels=rev(Label))]
p1<-ggplot(bar,aes(MeanAbsSHAP,Label))+geom_col(fill="#D55E00",colour="#A84300",linewidth=.18,width=.72)+labs(x="Mean |SHAP value|",y=NULL,title="XGBoost feature importance",subtitle="MIMIC-IV internal validation")+theme_p
p2<-ggplot(long,aes(SHAP,Label,colour=FeatureColour))+geom_vline(xintercept=0,colour="grey45",linewidth=.5)+geom_point(position=position_jitter(width=0,height=.18,seed=20260902),size=1.3,alpha=.92)+scale_colour_gradient(low="#0057D9",high="#FF6A00",limits=c(0,1),breaks=c(0,1),labels=c("Low","High"),oob=scales::squish)+labs(x="SHAP value (impact on model log-odds)",y=NULL,colour="Feature value",title="XGBoost SHAP summary",subtitle="MIMIC-IV internal validation")+theme_p+theme(legend.position="right")
save_png<-function(p,name,w,h){ragg::agg_png(file.path(FIG,paste0(name,".png")),w,h,units="in",res=600,background="white");print(p);dev.off()}
save_png(p1,"04_SHAP_importance",8.5,7);save_png(p2,"04_SHAP_beeswarm",10,7.5)
openxlsx::write.xlsx(list(SHAP_importance=imp,SHAP_values=long),file.path(TAB,"04_SHAP_results.xlsx"),overwrite=TRUE)
cat("Step 4 complete.\n");print(head(imp,15))
