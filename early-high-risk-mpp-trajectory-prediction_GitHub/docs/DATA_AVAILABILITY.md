# Data and code availability

## Data availability — reusable manuscript wording

The study used the MIMIC-IV database (version 3.1; https://doi.org/10.13026/kpb9-mt58) and the eICU Collaborative Research Database (version 2.0; https://doi.org/10.13026/C2WM1R), available through PhysioNet. Access to the individual-level source data requires completion of the applicable credentialing and training requirements and agreement to the corresponding data-use terms. The study-specific merged cohorts, individual predictions and individual SHAP outputs are not redistributed in this repository. Aggregate model-evaluation tables and analysis figures are provided in the repository's `results/` and `figures/` directories. MIMIC-derived trained models are excluded from the public code repository and remain subject to the source-data access and sharing conditions.

## Code availability — repository wording

The R code for preprocessing, LASSO feature selection, five-model development and evaluation, SHAP interpretation, DCA plotting, and the local research calculator is provided in this repository under the MIT license. The repository includes software metadata in `CITATION.cff`, dependency versions in `renv.lock`, and instructions for running the analysis with authorized local data. It begins with the study-specific merged and trajectory-labelled cohorts; upstream database extraction and trajectory fitting are outside this code release.

For the manuscript's final Code availability statement, cite the actual published repository URL and the released version/commit. Add an archival DOI only if one has actually been issued. This local package has not been assigned a repository URL or software DOI by the preparation workflow.

## Resource-to-location mapping

| Resource | Location / access route |
|---|---|
| MIMIC-IV v3.1 source data | [PhysioNet, credentialed access](https://physionet.org/content/mimiciv/3.1/) |
| eICU-CRD v2.0 source data | [PhysioNet, credentialed access](https://physionet.org/content/eicu-crd/2.0/) |
| Study-specific merged cohorts, split IDs, individual outputs | Author's authorized local study environment; not redistributed here |
| Aggregate evaluation tables and figures | `results/` and `figures/` in this code package |
| Analysis/calculator code | This repository; MIT code license |
| Fitted models, including minimal deployment model | Authorized local use or a source-compatible controlled-access deposit; no deposit is claimed |

Official MIMIC-IV guidance states that derived datasets and models should be treated as sensitive information and shared under the same agreement as the source data. Removing patient rows from a model object is not a change in those access conditions. [Official guidance](https://physionet.org/content/mimiciv/3.1/).

## Formal dataset references

Johnson, A., Bulgarelli, L., Pollard, T., Gow, B., Moody, B., Horng, S., Celi, L. A. & Mark, R. MIMIC-IV (version 3.1). PhysioNet (2024). https://doi.org/10.13026/kpb9-mt58.

Pollard, T., Johnson, A., Raffa, J., Celi, L. A., Badawi, O. & Mark, R. eICU Collaborative Research Database (version 2.0). PhysioNet (2019). https://doi.org/10.13026/C2WM1R.

BibTeX entries are in [references.bib](references.bib). These cite the dataset versions, rather than replacing them with the separate database-description articles.

## 中文核对

- MIMIC-IV版本已由作者确认为v3.1；eICU使用v2.0。
- “可通过PhysioNet申请访问”不等于无需条件的公开下载；访问条件以相应官方页面和数据使用协议为准。
- GitHub包提供代码、汇总表和图，不包含逐例数据、逐例预测、逐例SHAP或已训练模型。
- 代码MIT许可不改变MIMIC/eICU源数据及其衍生模型的使用条件。
- 上传后需要补入真实仓库地址和发布版本；文章题目、DOI和受控模型存储编号均未杜撰。
