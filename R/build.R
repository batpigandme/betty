#' Betty Build
#'
#' Builds pkgdown site and source package from  a git remote and optionally
#' publish it directly to \url{https://docs.ropensci.org}.
#'
#' @rdname build
#' @param repo either local path or remote url of the git repository
#' @param dest path of volume to save docs and src output
#' @param git_url full URL of the git remote (used to customize the template)
#' @param deploy_url optional base domain name under which sites will be hosted.
#' @export
#' @examples \dontrun{
#' build_site('https://github.com/ropensci/magick')
#' }
build_site <- function(repo, dest = ".", git_url = "", deploy_url = 'https://docs.ropensci.org'){
  dest <- normalizePath(dest, mustWork = TRUE)
  doc_dir <- paste0(dest, "/docs/")
  src_dir <- paste0(dest, "/src/contrib/")

  # Either clone or open the Git repo
  if(grepl("^(https://|git@)", repo)){
    remote <- repo
    src <- tempfile()
    gert::git_clone(remote, path = src, verbose = TRUE)
  } else {
    src <- normalizePath(repo, mustWork = TRUE)
    remote <- gert::git_remote_list(src)$url[1]
  }

  pwd <- getwd()
  on.exit(setwd(pwd), add = TRUE)
  setwd(src)
  if(!file.exists('DESCRIPTION'))
    stop("Remote does not contain an R package")

  if(file.exists('.norodocs'))
    stop("Package contains a '.norodocs' file, not generating docs")

  # From pkgdown build_home_index()
  home_files <- c("index.Rmd", "README.Rmd", "index.md", "README.md")
  home_files <- Filter(file.exists, home_files)
  if(!length(home_files))
    stop("Package does not contain an index.(r)md or README.(r)md file")

  # Install package locally
  utils::setRepositories(ind = 1:4)
  options(repos = c("rOpenSci" = 'https://dev.ropensci.org', getOption('repos')))

  # Extra packages
  #try(install_travis_packages())
  try(install_pkgdown_packages())
  Sys.setenv(R_REMOTES_NO_ERRORS_FROM_WARNINGS=TRUE)
  remotes::install_deps(dependencies = TRUE, upgrade = TRUE)
  pkgfile <- pkgbuild::build(dest_path = tempdir(), vignettes = FALSE)
  utils::install.packages(pkgfile, repos = NULL)
  pkg <- strsplit(basename(pkgfile), "_", fixed = TRUE)[[1]][1]

  # Hack the readme
  lapply(home_files, modify_ropensci_readme, pkg = pkg, git_url = git_url)

  # Build the website
  title <- sprintf("rOpenSci: %s", pkg)
  url <- paste0(deploy_url, "/", pkg)
  dest <- paste0(doc_dir, pkg)
  tmp <- paste0(dest, "_TMP")
  template <- list(
    params = list(
      docsearch = list(
        api_key = '799829e946e1f0f9cd5b5a782c6316b9',
        index_name = paste0('ropensci-', tolower(pkg))
      )
    )
  )
  if(!isTRUE(grepl('ropenscilabs', git_url))){
    template$package = "rotemplate"

    # Hack: pkgdown doesn't seem to override packages that set: template:path
    template$path = system.file("pkgdown/templates", package='rotemplate')
  }

  unlink(tmp, recursive = TRUE)

  # Remove temp site in case of failure
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  Sys.setenv(NOT_CRAN="true")
  pkgdown::build_site(devel = FALSE, preview = FALSE, install = FALSE, override =
    list(destination = tmp, title = title, url = url, template = template,
         development = list(mode = 'release')))
  file.create(file.path(tmp, '.nojekyll'))

  # Save some info about the repo
  head <- gert::git_log(max = 1, repo = src)
  jsonlite::write_json(list(commit = as.list(head), remote = remote, pkg = pkg),
                       file.path(tmp, 'info.json'), pretty = TRUE, auto_unbox = TRUE)

  # Store the source pkg and update repo (todo: use cranlike)
  dir.create(src_dir, showWarnings = FALSE, recursive = TRUE)
  unlink(sprintf("%s%s_*.tar.gz", src_dir, pkg))
  file.copy(pkgfile, src_dir)
  tools::write_PACKAGES(src_dir)

  # Move site to final location
  unlink(dest, recursive = TRUE)
  file.rename(tmp, dest)
  invisible(dest)
}

#' @export
#' @rdname build
build_all_sites <- function(dest = "."){
  registry <- "https://ropensci.github.io/roregistry/registry.json"
  packages <- jsonlite::fromJSON(registry)$packages
  success <- vector("list", 10)
  for(i in 1:nrow(packages)){
    url <- packages[i, "url"]
    success[[i]] <- tryCatch(build_site(url, dest = dest), error = function(e){
      cat(sprintf("Failure for: %s:\n", url))
      print(e)
      return(e$message)
    })
  }
  names(success) <- packages$name
  jsonlite::write_json(success, file.path(dest, 'build.json'), pretty = TRUE, auto_unbox = TRUE)
}

install_travis_packages <- function(){
  if(file.exists('.travis.yml')){
    travis_config <- yaml::read_yaml('.travis.yml')
    extra_pkgs <- c(travis_config$r_packages, travis_config$bioc_packages)
    if(length(extra_pkgs)){
      remotes::install_cran(extra_pkgs, upgrade = FALSE)
    }
    if(length(travis_config$r_github_packages)){
      remotes::install_github(travis_config$r_github_packages, upgrade = FALSE)
    }
  }
}

install_pkgdown_packages <- function(){
  if(file.exists('_pkgdown.yml')){
    pkgdown_config <- yaml::read_yaml('_pkgdown.yml')
    extra_pkgs <- c(pkgdown_config$extra_packages)
    is_github <- grepl('/', extra_pkgs)
    cran_pkgs <- extra_pkgs[!is_github]
    gh_pkgs <- extra_pkgs[is_github]
    if(length(cran_pkgs)){
      remotes::install_cran(cran_pkgs, upgrade = FALSE)
    }
    if(length(gh_pkgs)){
      remotes::install_github(gh_pkgs, upgrade = FALSE)
    }
  }
}
