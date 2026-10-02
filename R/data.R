# Documentation of the concentration-response tables shipped in `data/`.
#
# Every table has the same shape: a list of three wide data.frames (MEAN, LOW,
# UP) keyed by a character `conc` column rendered at one decimal place, plus one
# `endpoint_age` column per stratum. `rr_std()` turns them into the join-ready
# long form; `cr_config()` and `inst/extdata/cr_models.json` say which table
# backs which model. See `data-raw/README.md` for how the keys are rendered.

#' GEMM concentration-response lookup table
#'
#' The Global Exposure mortality Model (GEMM) curves for PM<sub>2.5</sub>
#' mortality, the default model of [mortality()].
#'
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide data.frame: a character \code{conc} column rendered at one decimal
#'   place plus one column per \code{endpoint_age} stratum.
#'
#' @source Burnett et al. (2014), \emph{Environmental Health Perspectives}
#'   122(4): 397-403, doi:10.1289/ehp.1307049.
"GEMM_Lookup_Table"

#' IER concentration-response lookup table (GBD 2010)
#'
#' The integrated exposure-response (IER) curves for PM<sub>2.5</sub> mortality
#' as used by the Global Burden of Disease 2010 comparative risk assessment.
#'
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide data.frame: a character \code{conc} column rendered at one decimal
#'   place plus one column per \code{endpoint_age} stratum.
#'
#' @source Global Burden of Disease Study 2010 comparative risk assessment
#'   (Institute for Health Metrics and Evaluation), IER relative-risk curves.
"IER2010_Lookup_Table"

#' IER concentration-response lookup table (GBD 2013)
#'
#' The integrated exposure-response (IER) curves for PM<sub>2.5</sub> mortality
#' as used by the Global Burden of Disease 2013 comparative risk assessment.
#'
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide data.frame: a character \code{conc} column rendered at one decimal
#'   place plus one column per \code{endpoint_age} stratum.
#'
#' @source Global Burden of Disease Study 2013 comparative risk assessment
#'   (Institute for Health Metrics and Evaluation), IER relative-risk curves.
"IER2013_Lookup_Table"

#' IER concentration-response lookup table (GBD 2015)
#'
#' The integrated exposure-response (IER) curves for PM<sub>2.5</sub> mortality
#' as used by the Global Burden of Disease 2015 comparative risk assessment.
#'
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide data.frame: a character \code{conc} column rendered at one decimal
#'   place plus one column per \code{endpoint_age} stratum.
#'
#' @source Global Burden of Disease Study 2015 comparative risk assessment
#'   (Institute for Health Metrics and Evaluation), IER relative-risk curves.
"IER2015_Lookup_Table"

#' IER concentration-response lookup table (GBD 2017)
#'
#' The integrated exposure-response (IER) curves for PM<sub>2.5</sub> mortality
#' as used by the Global Burden of Disease 2017 comparative risk assessment.
#'
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide data.frame: a character \code{conc} column rendered at one decimal
#'   place plus one column per \code{endpoint_age} stratum.
#'
#' @source Global Burden of Disease Study 2017 comparative risk assessment
#'   (Institute for Health Metrics and Evaluation), IER relative-risk curves.
"IER2017_Lookup_Table"

#' MR-BRT concentration-response lookup table (GBD 2019)
#'
#' The MR-BRT (meta-regression--Bayesian, regularised, trimmed) relative-risk
#' curves for PM<sub>2.5</sub> mortality from the Global Burden of Disease 2019
#' risk-factor analysis.
#'
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide data.frame: a character \code{conc} column rendered at one decimal
#'   place plus one column per \code{endpoint_age} stratum.
#'
#' @source Global Burden of Disease Study 2019 risk-factor analysis (Institute
#'   for Health Metrics and Evaluation), MR-BRT relative-risk curves.
"MRBRT2019_Lookup_Table"

#' MR-BRT concentration-response lookup table (GBD 2021)
#'
#' The MR-BRT (meta-regression--Bayesian, regularised, trimmed) relative-risk
#' curves for PM<sub>2.5</sub> mortality from the Global Burden of Disease 2021
#' risk-factor analysis.
#'
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide data.frame: a character \code{conc} column rendered at one decimal
#'   place plus one column per \code{endpoint_age} stratum.
#'
#' @source Global Burden of Disease Study 2021 risk-factor analysis (Institute
#'   for Health Metrics and Evaluation), MR-BRT relative-risk curves.
"MRBRT2021_Lookup_Table"

#' NO2 concentration-response lookup table
#'
#' The nitrogen dioxide (NO<sub>2</sub>) relative-risk curve of the Global
#' Burden of Disease risk-factor analysis, attributed to Larkin et al.
#'
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide data.frame: a character \code{conc} column rendered at one decimal
#'   place plus one column per \code{endpoint_age} stratum.
#'
#' @source The NO<sub>2</sub> relative-risk curve of the Global Burden of
#'   Disease risk-factor analysis (Institute for Health Metrics and
#'   Evaluation), attributed there to Larkin et al.
"NO2_CR_Lookup_Table"

#' O3 concentration-response lookup table
#'
#' The ozone (O<sub>3</sub>) relative-risk curve of the Global Burden of Disease
#' risk-factor analysis, attributed to Carey et al.
#'
#' @format A list with elements \code{MEAN}, \code{LOW} and \code{UP}, each a
#'   wide data.frame: a character \code{conc} column rendered at one decimal
#'   place plus one column per \code{endpoint_age} stratum.
#'
#' @source Carey et al. (2013), "mortality associations with long-term exposure
#'   to outdoor air pollution in a national English cohort" (PMID 23590261), as
#'   used by the Global Burden of Disease risk-factor analysis.
"O3_CR_Lookup_Table"
