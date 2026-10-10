# 05 Recompute and replot DCA through 80% using saved calibrated predictions
# Outcome: high-risk MPP trajectory (Classes 1 + 3 vs Classes 2 + 4)
suppressPackageStartupMessages({library(data.table);library(ggplot2);library(ragg)})
ROOT<-Sys.getenv("MPP_ML_ROOT",file.path(getwd(),"analysis_output"))
pred<-fread(file.path(ROOT,"predictions","03_all_predictions.csv"))
valid<-c("MIMIC-IV internal validation","eICU external validation")
strategy_levels<-c("Logistic regression","XGBoost","Random forest","SVM-RBF","k-NN","Treat all","Treat none")
thr<-seq(.01,.80,.01)
pp<-pred[Cohort%in%valid]
groups<-unique(pp[,.(Cohort,Model,ModelLabel)])
dcmodel<-rbindlist(lapply(seq_len(nrow(groups)),function(i){
  g<-groups[i];d<-pp[Cohort==g$Cohort&Model==g$Model];yy<-d$Truth=="HighRisk"
  data.table(Cohort=g$Cohort,Strategy=as.character(g$ModelLabel),Threshold=thr,
    NetBenefit=vapply(thr,function(t){cl<-d$Probability>=t;mean(cl&yy)-mean(cl&!yy)*t/(1-t)},numeric(1)))
}))
base<-rbindlist(lapply(valid,function(n){
  d<-pp[Cohort==n&Model==unique(Model)[1]];pr<-mean(d$Truth=="HighRisk")
  rbind(data.table(Cohort=n,Strategy="Treat all",Threshold=thr,NetBenefit=pr-(1-pr)*thr/(1-thr)),
        data.table(Cohort=n,Strategy="Treat none",Threshold=thr,NetBenefit=0))
}))
dca<-rbind(dcmodel,base)
dca[,Cohort:=factor(Cohort,levels=valid)];dca[,Strategy:=factor(Strategy,levels=strategy_levels)]
fwrite(dca,file.path(ROOT,"tables","03_DCA_source.csv"),bom=TRUE)
cols<-c("Logistic regression"="#0072B2","XGBoost"="#D55E00","Random forest"="#009E73","SVM-RBF"="#CC79A7","k-NN"="#E69F00","Treat all"="#4D4D4D","Treat none"="#999999")
dlty<-setNames(c(rep("solid",5),"dashed","dotted"),strategy_levels)
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
p<-ggplot(dca,aes(Threshold,NetBenefit,colour=Strategy,linetype=Strategy,group=Strategy))+
  geom_line(linewidth=.8)+facet_wrap(~Cohort,nrow=1)+
  scale_colour_manual(values=cols,breaks=strategy_levels)+
  scale_linetype_manual(values=dlty,breaks=strategy_levels)+
  scale_x_continuous(breaks=seq(0,.8,.2),labels=scales::percent_format(accuracy=1),expand=expansion(mult=c(.02,.025)))+
  scale_y_continuous(breaks=seq(0,.4,.1),labels=scales::label_number(accuracy=.1),expand=expansion(mult=c(0,.02)))+
  coord_cartesian(xlim=c(0,.8),ylim=c(-.02,.4))+
  labs(x="Threshold probability",y="Net benefit",colour="Model",linetype="Model",title="Decision curve analysis")+
  guides(colour=guide_legend(nrow=2,byrow=TRUE),linetype=guide_legend(nrow=2,byrow=TRUE))+theme_dca
ragg::agg_png(file.path(ROOT,"figures","03_DCA.png"),width=10.8,height=6.2,units="in",res=600,background="white");print(p);dev.off()
cat("DCA updated: threshold grid 1%–80%, axis 0%–80%.\n")
