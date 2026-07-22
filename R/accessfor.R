# Correspondance avec la couche ACCESSFOR de l'IGN (validation externe).
#
# L'IGN publie en WFS une accessibilite forestiere nationale (projet ACCESSFOR,
# edition 2025-01-01) : couches polygonales `acces_skidder` / `acces_porteur`,
# attribut entier `class` + libelle `cat`. Sur le departement cible (48,
# Chastel-Nouvel), le domaine observe est TERME POUR TERME celui de
# `classes_debardage()` -- meme filiation Sylvaccess. Cette table fige la
# correspondance `class` ACCESSFOR <-> valeur `classes_debardage()`, verifiee au
# WFS le 2026-07-22 (cf. data-raw/accessfor.R). On compare sur `class` (entier),
# JAMAIS sur `cat` (libelle) : les accents et la ponctuation varient.

# Domaine ACCESSFOR observe (dep 48, skidder ET porteur). Les bandes 3..8
# coincident avec les defauts Sylvaccess ; 1 = inaccessible, 2 = pente excessive.
.ACCESSFOR_BANDES_M <- c(0, 250, 500, 1000, 1500, 2000)

#' Map the IGN ACCESSFOR classes onto `classes_debardage()`
#'
#' The IGN publishes a national forest-accessibility layer (project **ACCESSFOR**,
#' edition 2025-01-01) over WFS: polygonal `acces_skidder` / `acces_porteur`
#' layers with an integer `class` and a `cat` label. On the target department
#' (48, Chastel-Nouvel) the observed class domain matches [classes_debardage()]
#' band for band -- both descend from Sylvaccess. This function returns the
#' explicit crosswalk so a comparison joins on the **integer** code, never on the
#' label (`cat` carries accents and punctuation that must not be matched on).
#'
#' The ACCESSFOR bands are **frozen** at `0, 250, 500, 1000, 1500, 2000` m (the
#' Sylvaccess defaults). If `config` sets different
#' `skidder$classes_distance_m`, the crosswalk is undefined and the function
#' errors rather than align mismatched bands silently.
#'
#' @section Correspondence:
#' \tabular{lll}{
#'   ACCESSFOR `class` \tab `classes_debardage()` \tab meaning \cr
#'   3, 4, 5, 6, 7, 8 \tab 1, 2, 3, 4, 5, 6 \tab bands 0-250 ... > 2000 m \cr
#'   1 \tab `k+1` \tab inaccessible \cr
#'   2 \tab `k+2` \tab inexploitable (harvest slope exceeded) \cr
#'   -- \tab `k+3` \tab hors_foret (no ACCESSFOR code -- outside its forest mask) \cr
#' }
#' where `k = length(config$skidder$classes_distance_m)` (6 by default). ACCESSFOR
#' has **no** `hors_foret` code: its polygons *are* the forest, so `hors_foret`
#' maps to "outside the ACCESSFOR mask" and is excluded from any comparison.
#'
#' @param config A `foretaccess_config`. Its `skidder$classes_distance_m` must
#'   equal the ACCESSFOR bands. Default [foretaccess_config()].
#' @return A `data.frame` with one row per `classes_debardage()` value:
#'   `fa_value` (integer, the raster code), `fa_classe` (label), `accessfor_class`
#'   (integer ACCESSFOR code, `NA` for `hors_foret`), `accessfor_cat` (indicative
#'   ASCII label -- do not join on it).
#' @seealso [classes_debardage()].
#' @export
#' @examples
#' accessfor_correspondance()
accessfor_correspondance <- function(config = foretaccess_config()) {
  bornes <- config$skidder$classes_distance_m
  attendu <- .ACCESSFOR_BANDES_M
  if (!isTRUE(all.equal(as.numeric(bornes), attendu))) {
    cli::cli_abort(c(
      "Les bandes de {.fn classes_debardage} divergent d'ACCESSFOR.",
      "i" = "ACCESSFOR (edition 2025-01-01) est fige sur {.val {attendu}} m.",
      "x" = "{.code config$skidder$classes_distance_m} = {.val {bornes}}.",
      "i" = "La correspondance n'est definie que pour les defauts Sylvaccess."
    ))
  }
  k <- length(bornes)
  bandes <- c(paste0(bornes[-k], "-", bornes[-1]), paste0("> ", bornes[k]))

  # Libelles ACCESSFOR indicatifs (transliteres ASCII). La jointure se fait sur
  # `accessfor_class`, pas ici : les vrais libelles portent des accents.
  cat_bandes <- paste0("Accessible - Classe de debardage ", seq_len(k), " : ", bandes)

  data.frame(
    fa_value        = c(seq_len(k), k + 1L, k + 2L, k + 3L),
    fa_classe       = c(bandes, "inaccessible", "inexploitable", "hors_foret"),
    accessfor_class = c(seq.int(3L, 2L + k), 1L, 2L, NA_integer_),
    accessfor_cat   = c(
      cat_bandes,
      "Inaccessible",
      "Zone non exploitable (pente trop elevee)",
      NA_character_
    ),
    stringsAsFactors = FALSE
  )
}
