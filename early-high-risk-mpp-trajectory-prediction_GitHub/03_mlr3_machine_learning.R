# ============================================================
# 03 mlr3 machine learning
# 10-fold CV, random-search tuning, OOF Platt calibration,
# MIMIC-IV internal validation and fixed eICU validation
# Outcome: high-risk MPP trajectory (Classes 1 + 3 vs Classes 2 + 4)
# Set MPP_ML_FAST=1 only for pipeline testing; formal analysis uses 0.
# ============================================================
pkgs <- c("data.table","mlr3","mlr3learners","mlr3tuning","paradox","bbotk","pROC",
          "ggplot2","ragg","scales","xgboost","ranger","e1071","kknn","future",
          "future.apply","parallelly","openxlsx")
miss <- pkgs[!vapply(pkgs,requireNamespace,logical(1),quietly=TRUE)]
if(length(miss)) stop("Missing R packages: ",paste(miss,collapse=", "))
suppressPackageStartupMessages({library(data.table);library(mlr3);library(mlr3learners);
  library(mlr3tuning);library(paradox);library(bbotk);library(ggplot2)})
set.seed(20260902)

FAST <- identical(Sys.getenv("MPP_ML_FAST","0"),"1")
CV_FOLDS <- if(FAST) 3L else 10L
TUNE_EVALS <- if(FAST) c(xgboost=5L,ranger=5L,svm=5L,kknn=5L) else c(xgboost=200L,ranger=150L,svm=150L,kknn=100L)
BOOT_B <- if(FAST) 20L else 1000L
avail <- as.integer(future::availableCores())
uw <- suppressWarnings(as.integer(Sys.getenv("MPP_ML_WORKERS","0")))
N_WORKERS <- if(!is.na(uw)&&uw>0) min(uw,CV_FOLDS) else min(CV_FOLDS,max(1L,avail-1L))
options(future.globals.maxSize=8*1024^3); future::plan(future::multisession,workers=N_WORKERS)

ROOT <- Sys.getenv("MPP_ML_ROOT",file.path(getwd(),"analysis_output"))
OBJ<-file.path(ROOT,"objects"); TAB<-file.path(ROOT,"tables"); FIG<-file.path(ROOT,"figures")
PRED<-file.path(ROOT,"predictions"); MOD<-file.path(ROOT,"models")
for(d in c(OBJ,TAB,FIG,PRED,MOD)) dir.create(d,recursive=TRUE,showWarnings=FALSE)
cat(sprintf("Mode=%s | CV=%d | workers=%d | tuning XGB/RF/SVM/kNN=%d/%d/%d/%d\n",
  ifelse(FAST,"FAST test","Formal"),CV_FOLDS,N_WORKERS,TUNE_EVALS[1],TUNE_EVALS[2],TUNE_EVALS[3],TUNE_EVALS[4]))

z <- readRDS(file.path(OBJ,"step2_lasso.rds")); ds <- z$preprocessed$processed
labels <- c(log_reg="Logistic regression",xgboost="XGBoost",ranger="Random forest",svm="SVM-RBF",kknn="k-NN")
cols <- c("Logistic regression"="#0072B2","XGBoost"="#D55E00","Random forest"="#009E73","SVM-RBF"="#CC79A7","k-NN"="#E69F00")
theme_p <- theme_bw(base_size=11,base_family="Times New Roman")+theme(text=element_text(family="Times New Roman",colour="black"),plot.title=element_text(face="bold",hjust=.5),legend.position="bottom",strip.text=element_text(face="bold"),panel.grid.minor=element_blank())
save_fig <- function(p,name,w=13.5,h=5.5){
  ragg::agg_png(file.path(FIG,paste0(name,".png")),w,h,units="in",res=600,background="white"); print(p); dev.off()
}
write_dt <- function(x,file){d<-as.data.table(x); lc<-names(d)[vapply(d,is.list,logical(1))]; for(v in lc)d[,(v):=vapply(get(v),function(a)paste(unlist(a),collapse=";"),character(1))]; fwrite(d,file,bom=TRUE)}
make_task <- function(x,y,id){d<-as.data.frame(x);d$Target<-factor(y,c("Other","HighRisk"));TaskClassif$new(id,d,target="Target",positive="HighRisk")}
make_folds <- function(y,k,seed=20260902){set.seed(seed);f<-integer(length(y));for(g in levels(y)){ii<-sample(which(y==g));f[ii]<-rep(seq_len(k),length.out=length(ii))};f}
extract_prob <- function(pr){d<-as.data.table(pr);pc<-grep("^prob\\.HighRisk$|^prob_HighRisk$",names(d),value=TRUE);if(!length(pc))pc<-grep("HighRisk",names(d),value=TRUE)[1];data.table(row_id=d$row_ids,p=as.numeric(d[[pc[1]]]))}
clip <- function(p)pmin(pmax(as.numeric(p),1e-6),1-1e-6)
fit_platt <- function(y,p){lp<-qlogis(clip(p));yy<-as.integer(y=="HighRisk");fit<-suppressWarnings(glm(yy~lp,family=binomial()));if(any(!is.finite(coef(fit))))fit<-glm(yy~1,family=binomial());fit}
apply_platt <- function(fit,p){lp<-qlogis(clip(p));clip(predict(fit,newdata=data.frame(lp=lp),type="response"))}
best_cut <- function(y,p)as.numeric(pROC::coords(pROC::roc(y,p,levels=c("Other","HighRisk"),direction="<",quiet=TRUE),"best",best.method="youden",ret="threshold",transpose=FALSE)[1])

specs <- function(p){n<-TUNE_EVALS;list(
  log_reg=list(lrn("classif.log_reg",predict_type="prob",maxit=500),NULL,0),
  xgboost=list(lrn("classif.xgboost",predict_type="prob",nthread=1,objective="binary:logistic",eval_metric="aucpr",verbose=0),
    ps(nrounds=p_int(100,1200),eta=p_dbl(.005,.30,logscale=TRUE),max_depth=p_int(2,8),min_child_weight=p_dbl(1,20,logscale=TRUE),subsample=p_dbl(.50,1),colsample_bytree=p_dbl(.50,1),gamma=p_dbl(1e-5,5,logscale=TRUE),lambda=p_dbl(1e-4,10,logscale=TRUE),alpha=p_dbl(1e-4,10,logscale=TRUE)),n["xgboost"]),
  ranger=list(lrn("classif.ranger",predict_type="prob",num.trees=1500,importance="permutation",num.threads=1,seed=20260902),
    ps(mtry.ratio=p_dbl(max(1/p,.05),1),min.node.size=p_int(1,40),sample.fraction=p_dbl(.50,1),splitrule=p_fct(c("gini","extratrees"))),n["ranger"]),
  svm=list(lrn("classif.svm",predict_type="prob",kernel="radial",type="C-classification",scale=FALSE,cachesize=2000),
    ps(cost=p_dbl(.001,1000,logscale=TRUE),gamma=p_dbl(1e-5,10,logscale=TRUE)),n["svm"]),
  kknn=list(lrn("classif.kknn",predict_type="prob",scale=FALSE,store_model=TRUE),
    ps(k=p_int(3,101),distance=p_dbl(1,2),kernel=p_fct(c("optimal","triangular","gaussian"))),n["kknn"]))}

tune_one <- function(s,task,fold,id){
  learner<-s[[1]]$clone(deep=TRUE); if(is.null(s[[2]]))return(learner)
  rs<-rsmp("custom_cv");rs$instantiate(task,f=factor(fold));set.seed(20260902+match(id,names(labels)))
  ins<-mlr3tuning::tune(tnr("random_search",batch_size=N_WORKERS),task,learner,rs,msr("classif.prauc"),
                        term_evals=as.integer(s[[3]]),search_space=s[[2]],store_benchmark_result=FALSE)
  vals<-learner$param_set$values;vals[names(ins$result_learner_param_vals)]<-ins$result_learner_param_vals;learner$param_set$values<-vals
  write_dt(ins$archive$data,file.path(TAB,paste0("03_tuning_",id,".csv")));learner
}

y<-factor(ds$train$y,levels=c("Other","HighRisk"));task<-make_task(ds$train$x,y,"MIMIC_train")
fold<-make_folds(y,CV_FOLDS);sp<-specs(ncol(ds$train$x));models<-calibrators<-cuts<-list();predlist<-paramlog<-list()
sets<-list("MIMIC-IV internal validation"=ds$internal,"eICU external validation"=ds$eicu)

for(id in names(sp)){
  cat("Training: ",labels[id],"\n",sep=""); learner<-tune_one(sp[[id]],task,fold,id)
  rs<-rsmp("custom_cv");rs$instantiate(task,f=factor(fold));set.seed(20261000+match(id,names(sp)))
  rr<-resample(task,learner$clone(deep=TRUE),rs,store_models=FALSE);oof<-extract_prob(rr$prediction());setorder(oof,row_id)
  cal<-fit_platt(y[oof$row_id],oof$p);cp<-apply_platt(cal,oof$p);cut<-best_cut(y[oof$row_id],cp)
  final<-learner$clone(deep=TRUE);if(id=="xgboost")final$param_set$values$nthread<-N_WORKERS;if(id=="ranger")final$param_set$values$num.threads<-N_WORKERS
  set.seed(20262000+match(id,names(sp)));final$train(task)
  pv<-final$param_set$values;paramlog[[id]]<-data.table(Model=id,ModelLabel=labels[id],Parameters=paste(names(pv),vapply(pv,function(v)paste(v,collapse="|"),character(1)),sep="=",collapse="; "))
  models[[id]]<-final;calibrators[[id]]<-cal;cuts[[id]]<-cut
  predlist[[paste("OOF",id)]]<-data.table(ID=ds$train$id[oof$row_id],Cohort="MIMIC-IV training OOF",Model=id,Truth=y[oof$row_id],Raw=oof$p,Probability=cp,Threshold=cut)
  for(nm in names(sets)){s<-sets[[nm]];rawp<-extract_prob(final$predict(make_task(s$x,s$y,paste0("p_",id))))$p;predlist[[paste(nm,id)]]<-data.table(ID=s$id,Cohort=nm,Model=id,Truth=s$y,Raw=rawp,Probability=apply_platt(cal,rawp),Threshold=cut)}
  saveRDS(final,file.path(MOD,paste0("final_",id,".rds")),compress="xz");saveRDS(cal,file.path(MOD,paste0("platt_",id,".rds")),compress="xz")
}

pred<-rbindlist(predlist);pred[,ModelLabel:=factor(labels[Model],levels=unname(labels))]
fwrite(pred,file.path(PRED,"03_all_predictions.csv"),bom=TRUE)
fwrite(data.table(Model=names(cuts),ModelLabel=labels[names(cuts)],Threshold=unlist(cuts)),file.path(TAB,"03_classification_thresholds.csv"),bom=TRUE)
fwrite(rbindlist(paramlog),file.path(TAB,"03_best_hyperparameters.csv"),bom=TRUE)
cfg<-data.table(Setting=c("Mode","CV folds","Workers","Tuning metric","XGBoost evaluations","RF evaluations","SVM evaluations","kNN evaluations","Bootstrap repetitions","Seed"),Value=c(ifelse(FAST,"FAST test","Formal"),CV_FOLDS,N_WORKERS,"PR-AUC",TUNE_EVALS,BOOT_B,20260902));fwrite(cfg,file.path(TAB,"03_machine_learning_settings.csv"),bom=TRUE)

truth01<-function(y)as.integer(as.character(y)=="HighRisk")
ap<-function(y,p){y<-truth01(y);o<-order(p,decreasing=TRUE);y<-y[o];if(!sum(y))return(NA_real_);sum((cumsum(y)/seq_along(y))*y)/sum(y)}
score<-function(y,p,cut){yy<-truth01(y);cl<-p>=cut;tp<-sum(cl&yy==1);tn<-sum(!cl&yy==0);fp<-sum(cl&yy==0);fn<-sum(!cl&yy==1);c(AUROC=as.numeric(pROC::auc(pROC::roc(y,p,levels=c("Other","HighRisk"),direction="<",quiet=TRUE))),AUPRC=ap(y,p),Brier=mean((p-yy)^2),Sensitivity=tp/(tp+fn),Specificity=tn/(tn+fp),PPV=tp/(tp+fp),NPV=tn/(tn+fn),F1=2*tp/(2*tp+fp+fn))}
boot_ci<-function(y,p,cut,B,seed){set.seed(seed);yy<-truth01(y);pos<-which(yy==1);neg<-which(yy==0);replicate(B,{ii<-c(sample(pos,length(pos),TRUE),sample(neg,length(neg),TRUE));score(y[ii],p[ii],cut)})}

groups<-unique(pred[,.(Cohort,Model,ModelLabel)]);met<-ci<-calstat<-vector("list",nrow(groups))
for(i in seq_len(nrow(groups))){g<-groups[i];d<-pred[Cohort==g$Cohort&Model==g$Model];sc<-score(d$Truth,d$Probability,d$Threshold[1]);met[[i]]<-cbind(g,as.data.table(as.list(sc)),N=nrow(d),Events=sum(d$Truth=="HighRisk"));bt<-boot_ci(d$Truth,d$Probability,d$Threshold[1],BOOT_B,20260902+i);ci[[i]]<-rbindlist(lapply(rownames(bt)[1:3],function(v)data.table(Cohort=g$Cohort,Model=g$Model,Metric=v,Estimate=sc[v],Lower95=quantile(bt[v,],.025,na.rm=TRUE),Upper95=quantile(bt[v,],.975,na.rm=TRUE))));yy<-truth01(d$Truth);lp<-qlogis(clip(d$Probability));cf<-coef(glm(yy~lp,family=binomial()));calstat[[i]]<-cbind(g,data.table(Prevalence=mean(yy),MeanPredicted=mean(d$Probability),CalibrationIntercept=cf[1],CalibrationSlope=cf[2]))}
met<-rbindlist(met);ci<-rbindlist(ci);calstat<-rbindlist(calstat)
fwrite(met,file.path(TAB,"03_performance_metrics.csv"),bom=TRUE);fwrite(ci,file.path(TAB,"03_performance_bootstrap_ci.csv"),bom=TRUE);fwrite(calstat,file.path(TAB,"03_calibration_statistics.csv"),bom=TRUE)

valid<-names(sets);pp<-pred[Cohort%in%valid]
rocdata<-rbindlist(lapply(seq_len(nrow(unique(pp[,.(Cohort,Model,ModelLabel)]))),function(i){g<-unique(pp[,.(Cohort,Model,ModelLabel)])[i];d<-pp[Cohort==g$Cohort&Model==g$Model];r<-pROC::roc(d$Truth,d$Probability,levels=c("Other","HighRisk"),direction="<",quiet=TRUE);data.table(Cohort=g$Cohort,ModelLabel=g$ModelLabel,FPR=1-r$specificities,Sensitivity=r$sensitivities)}))
rocdata[,Cohort:=factor(Cohort,valid)];p1<-ggplot(rocdata,aes(FPR,Sensitivity,colour=ModelLabel,group=ModelLabel))+geom_abline(slope=1,intercept=0,linetype=2,colour="grey60")+geom_path(linewidth=.85)+facet_wrap(~Cohort,nrow=1)+coord_equal()+scale_colour_manual(values=cols)+labs(x="1 - Specificity",y="Sensitivity",colour="Model",title="ROC curves for high-risk MPP trajectory prediction")+theme_p;save_fig(p1,"03_ROC")
caldata<-copy(pp);caldata[,Bin:=pmin(10,pmax(1,ceiling(frank(Probability,ties.method="average")/.N*10))),by=.(Cohort,Model)];caldata<-caldata[,.(Predicted=mean(Probability),Observed=mean(Truth=="HighRisk")),by=.(Cohort,ModelLabel,Bin)];caldata[,Cohort:=factor(Cohort,valid)]
p2<-ggplot(caldata,aes(Predicted,Observed,colour=ModelLabel,group=ModelLabel))+geom_abline(slope=1,intercept=0,linetype=2,colour="grey60")+geom_line()+geom_point(size=1.5)+facet_wrap(~Cohort,nrow=1)+coord_equal()+scale_colour_manual(values=cols)+labs(x="Predicted probability",y="Observed proportion",colour="Model",title="Calibration curves")+theme_p;save_fig(p2,"03_Calibration")
thr<-seq(.01,.80,.01);dcmodel<-rbindlist(lapply(seq_len(nrow(unique(pp[,.(Cohort,Model,ModelLabel)]))),function(i){g<-unique(pp[,.(Cohort,Model,ModelLabel)])[i];d<-pp[Cohort==g$Cohort&Model==g$Model];yy<-truth01(d$Truth);data.table(Cohort=g$Cohort,Strategy=as.character(g$ModelLabel),Threshold=thr,NetBenefit=vapply(thr,function(t){cl<-d$Probability>=t;mean(cl&yy==1)-mean(cl&yy==0)*t/(1-t)},numeric(1)))}));base<-rbindlist(lapply(valid,function(n){d<-pp[Cohort==n&Model==unique(Model)[1]];pr<-mean(d$Truth=="HighRisk");rbind(data.table(Cohort=n,Strategy="Treat all",Threshold=thr,NetBenefit=pr-(1-pr)*thr/(1-thr)),data.table(Cohort=n,Strategy="Treat none",Threshold=thr,NetBenefit=0))}));dca<-rbind(dcmodel,base);dca[,Cohort:=factor(Cohort,valid)];strategy_levels<-c(unname(labels),"Treat all","Treat none");dca[,Strategy:=factor(Strategy,levels=strategy_levels)];dcols<-c(cols,"Treat all"="#4D4D4D","Treat none"="#999999");dlty<-setNames(c(rep("solid",5),"dashed","dotted"),strategy_levels)
theme_dca<-theme_bw(base_size=11,base_family="Times New Roman")+theme(
  text=element_text(family="Times New Roman",colour="#222222"),
  plot.title=element_text(size=15,face="bold",hjust=.5,margin=margin(b=12)),
  axis.title=element_text(size=12),axis.title.x=element_text(margin=margin(t=9)),
  axis.title.y=element_text(margin=margin(r=9)),axis.text=element_text(size=10.5,colour="#333333"),
  axis.ticks=element_line(colour="#555555",linewidth=.4),axis.ticks.length=grid::unit(3,"pt"),
  panel.border=element_rect(colour="#666666",linewidth=.45),
  panel.grid.minor=element_blank(),panel.grid.major.x=element_blank(),
  panel.grid.major.y=element_line(colour="#E5E7EB",linewidth=.35),
  panel.spacing.x=grid::unit(.9,"lines"),
  strip.background=element_rect(fill="#F3F4F6",colour="#B8BEC6",linewidth=.4),
  strip.text=element_text(size=11,face="bold",margin=margin(7,4,7,4)),
  legend.position="bottom",legend.title=element_blank(),legend.box="horizontal",
  legend.text=element_text(size=10),legend.key.width=grid::unit(.75,"cm"),
  legend.key.height=grid::unit(.45,"cm"),legend.spacing.x=grid::unit(.1,"cm"),
  legend.margin=margin(t=5),plot.margin=margin(10,12,8,10))
p3<-ggplot(dca,aes(Threshold,NetBenefit,colour=Strategy,linetype=Strategy,group=Strategy))+
  geom_line(linewidth=.8)+facet_wrap(~Cohort,nrow=1)+
  scale_colour_manual(values=dcols,breaks=strategy_levels)+
  scale_linetype_manual(values=dlty,breaks=strategy_levels)+
  scale_x_continuous(breaks=seq(0,.8,.2),labels=scales::percent_format(accuracy=1),expand=expansion(mult=c(.02,.025)))+
  scale_y_continuous(breaks=seq(0,.4,.1),labels=scales::label_number(accuracy=.1),expand=expansion(mult=c(0,.02)))+
  coord_cartesian(xlim=c(0,.8),ylim=c(-.02,.4))+
  labs(x="Threshold probability",y="Net benefit",colour="Model",linetype="Model",title="Decision curve analysis")+
  guides(colour=guide_legend(nrow=2,byrow=TRUE),linetype=guide_legend(nrow=2,byrow=TRUE))+theme_dca
save_fig(p3,"03_DCA",w=10.8,h=6.2)
fwrite(rocdata,file.path(TAB,"03_ROC_source.csv"),bom=TRUE);fwrite(caldata,file.path(TAB,"03_calibration_source.csv"),bom=TRUE);fwrite(dca,file.path(TAB,"03_DCA_source.csv"),bom=TRUE)

openxlsx::write.xlsx(list(Performance=met,Bootstrap_CI=ci,Calibration=calstat,Thresholds=data.table(Model=names(cuts),Threshold=unlist(cuts)),Settings=cfg),file.path(TAB,"03_machine_learning_results.xlsx"),overwrite=TRUE)
saveRDS(list(models=models,calibrators=calibrators,thresholds=cuts,predictions=pred,metrics=met,step2=z,settings=cfg),file.path(OBJ,"step3_models.rds"),compress="xz")
future::plan(future::sequential);cat("Step 3 complete.\n");print(met[Cohort%in%valid,.(Cohort,ModelLabel,AUROC,AUPRC,Brier)])
