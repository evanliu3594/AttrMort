#' the GEMM C-R curves by Burnett et al.
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide tibble: a character \code{conc} column rendered at one decimal place
#'   plus one column per \code{endpoint_age} stratum.
#'
"GEMM_Lookup_Table"

#' the IER C-R curves by GBD2010.
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide tibble: a character \code{conc} column rendered at one decimal place
#'   plus one column per \code{endpoint_age} stratum.
#'
"IER2010_Lookup_Table"

#' the IER C-R curves by GBD2013.
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide tibble: a character \code{conc} column rendered at one decimal place
#'   plus one column per \code{endpoint_age} stratum.
#'
"IER2013_Lookup_Table"

#' the IER C-R curves by GBD2015.
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide tibble: a character \code{conc} column rendered at one decimal place
#'   plus one column per \code{endpoint_age} stratum.
#'
"IER2015_Lookup_Table"

#' the IER C-R curves by GBD2017.
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide tibble: a character \code{conc} column rendered at one decimal place
#'   plus one column per \code{endpoint_age} stratum.
#'
"IER2017_Lookup_Table"

#' the MRBRT C-R curves for PM25 by GBD2019.
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide tibble: a character \code{conc} column rendered at one decimal place
#'   plus one column per \code{endpoint_age} stratum.
#'
"MRBRT2019_Lookup_Table"

#' the MRBRT C-R curves for PM25 by GBD2021.
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide tibble: a character \code{conc} column rendered at one decimal place
#'   plus one column per \code{endpoint_age} stratum.
#'
"MRBRT2021_Lookup_Table"

#' the C-R curves for NO2 by Larkin et al.
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide tibble: a character \code{conc} column rendered at one decimal place
#'   plus one column per \code{endpoint_age} stratum.
#'
"NO2_CR_Lookup_Table"

#' the C-R curves for O3 by Carey et al.
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide tibble: a character \code{conc} column rendered at one decimal place
#'   plus one column per \code{endpoint_age} stratum.
#'
"O3_CR_Lookup_Table"

## quiets concerns of R CMD check
if (getRversion() >= "3.1.0") {
  utils::globalVariables(".")    
}