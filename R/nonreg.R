#' Compare une sortie à un oracle de non-régression
#'
#' Cœur du harnais de non-régression (brief §7, ADR-006). Compare une valeur
#' *actuelle* à un *oracle* de référence (sorties Sylvaccess v3.6 figées, ou
#' oracle synthétique au Lot 0) avec des tolérances absolue et relative.
#'
#' Types supportés : vecteurs/matrices numériques et rasters `terra::SpatRaster`.
#' Les `NA` doivent apparaître aux mêmes positions dans les deux objets.
#'
#' @param actual Valeur produite (numérique ou `SpatRaster`).
#' @param oracle Valeur de référence, de même forme que `actual`.
#' @param tol_abs Tolérance absolue (défaut `0`).
#' @param tol_rel Tolérance relative (défaut `1e-6`), rapportée à `abs(oracle)`.
#' @return Une liste de classe `foretaccess_nonreg` : `ok` (logique),
#'   `max_abs`, `max_rel`, `n`, `tol_abs`, `tol_rel`.
#' @export
#' @examples
#' compare_to_oracle(c(1, 2, 3), c(1, 2, 3.0000001), tol_rel = 1e-3)
compare_to_oracle <- function(actual, oracle, tol_abs = 0, tol_rel = 1e-6) {
  checkmate::assert_number(tol_abs, lower = 0)
  checkmate::assert_number(tol_rel, lower = 0)

  a <- .as_numeric_values(actual)
  o <- .as_numeric_values(oracle)

  if (length(a) != length(o)) {
    cli::cli_abort(c(
      "Formes incompatibles entre {.arg actual} et {.arg oracle}.",
      "x" = "{length(a)} valeur{?s} vs {length(o)}."
    ))
  }

  na_a <- is.na(a)
  na_o <- is.na(o)
  if (!identical(na_a, na_o)) {
    cli::cli_abort("Les positions des {.val NA} different entre actual et oracle.")
  }

  keep <- !na_a
  a <- a[keep]
  o <- o[keep]

  abs_diff <- abs(a - o)
  rel_diff <- abs_diff / pmax(abs(o), .Machine$double.eps)

  max_abs <- if (length(abs_diff)) max(abs_diff) else 0
  max_rel <- if (length(rel_diff)) max(rel_diff) else 0

  ok <- all(abs_diff <= tol_abs | rel_diff <= tol_rel)

  structure(
    list(
      ok = ok, max_abs = max_abs, max_rel = max_rel,
      n = length(a), tol_abs = tol_abs, tol_rel = tol_rel
    ),
    class = "foretaccess_nonreg"
  )
}

# Extrait un vecteur numérique d'un objet supporté.
.as_numeric_values <- function(x) {
  if (inherits(x, "SpatRaster")) {
    return(as.numeric(terra::values(x)))
  }
  if (is.data.frame(x)) {
    num <- vapply(x, is.numeric, logical(1))
    return(as.numeric(unlist(x[num], use.names = FALSE)))
  }
  checkmate::assert_numeric(x)
  as.numeric(x)
}

#' @export
print.foretaccess_nonreg <- function(x, ...) {
  status <- if (x$ok) "OK" else "ECHEC"
  cli::cli_inform(c(
    "Non-regression : {status}",
    "*" = "n = {x$n} ; max_abs = {signif(x$max_abs, 4)} ; max_rel = {signif(x$max_rel, 4)}",
    "*" = "tolerances : abs = {x$tol_abs} ; rel = {x$tol_rel}"
  ))
  invisible(x)
}
