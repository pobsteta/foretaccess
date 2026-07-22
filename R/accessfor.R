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

#' Compare debarking classes against the IGN ACCESSFOR layer
#'
#' Confronts a [classes_debardage()] raster with the IGN **ACCESSFOR** reference
#' (skidder or porteur), on the grid of the raster itself. ACCESSFOR is
#' rasterised in **nearest-neighbour** (a class code must never be interpolated),
#' mapped onto our value scheme via [accessfor_correspondance()], and the two are
#' cross-tabulated **only on the intersection of the forest masks** -- the three
#' masks (ours, ACCESSFOR, ACCESSFOR-V3) differ, so any global figure that
#' ignored this would be dominated by a masking artefact.
#'
#' @section Lecture:
#' The robust number is the **aggregated** agreement (accessible vs not): a strong
#' disagreement on the far bands is expected (machine parameters, reference road
#' network), while an accessible-vs-inaccessible flip is a signal to investigate.
#' The `inexploitable` class only appears if `classes_debardage()` was given `pre`;
#' its ACCESSFOR threshold (slope) is not published, so a disagreement there is a
#' parameter artefact, not a defect.
#'
#' @param cl A categorical `classes_debardage()` raster (values `1..k+3`).
#' @param accessfor An `sf`/`SpatVector` of ACCESSFOR polygons carrying an integer
#'   class column. Must share the CRS of `cl` (no implicit reprojection, ADR-004).
#' @param champ Name of the ACCESSFOR class column. Default `"class"`.
#' @param config The `foretaccess_config` whose bands define the crosswalk.
#'   Default [foretaccess_config()].
#' @return An object of class `foretaccess_accessfor_compare`: `matrice` (area in
#'   ha, our class in rows x ACCESSFOR class in cols, on the common mask),
#'   `accord_global` (share of area on the diagonal), `accord_agrege`
#'   (accessible/non-accessible 2x2 agreement), `surface_ha` (common, and each
#'   mask-only area excluded from the comparison), and `config`.
#' @seealso [accessfor_correspondance()], [classes_debardage()].
#' @export
comparer_accessfor <- function(cl, accessfor, champ = "class",
                               config = foretaccess_config()) {
  checkmate::assert_class(cl, "SpatRaster")
  checkmate::assert_string(champ)
  co <- accessfor_correspondance(config)

  af <- .as_vector(accessfor, "accessfor")
  if (is.na(sf::st_crs(af)) || sf::st_crs(af) != sf::st_crs(terra::crs(cl))) {
    cli::cli_abort(c(
      "Le CRS de {.arg accessfor} doit egaler celui de {.arg cl}.",
      "i" = "Aucune reprojection implicite : reprojeter en amont (ADR-004)."
    ))
  }
  if (!champ %in% names(af)) {
    cli::cli_abort("{.arg accessfor} n'a pas de champ {.field {champ}}.")
  }
  af[[champ]] <- as.integer(af[[champ]])
  af <- af[!is.na(af[[champ]]), ]

  # Rasterisation NEAREST : un code de classe ne s'interpole pas. On verifie
  # ensuite que l'ensemble des valeurs obtenues est bien inclus dans les codes
  # d'entree -- sinon la rasterisation a fabrique une classe qui n'existe pas.
  afr <- terra::rasterize(terra::vect(af), cl, field = champ)
  vals_out <- stats::na.omit(unique(terra::values(afr)[, 1]))
  vals_in <- sort(unique(af[[champ]]))
  if (!all(vals_out %in% vals_in)) {
    cli::cli_abort(c(
      "La rasterisation d'ACCESSFOR a produit des codes absents de l'entree.",
      "x" = "Obtenus hors entree : {.val {setdiff(vals_out, vals_in)}}.",
      "i" = "La rasterisation doit etre en plus proche voisin (near)."
    ))
  }

  af_class <- as.integer(terra::values(afr)[, 1])
  notre <- as.integer(terra::values(cl)[, 1])

  # Correspondance code ACCESSFOR -> notre valeur (schema classes_debardage).
  map <- stats::setNames(co$fa_value, co$accessfor_class)
  af_notre <- unname(map[as.character(af_class)])

  # Masques. `hors_foret` = derniere valeur (k+3). ACCESSFOR present = non-NA.
  hf <- max(co$fa_value)
  notre_foret <- !is.na(notre) & notre != hf
  af_present <- !is.na(af_class)
  commun <- notre_foret & af_present

  cell_ha <- prod(terra::res(cl)) / 10000

  # Matrice de confusion (ha) sur l'intersection des masques.
  etq <- co$fa_classe[co$fa_value %in% unique(c(notre[commun], af_notre[commun]))]
  lev <- co$fa_value[co$fa_classe %in% etq]
  fx <- factor(notre[commun], levels = lev, labels = co$fa_classe[match(lev, co$fa_value)])
  fy <- factor(af_notre[commun], levels = lev, labels = co$fa_classe[match(lev, co$fa_value)])
  matrice <- table(foretaccess = fx, accessfor = fy) * cell_ha

  diago <- sum(diag(matrice))
  total <- sum(matrice)
  accord_global <- if (total > 0) diago / total else NA_real_

  # Accord agrege : accessible (bandes 1..k) vs non-accessible (inaccessible +
  # inexploitable). Le chiffre robuste.
  bande <- seq_along(config$skidder$classes_distance_m)
  # Facteur a niveaux FIXES : sinon deux cotes a niveau unique different donnent
  # une table 1x1 dont la diagonale vaut tout (faux accord de 100 %).
  agr <- function(v) {
    factor(ifelse(v %in% bande, "accessible", "non_accessible"),
      levels = c("accessible", "non_accessible"))
  }
  m_agr <- table(
    foretaccess = agr(notre[commun]), accessfor = agr(af_notre[commun])
  ) * cell_ha
  accord_agrege <- if (sum(m_agr) > 0) sum(diag(m_agr)) / sum(m_agr) else NA_real_

  structure(
    list(
      matrice = matrice,
      matrice_agrege = m_agr,
      accord_global = accord_global,
      accord_agrege = accord_agrege,
      surface_ha = list(
        commun = total,
        notre_seul = sum(notre_foret & !af_present) * cell_ha, # foret pour nous, hors ACCESSFOR
        accessfor_seul = sum(!notre_foret & af_present & !is.na(notre)) * cell_ha
      ),
      config = config
    ),
    class = "foretaccess_accessfor_compare"
  )
}

#' @export
print.foretaccess_accessfor_compare <- function(x, ...) {
  s <- x$surface_ha
  cli::cli_inform(c(
    "Comparaison ACCESSFOR (IGN) vs classes_debardage()",
    "*" = "accord global (9 classes) : {.strong {round(100 * x$accord_global, 1)}%}",
    "*" = "accord agrege (accessible/non) : {.strong {round(100 * x$accord_agrege, 1)}%}",
    "*" = "surface comparee : {round(s$commun, 1)} ha ; exclue -- foret hors
           ACCESSFOR : {round(s$notre_seul, 1)} ha ; ACCESSFOR hors notre foret :
           {round(s$accessfor_seul, 1)} ha"
  ))
  invisible(x)
}
