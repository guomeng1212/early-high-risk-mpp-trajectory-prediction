# ============================================================
# 02 Feature engineering: LASSO on MIMIC-IV training data only
# Selection rule explicitly fixed at lambda.min
# Outcome: high-risk MPP trajectory (Classes 1 + 3 vs Classes 2 + 4)
# ============================================================
suppressPackageStartupMessages({library(data.table); library(glmnet); library(ggplot2); library(ragg); library(openxlsx)})
set.seed(20260902)
ROOT <- Sys.getenv("MPP_ML_ROOT", file.path(getwd(),"analysis_output"))
obj <- readRDS(file.path(ROOT,"objects","step1_preprocessed.rds")); tr <- obj$processed$train
x <- tr$x; y <- as.integer(tr$y=="HighRisk")
if(sum(y)<10 || sum(y==0)<10) stop("Insufficient outcome events for LASSO")

cv <- cv.glmnet(x,y,family="binomial",alpha=1,nfolds=10,type.measure="deviance",
                standardize=FALSE,keep=TRUE,parallel=FALSE)
lambda_use <- cv$lambda.min
cf <- as.matrix(coef(cv,s=lambda_use)); selected <- setdiff(rownames(cf)[abs(cf[,1])>1e-8],"(Intercept)")
if(!length(selected)) stop("lambda.min selected no predictors")

coef_table <- data.table(Feature=rownames(cf),Coefficient=as.numeric(cf[,1]))[Feature!="(Intercept)"]
coef_table[,Selected:=Feature %in% selected][,Abs_coefficient:=abs(Coefficient)]
setorder(coef_table,-Abs_coefficient)
selected_table <- coef_table[Selected==TRUE]

disp <- c(Age="Age",Gender="Gender",Race="Race",CABG="CABG",Valve="Valve",
          SOFA="SOFA",CCI="CCI",Hb="Hb",WBC="WBC",Plt="Plt",
          Vasopressors="Vasopressors",Mechanical_Ventilation="Mechanical ventilation",MPP="Initial MPP")
label_feature <- function(v){
  hit<-names(disp)[vapply(names(disp),function(k)startsWith(v,k),logical(1))]
  if(!length(hit)) return(v); k<-hit[which.max(nchar(hit))]
  suffix<-sub(paste0("^",k),"",v); paste0(disp[[k]],if(nzchar(suffix))paste0(": ",gsub("_"," ",suffix))else"")
}
coef_table[,Label:=vapply(Feature,label_feature,character(1))]
selected_table <- coef_table[Selected==TRUE]

cvtab<-data.table(Lambda=cv$lambda,LogLambda=log(cv$lambda),Deviance=cv$cvm,
                  Lower=cv$cvlo,Upper=cv$cvup,Nzero=cv$nzero)
m<-10L;idx<-unique(pmax(1L,pmin(nrow(cvtab),round(seq(1,nrow(cvtab),length.out=m)))))
sec_dat<-cvtab[idx][order(LogLambda)];sec_breaks<-sec_dat$LogLambda;sec_labels<-sec_dat$Nzero
pal<-viridisLite::viridis(3,option="H",begin=.2,end=.8)
theme_lasso<-theme_classic(base_family="Times New Roman",base_size=12)+theme(
  text=element_text(family="Times New Roman",colour="black"),
  panel.border=element_rect(fill=NA,colour="black",linewidth=.5),axis.line=element_line(linewidth=.5),
  axis.title.x.top=element_text(size=13,face="bold",margin=margin(b=6)),axis.text.x.top=element_text(size=11),
  axis.title.x=element_text(size=13,face="bold"),axis.text.x=element_text(size=11),
  axis.title.y=element_text(size=13,face="bold"),axis.text.y=element_text(size=11),
  axis.ticks=element_line(linewidth=.45),legend.title=element_blank(),legend.text=element_text(size=9),
  legend.key.size=grid::unit(.5,"cm"),plot.margin=margin(8,8,8,8,"mm"))
p1<-ggplot(cvtab,aes(LogLambda,Deviance,colour=Nzero))+
  geom_errorbar(aes(ymin=Lower,ymax=Upper),width=.02,alpha=.5,linewidth=.35)+geom_point(size=2)+
  scale_colour_viridis_c(option="H",begin=.2,end=.8,guide="none")+
  geom_vline(xintercept=log(cv$lambda.min),linetype="dashed",colour=pal[1],linewidth=.7)+
  geom_vline(xintercept=log(cv$lambda.1se),linetype="dashed",colour=pal[3],linewidth=.7)+
  scale_x_continuous(name=expression(log(lambda)),sec.axis=dup_axis(breaks=sec_breaks,labels=sec_labels,name="Number of non-zero coefficients"))+
  labs(y="CV Deviance")+theme_lasso
agg_png(file.path(ROOT,"figures","01_LASSO_cross_validation.png"),width=12,height=9,units="in",res=600,background="white");print(p1);dev.off()

fit<-cv$glmnet.fit;beta<-as.matrix(fit$beta);imp<-apply(abs(beta),1,max);imp<-imp[imp>0]
top<-names(head(sort(imp,decreasing=TRUE),15))
path<-rbindlist(lapply(seq_along(fit$lambda),function(j)data.table(Feature=top,Coefficient=beta[top,j],LogLambda=log(fit$lambda[j]))))
path[,Label:=vapply(Feature,label_feature,character(1))]
fwrite(cvtab,file.path(ROOT,"tables","02_LASSO_CV_source.csv"));fwrite(path,file.path(ROOT,"tables","02_LASSO_path_source.csv"))
p2<-ggplot(path,aes(LogLambda,Coefficient,colour=Label,group=Feature))+
  geom_hline(yintercept=0,colour="grey75",linewidth=.35)+geom_line(linewidth=.8)+
  geom_vline(xintercept=log(cv$lambda.min),linetype="dashed",colour=pal[1],linewidth=.7,show.legend=FALSE)+
  geom_vline(xintercept=log(cv$lambda.1se),linetype="dashed",colour=pal[3],linewidth=.7,show.legend=FALSE)+
  scale_x_continuous(name=expression(log(lambda)),sec.axis=dup_axis(breaks=sec_breaks,labels=sec_labels,name="Number of non-zero coefficients"))+
  scale_colour_viridis_d(option="H",begin=.1,end=.9,name=NULL)+labs(y="Coefficient")+
  theme_lasso+theme(legend.position="right")
agg_png(file.path(ROOT,"figures","02_LASSO_coefficient_paths.png"),width=12,height=9,units="in",res=600,background="white");print(p2);dev.off()

for(nm in names(obj$processed)) obj$processed[[nm]]$x <- obj$processed[[nm]]$x[,selected,drop=FALSE]
lasso_obj <- list(preprocessed=obj,cvfit=cv,lambda=lambda_use,rule="lambda.min",
                  selected=selected,coefficients=coef_table)
saveRDS(lasso_obj,file.path(ROOT,"objects","step2_lasso.rds"))
write.xlsx(list(Selected_features=selected_table,All_coefficients=coef_table,
                LASSO_summary=data.table(Rule="lambda.min",Lambda=lambda_use,N_selected=length(selected))),
           file.path(ROOT,"tables","02_LASSO_feature_selection.xlsx"),overwrite=TRUE)
fwrite(selected_table,file.path(ROOT,"tables","02_LASSO_selected_features.csv"))
cat("Step 2 complete: lambda.min =",lambda_use,"; selected",length(selected),"features.\n")
print(selected_table[,.(Feature,Label,Coefficient)])
