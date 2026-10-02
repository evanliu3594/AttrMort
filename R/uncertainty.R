# ── Uncertainty and domain-aggregation helpers ──────────────────────────
#
# The interval reported by mortality(uncertain = TRUE) is a *range* built from
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

# Sum over the value columns of each row of a mortality() result.
.row_total <- function(x, keys) {
  vals <- setdiff(names(x), keys)
  vals <- vals[map_lgl(x[vals], is.numeric)]
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

  # Every chain is matched to the same key space before the endpoints are
  # taken. A chain can be short -- a perturbed concentration that leaves the
  # C-R lookup, a domain the group does not cover -- and comparing the raw
  # vectors would then hand one cell's value to another, because the shorter
  # vector is recycled.
  # `keys` are the columns the caller groups *by* (`location`, say); the
  # chains are matched on every key they carry, which is the grid.
  align_keys <- setdiff(names(frames[[1L]]), ".total")
  values <- if (length(align_keys) == 0) {
    map(frames, ".total")
  } else {
    if (is.null(keys_frame)) {
      keys_frame <- frames |>
        map(function(f) f[align_keys]) |>
        reduce(function(a, b) unique(rbind(a, b)))
    }
    map(frames, function(f) left_join(keys_frame, f[c(align_keys, ".total")],
                                      by = align_keys)$.total)
  }
  totals <- reduce(values, pick_fn)

  # A cell no chain could compute is reported rather than filled in: the
  # interval is undefined there, not equal to another cell's.
  holes <- sum(is.na(totals))
  if (holes > 0) {
    cli::cli_warn(str_c(
      holes, " cell(s) have no interval: at least one chain could not compute ",
      "them (a concentration outside the C-R lookup, or data the chain does ",
      "not cover)."
    ))
  }

  if (!aggregate) {
    return(totals)
  }
  if (length(keys) == 0) {

  # No grouping keys means the whole field collapses to one row. Keep the
  # `.total` column even then, because `.attach_range()` renames it like any
  # other aggregate instead of accepting a bare number.
    return(tibble(.total = sum(totals, na.rm = TRUE)))
  }

  if (is.null(keys_frame)) {
    keys_frame <- frames[[1L]][keys]
  }
  out <- keys_frame
  out$.total <- totals
  out |>
    group_by(pick(all_of(keys))) |>
    summarise(.total = sum(.total, na.rm = TRUE), .groups = "drop")
}

# Attach CI_LOW / CI_UP to an aggregated result. `group_keys` are the columns
# the result was aggregated on; an empty vector means the whole field.
.attach_range <- function(out, lower, upper, group_keys) {
  lo <- .range_sum(lower, group_keys, "low") |> rename(CI_LOW = .total)
  # No baseline is passed: the chains are grid-level while `out` is already
  # aggregated, so the key space to align on is theirs.
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
    reduce(.left_join_common) |>
    drop_na()

  if (length(lvl) == 0) {
    return(tibble(conc_pwe = weighted.mean(as.numeric(pwe$conc), pwe$pop)))
  }

  pwe |>
    group_by(pick(all_of(lvl))) |>
    summarise(conc_pwe = weighted.mean(as.numeric(conc), pop), .groups = "drop")
}
