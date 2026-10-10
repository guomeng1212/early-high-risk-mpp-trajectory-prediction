# Local research calculator. See README.md and models/README.md before running.
pkgs <- c("shiny","bslib","ggplot2","scales","xgboost")
miss <- pkgs[!vapply(pkgs,requireNamespace,logical(1),quietly=TRUE)]
if(length(miss)) stop("Missing packages: ",paste(miss,collapse=", "),". Run 00_setup.R first.")
suppressPackageStartupMessages({library(shiny);library(bslib);library(ggplot2)})
ROOT <- normalizePath(Sys.getenv("MPP_REPO_ROOT","."),winslash="/",mustWork=TRUE)
source(file.path(ROOT,"R","predict_mpp.R"),local=TRUE,encoding="UTF-8")
MODEL_FILE <- Sys.getenv("MPP_DEPLOYMENT_MODEL",file.path(Sys.getenv("MPP_ML_ROOT",file.path(ROOT,"analysis_output")),"models","MPP_xgboost_deployment.rds"))
z <- if(file.exists(MODEL_FILE)) mpp_load_model(MODEL_FILE) else NULL
app_theme <- bs_theme(version=5,bootswatch="flatly",primary="#21618C",base_font="Arial",heading_font="Arial")

if(is.null(z)) {
  ui <- page_fluid(theme=app_theme,
    h2("High-risk MPP trajectory prediction"),
    card(card_header("A local model is required"),
      p("This repository provides the analysis and calculator code for CABG and/or valve surgery patients."),
      p("After an authorized local analysis, run 06_export_deployment.R. Alternatively, set MPP_DEPLOYMENT_MODEL to the path of an authorized local deployment file, then restart the app."),
      p("See models/README.md for the access conditions and setup instructions.")))
  server <- function(input,output,session) {}
} else {
  selected_vars <- unique(vapply(z$selected,mpp_parent,character(1),vars=z$vars))
  median_value <- function(v,digits=1) round(as.numeric(z$prep$num_median[[v]]),digits)
  mode_value <- function(v) as.character(z$prep$fac_mode[[v]])
  css <- HTML("body{background:#f5f7fa}.navbar-brand{font-weight:700}.card{border:1px solid #e7ebef;border-radius:10px;box-shadow:none}.card-header{font-weight:700;background:#fff}.form-label{font-weight:600}.small-note{font-size:.9rem;color:#526273}.value-box-value{font-size:2.1rem!important}.btn-primary{font-weight:600}.sidebar{background:#fff}.main-card{margin-bottom:1rem}")
  ui <- page_sidebar(
    title="High-risk MPP trajectory prediction",theme=app_theme,fillable=FALSE,header=tags$head(tags$style(css)),
    sidebar=sidebar(width=340,open="always",
      div(class="small-note mb-3","Research population: adults admitted to the ICU after CABG and/or valve surgery."),
      accordion(open=c("Initial MPP","Demographics and surgery"),
        accordion_panel("Initial MPP",
          numericInput("MPP","Initial MPP (mmHg)",median_value("MPP",2),step=.1),
          div(class="small-note","Use the first available MPP defined by the study protocol.")),
        accordion_panel("Demographics and surgery",
          numericInput("Age","Age (years)",median_value("Age",0),min=19,step=1),
          selectInput("Gender","Sex",choices=c("Female"="F","Male"="M"),selected=mode_value("Gender")),
          selectInput("Race","Race",choices=setdiff(z$prep$fac_levels$Race,"Unknown"),selected=mode_value("Race")),
          selectInput("CABG","CABG",choices=c("No","Yes"),selected=mode_value("CABG")),
          selectInput("Valve","Valve surgery",choices=c("No","Yes"),selected=mode_value("Valve"))),
        accordion_panel("Severity and laboratory tests",
          numericInput("SOFA","SOFA score",median_value("SOFA",0),min=0,step=1),
          numericInput("CCI","Charlson Comorbidity Index",median_value("CCI",0),min=0,step=1),
          numericInput("Hb","Hemoglobin (g/dL)",median_value("Hb",1),min=0,step=.1),
          numericInput("Plt","Platelet count (10^9/L)",median_value("Plt",0),min=0,step=1),
          if("WBC"%in%selected_vars) numericInput("WBC","White blood cell count (10^9/L)",median_value("WBC",1),min=0,step=.1)),
        accordion_panel("Interventions within 24 h",
          selectInput("Vasopressors","Vasopressor use",choices=c("No","Yes"),selected=mode_value("Vasopressors")),
          selectInput("Mechanical_Ventilation","Mechanical ventilation",choices=c("No","Yes"),selected=mode_value("Mechanical_Ventilation")))),
      actionButton("calculate","Calculate probability and SHAP",class="btn-primary w-100 mt-3"),
      div(class="small-note mt-3","Initial values are training-cohort medians and modes. Replace them with the intended input profile. Blank numeric values are imputed using the stored training median.")),
    div(class="mb-3",h4("Predefined trajectory membership"),
      p("High-risk group: Classes 1 + 3. Other group: Classes 2 + 4."),
      div(class="small-note","The result reflects the last calculation. The model uses initial MPP and specified baseline/first-24-hour variables.")),
    uiOutput("summary"),
    layout_columns(col_widths=c(8,4),
      div(card(class="main-card",card_header("Estimated probability"),plotOutput("probability_plot",height=190)),
          card(class="main-card",card_header("Individual SHAP contributions"),
               div(class="small-note","Positive contributions increase the uncalibrated XGBoost score; negative contributions decrease it."),
               plotOutput("shap_plot",height=480))),
      div(card(class="main-card",card_header("Interpretation"),uiOutput("interpretation")),
          card(class="main-card",card_header("Input handling"),uiOutput("handling")),
          card(class="main-card",card_header("Export this calculation"),
               downloadButton("download","Download research result",class="btn-outline-primary")),
          card(class="main-card",div(class="small-note",
            "Research use only. This tool estimates trajectory-group membership, not mortality or MAKE30. SHAP values are not causal effects or calibrated probability contributions. A clinical action threshold has not been established."))))
  )
  server <- function(input,output,session) {
    result <- eventReactive(input$calculate,{
      validate(need(input$CABG=="Yes"||input$Valve=="Yes","Select CABG, valve surgery, or both to match the study population."))
      validate(need(is.null(input$Age)||is.na(input$Age)||input$Age>18,"The study cohort requires age >18 years."))
      values <- mpp_default_input(z)
      for(v in z$vars) if(!is.null(input[[v]])) values[[v]] <- input[[v]]
      pred <- mpp_predict(values,z,explain=TRUE)
      shap <- data.frame(Feature=z$selected,Label=vapply(z$selected,mpp_feature_label,character(1),z=z),
        SHAP=as.numeric(pred$shap[1,]),stringsAsFactors=FALSE)
      shap <- shap[order(abs(shap$SHAP),decreasing=TRUE),]
      list(values=values,pred=pred,shap=shap)
    },ignoreNULL=TRUE)
    output$summary <- renderUI({
      if(input$calculate==0) return(card(class="mb-3",p("Set the inputs, then select Calculate probability and SHAP.")))
      r <- result(); high <- r$pred$probability>=z$threshold
      layout_columns(col_widths=c(4,4,4),
        value_box(title="Calibrated probability",value=scales::percent(r$pred$probability,accuracy=.1),theme="primary"),
        value_box(title="Threshold-based group",value=if(high)"High-risk"else"Other",p(if(high)"Classes 1 + 3"else"Classes 2 + 4"),theme="secondary"),
        value_box(title="Training-derived threshold",value=scales::percent(z$threshold,accuracy=.1),theme="secondary"))
    })
    output$probability_plot <- renderPlot({
      r<-result(); p<-r$pred$probability
      ggplot()+annotate("rect",xmin=0,xmax=1,ymin=.3,ymax=.7,fill="#E8EEF4")+
        geom_vline(xintercept=z$threshold,linetype="dashed",colour="#677686",linewidth=.6)+
        annotate("point",x=p,y=.5,size=5.5,colour="#21618C")+
        annotate("text",x=p,y=.82,label=scales::percent(p,accuracy=.1),fontface="bold",size=4.5)+
        scale_x_continuous(limits=c(0,1),breaks=seq(0,1,.2),labels=scales::percent)+
        coord_cartesian(ylim=c(0,1),clip="off")+labs(x="Estimated high-risk trajectory probability",y=NULL)+
        theme_minimal(base_size=12)+theme(axis.text.y=element_blank(),axis.ticks.y=element_blank(),panel.grid=element_blank())
    })
    output$shap_plot <- renderPlot({
      r<-result(); p<-r$shap; p$Label<-factor(p$Label,levels=rev(p$Label));p$Direction<-ifelse(p$SHAP>=0,"Positive","Negative")
      ggplot(p,aes(SHAP,Label,fill=Direction))+geom_vline(xintercept=0,colour="#8794A1",linewidth=.4)+
        geom_col(width=.68)+scale_fill_manual(values=c(Positive="#D55E00",Negative="#21618C"))+
        labs(x="SHAP contribution to raw model log-odds",y=NULL,fill=NULL)+
        theme_minimal(base_size=12)+theme(panel.grid.major.y=element_blank(),panel.grid.minor=element_blank(),legend.position="bottom")
    })
    output$interpretation <- renderUI({
      r<-result();prediction<-r$pred
      tagList(paste0("Estimated membership in the combined high-risk group: ",scales::percent(prediction$probability,accuracy=.1),"."),
        p(paste0("Threshold-based assignment: ",prediction$group,".")),
        p("The threshold maximized the Youden index in calibrated training out-of-fold predictions. It is a classification rule for this study."),
        p("XGBoost was used for SHAP and this calculator. Logistic regression had the highest external-validation AUROC in the supplied analysis."))
    })
    output$handling <- renderUI({
      r<-result();h<-r$pred$prepared$handling
      h<-h[h$Variable%in%selected_vars,,drop=FALSE]
      if(!nrow(h)) return(p("No selected input required imputation or winsorization."))
      tags$ul(lapply(seq_len(nrow(h)),function(i)tags$li(paste0(z$display[[h$Variable[i]]],": ",h$Handling[i]))))
    })
    output$download <- downloadHandler(
      filename=function()paste0("MPP_research_calculation_",Sys.Date(),".csv"),
      content=function(file){
        r<-result(); p<-r$pred
        selected_input<-r$values[,selected_vars,drop=FALSE]
        entries<-data.frame(Section="Input",Field=names(selected_input),Value=as.character(unlist(selected_input)),stringsAsFactors=FALSE)
        prediction<-data.frame(Section="Prediction",Field=c("Probability","Threshold","Group","Raw_probability","SHAP_baseline_log_odds"),
          Value=as.character(c(p$probability,p$threshold,p$group,p$raw_probability,p$shap_baseline)))
        contributions<-data.frame(Section="SHAP_raw_log_odds",Field=r$shap$Label,Value=as.character(r$shap$SHAP))
        write.csv(rbind(entries,prediction,contributions),file,row.names=FALSE,fileEncoding="UTF-8")
      })
  }
}
shinyApp(ui,server)
