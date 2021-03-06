% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/universe.R
\name{update_universe}
\alias{update_universe}
\title{Update Universe}
\usage{
update_universe(remote, dirname = basename(remote), ref = "master", dest = ".")
}
\arguments{
\item{remote}{URL of the upstream git repository to add}

\item{dirname}{name of the submodule to add}

\item{ref}{which branch or commit to checkout for this submodule}

\item{dest}{root of the data drive}
}
\description{
Update git reference in the meta repository.
}
