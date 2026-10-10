# MPP高危轨迹预测：GitHub代码包使用说明

这份代码包按已完成的MPP分析整理，研究人群为**接受CABG和/或瓣膜手术的成年ICU患者**。CABG与瓣膜手术为“或”的关系，同时接受两类手术的患者也包括在内。

**预测目标：Class 1＋Class 3直接合并为高危组；Class 2＋Class 4为其他组。** `Class`仅用于定义结局，不进入预测变量。

## 已整理内容

- 原有01–05五个分析脚本：只替换固定桌面路径，保留统计方法、调参范围、随机种子、LASSO规则、SHAP和DCA绘图逻辑。
- 一键运行入口、依赖版本文件、英文README、变量字典、数据与代码可用性说明、引用文件和MIT许可证。
- 原正式分析的19份汇总表、7张图片，包括已调整为0%–80%横坐标的DCA图。
- XGBoost本地研究计算器、模型导出脚本和验证脚本。

本仓库覆盖机器学习部分。它从已经合并并带有轨迹分类的队列文件开始，不包含原始数据库提取、轨迹拟合、Table 1或Cox等其他分析。整理代码包时没有重新调参或重新训练五个模型。

## 分析定义

数据版本为 **MIMIC-IV v3.1** 和 **eICU-CRD v2.0**。MIMIC-IV共6,896例，训练集4,826例、内部验证集2,070例；eICU外部验证集4,944例。

LASSO候选变量为Model 3的12项协变量（不含Class）＋初始MPP，共13项。原结果保留12个原始变量，形成13个编码特征；**WBC未入选**。后续五模型及计算器都沿用这一筛选结果。

XGBoost用于本次SHAP解释和计算器，但eICU外部验证中AUROC最高的是Logistic回归（0.778），XGBoost为0.768。说明文件按实际结果表述，不将XGBoost写成所有验证中最优。

## 在自己的电脑运行

1. 将R工作目录设为这个GitHub文件夹，推荐使用R 4.4.2。
2. 根据[data/README.md](data/README.md)准备自己的授权数据，分别命名为 `data/MIMICIV.csv` 和 `data/EICU.csv`，或用环境变量指定现有CSV路径。数据中每个 `stay_id` 必须唯一，轨迹类别必须已经确定。
3. 运行：

```r
source("00_setup.R", encoding = "UTF-8")
Sys.setenv(MPP_ML_FAST = "0", MPP_ML_WORKERS = "10")
source("00_run_all.R", encoding = "UTF-8")
```

完整分析会进行10折交叉验证、600次模型调参评估和1,000次bootstrap，耗时较长。新结果默认进入 `analysis_output/`，其中包括不能公开上传的逐例数据和模型。试运行时可以设置 `MPP_ML_FAST="1"` 并单独指定输出目录，但试运行结果不能代替正式分析结果。

## 本地计算器

本次交付另有独立的 `MPP_local_runtime` 文件夹，内含本地模型和启动文件。保持它与本GitHub文件夹位于同一父目录，运行其中的 `RUN_LOCAL_APP.R` 即可。该文件夹不放进GitHub压缩包。

计算器填写最终12个原始变量，输出校准概率、按训练集Youden阈值划分的组别及个体SHAP解释。显示的是MPP高危轨迹归属概率，不能将它表述为死亡率或MAKE30发生率。首屏数值来自训练集的中位数和众数，需替换为实际输入。

本地模型已与原分析保存结果核对：全部11,840例预处理矩阵一致；内部与外部验证合计7,014例预测概率一致，最大差异低于1e-14。

## 上传GitHub

上传这一个代码包文件夹的内容即可，包括脚本、说明、汇总结果和图片。建议仓库名称：`early-high-risk-mpp-trajectory-prediction`。

不要把旁边的 `MPP_local_runtime`、原始分析文件夹或后来生成的 `analysis_output` 一起拖入上传。PhysioNet现行[MIMIC-IV共享说明](https://physionet.org/content/mimiciv/3.1/)将衍生模型也列为受控共享资源，因此公开包只包含计算器代码和导出方法，本地模型单独保存。

创建真实GitHub仓库后，把实际地址补进 `CITATION.cff` 的 `repository-code`，再在论文的Code availability中使用该地址。文章题目、作者顺序及DOI以最终发表信息为准；当前代码包未填写不存在的文章引用或DOI。

依赖版本文件记录的是这次整理验证时的环境。实际的预测时间窗、轨迹类别跨数据库的对应关系和DCA的临床用途仍需与论文方法一致，详见[方法说明](docs/METHODS.md)。
