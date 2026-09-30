# ── Uncertainty and domain-aggregation helpers ──────────────────────────
#
# The interval reported by Mortality(uncertain = TRUE) is a *range* built from
# the published quantiles of the concentration-response function: the same
# low/high tables are applied to every grid cell, the resulting per-cell
# burdens are summed, and those sums form the two ends of the interval.
#
# Why a range rather than a sum of squared sensitivities: the CRF is a single
# object shared by every grid cell, so its uncertainty is common-mode and does
# not average out as the domain grows.  With one shared parameter the
# quantiles of the total are exactly the total evaluated at the parameter
# quantiles, which is what summing the per-cell ranges computes.  A
# first-order propagation sigma^2 = sum(Sensi^2) instead assumed the
# perturbations were independent between cells and therefore shrank the CRF
# term roughly like 1/sqrt(n_cells); it was removed in favour of the range.
#
# The exposure chain (conc_uncert) is treated the same way: the whole
# analysis is re-run with every concentration scaled by 1 +/- conc_uncert%,
# and the resulting per-cell burdens are summed.  When both chains are
# active the reported interval is their union -- the most extreme low and
# high -- which is the range spanned by the two perturbations.

# Sum over the value columns of each row of a Mortality() result.
.row_total <- function(x, keys) {
  vals <- setdiff(names(x), keys)
  vals <- vals[vapply(x[vals], is.numeric, logical(1))]
  if (length(vals) == 0) {
    return(rep(0, nrow(x)))
  }
  rowSums(as.matrix(x[vals]), na.rm = TRUE)
}

# Re-render an exposure key after scaling, keeping it joinable.
.scale_conc <- function(conc, factor, dgt) {
  conc$conc <- matchable(as.numeric(conc$conc) * factor, dgt = dgt)
  conc
}

# Keys + row total for one grid-level result.
.total_frame <- function(grid, keys) {
  out <- grid[keys]
  out$.total <- .row_total(grid, keys)
  out
}

# Collapse several per-cell totals into one side of the range, either per
# cell (aggregate = FALSE) or summed within the aggregation keys.
.range_sum <- function(frames, keys, side = c("low", "up"), aggregate = TRUE) {
  side <- match.arg(side)
  pick_fn <- if (side == "low") pmin else pmax
  totals <- Reduce(
    function(a, b) pick_fn(a, b),
    lapply(frames, function(f) f$.total)
  )

  if (!aggregate) {
    return(totals)
  }
  if (length(keys) == 0) {
    return(sum(totals, na.rm = TRUE))
  }

  out <- frames[[1]][keys]
  out$.total <- totals
  out |>
    group_by(pick(all_of(keys))) |>
    summarise(.total = sum(.total, na.rm = TRUE), .groups = "drop")
}

# Attach CI_LOW / CI_UP to an aggregated result. `group_keys` are the columns
# the result was aggregated on; an empty vector means the whole field.
.attach_range <- function(out, lower, upper, group_keys) {
  lo <- .range_sum(lower, group_keys, "low") |> rename(CI_LOW = .total)
  hi <- .range_sum(upper, group_keys, "up") |> rename(CI_UP = .total)

  if (length(group_keys) == 0) {
    out$CI_LOW <- lo$CI_LOW
    out$CI_UP  <- hi$CI_UP
    return(out)
  }
  out |>
    left_join(lo, by = group_keys) |>
    left_join(hi, by = group_keys)
}

# Population-weighted exposure by domain, reported alongside aggregated
# results because it is the exposure metric attributable-burden papers quote.
.domain_pwe <- function(field, conc_real, pop, lvl) {
  pwe <- list(field, conc_real, pop) |>
    reduce(left_join) |>
    na.omit()

  if (length(lvl) == 0) {
    return(data.frame(conc_pwe = weighted.mean(as.numeric(pwe$conc), pwe$pop)))
  }

  pwe |>
    group_by(pick(all_of(lvl))) |>
    summarise(conc_pwe = weighted.mean(as.numeric(conc), pop), .groups = "drop")
}
