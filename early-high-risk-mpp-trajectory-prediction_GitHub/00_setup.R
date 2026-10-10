# Run from the repository root. Uses the package versions recorded in renv.lock.
root <- normalizePath(Sys.getenv("MPP_REPO_ROOT", "."), winslash="/", mustWork=TRUE)
if (!file.exists(file.path(root,"renv.lock"))) stop("Run 00_setup.R from the repository root.")
if (!requireNamespace("renv",quietly=TRUE)) install.packages("renv",repos="https://cloud.r-project.org")
renv::restore(project=root,lockfile=file.path(root,"renv.lock"),prompt=FALSE)
renv::load(project=root)
cat("Project package library restored and loaded.\n")
