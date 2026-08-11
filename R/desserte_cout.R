# Epic « conception de desserte » (Lots 14-18, docs/ROADMAP-desserte.md).
# Lot 14 : surface de cout de CONSTRUCTION d'une nouvelle desserte. Structure
# additive inspiree du « Cost Raster Creator » de ForestRoadNetwork (Klemet,
# GPL v3) ; formulation R propre (cf. specs/014-cout-construction.md, Attribution).

#' Build the construction-cost surface of a new forest road
#'
#' Produces the per-cell **construction cost** (monetary, €/m of road crossing the
#' cell) that the route solver (Lot 15) will propagate, plus a **crossability**
#' layer (`NA`/`FALSE` = the solver must not traverse the cell). The cost is
#' additive: base cost + slope surcharge (by class) + soil surcharge + point
#' crossings (bridge over water bodies, culvert over streams) + a free
#' additional surcharge. Only the base cost is required; every optional layer that
#' is absent contributes nothing (never errors).
#'
#' @param pre A `foretaccess_preprocessing` object (Lot 1): supplies the DEM grid,
#'   terrain slope (`slope_pct`) and the complete-obstacle mask.
#' @param config A `foretaccess_config`; the cost scale lives in
#'   `config$desserte$cout`.
#' @param plan_eau Optional water-body layer (bridges): `SpatRaster` (`> 0` = water)
#'   or `sf` polygons. Cells receive `cout_pont_m`.
#' @param cours_eau Optional stream layer (culverts): `SpatRaster` (metres of stream
#'   per cell, or `> 0`) or `sf` lines. Cells receive `cout_buse_m` scaled by the
#'   crossed fraction.
#' @param sol Optional soil-class layer (`SpatRaster` of class codes or `sf`
#'   polygons with a `classe` field); mapped through `config$desserte$cout$bareme_sol`.
#' @param interdit Optional forbidden-area layer (`SpatRaster` `> 0` or `sf`
#'   polygons): those cells are not crossable.
#' @param surcout Optional free additional surcharge (`SpatRaster`, €/m).
#' @param methode_pente How the slope term is priced: `"bareme"` (default, the
#'   Lot 14 step function) or `"terrassement"` (spec 029, cut-and-fill volumes
#'   priced per cubic metre -- continuous, and sensitive to platform width).
#'   The default is deliberate: switching the slope term changes every route the
#'   solver produces, so a side-by-side run on a real massif must come first.
#' @param largeur_m Target platform width (m), used by
#'   `methode_pente = "terrassement"` only. Default 4.
#' @param pente_max_pct Constructibility ceiling: cells at or above this terrain
#'   slope (percent) are not crossable, **whichever pricing method is used**.
#'   `NULL` (default) takes the ceiling the step function already implies -- the
#'   first class priced `Inf`, i.e. 60 % with the shipped scale -- so that
#'   switching method changes only the pricing. `Inf` gives the earthwork model
#'   its full reach, which on the DABO bench opens 5 % of the massif between
#'   60 % and 100 % of slope. That is a separate decision from the pricing one,
#'   and it is meant to be taken separately.
#' @return A `foretaccess_cout_construction` object: a list of two `SpatRaster`
#'   aligned on the DEM — `cout` (€/m, `NA` outside the crossable zone) and
#'   `franchissable` (logical).
#' @export
surface_cout_construction <- function(pre, config = foretaccess_config(),
                                       plan_eau = NULL, cours_eau = NULL,
                                       sol = NULL, interdit = NULL,
                                       surcout = NULL,
                                       methode_pente = c("bareme", "terrassement"),
                                       largeur_m = 4, pente_max_pct = NULL) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  methode_pente <- match.arg(methode_pente)
  validate_config(config)
  co <- config$desserte$cout
  grille <- pre$mnt

  # 1. Cout de base : constant sur la grille, NA hors MNT.
  cout <- terra::mask(terra::setValues(grille, co$cout_base_m), grille)

  # 2. Terme de pente. Deux methodes, meme place dans la somme.
  #
  #    "bareme" (defaut) : classes [min, max) -> surcout. Un surcout Inf (pente
  #    non constructible) rend la cellule infranchissable (etape 8).
  #
  #    "terrassement" (spec 029) : volume de deblai/remblai chiffre au m3,
  #    continu et sensible a la largeur de plateforme. Le defaut reste le bareme
  #    DELIBEREMENT : changer ce terme change tous les traces produits, et la
  #    comparaison des deux methodes sur un massif reel doit preceder la
  #    bascule.
  # PLAFOND DE CONSTRUCTIBILITE, commun aux deux methodes. Sans lui, choisir la
  # methode deciderait AUSSI du plafond, sans le dire : le bareme s'arrete a
  # 60 % par sa derniere classe, le terrassement va jusqu'a la pente du talus de
  # deblai (100 % au defaut) et rendait donc constructibles 5 % du massif de
  # plus sur le banc DABO. Deux decisions distinctes -- « comment tarifer » et
  # « jusqu'ou construire » -- qui ne doivent pas etre prises d'un seul geste.
  #
  # Par defaut on reprend le plafond IMPLICITE du bareme, de sorte que changer
  # de methode ne change que la tarification. `pente_max_pct = Inf` rend au
  # terrassement toute sa portee -- explicitement.
  if (is.null(pente_max_pct)) {
    inf <- is.infinite(co$bareme_pente$surcout)
    pente_max_pct <- if (any(inf)) min(co$bareme_pente$min[inf]) else Inf
  }
  checkmate::assert_number(pente_max_pct, lower = 0)

  s_pente <- if (identical(methode_pente, "terrassement")) {
    cout_terrassement(pre$slope_pct, largeur_m = largeur_m, config = config)
  } else {
    rcl <- as.matrix(co$bareme_pente[, c("min", "max", "surcout")])
    terra::classify(pre$slope_pct, rcl, right = FALSE)
  }
  # Le terrassement rend NA la ou la construction est impossible, la ou le
  # bareme rend Inf. Les deux doivent aboutir au meme endroit -- une cellule
  # infranchissable -- alors qu'un NA se propagerait en silence dans la somme.
  if (identical(methode_pente, "terrassement")) {
    s_pente <- terra::ifel(is.na(s_pente) & !is.na(grille), Inf, s_pente)
  }
  # Le plafond ferme la cellule, quelle que soit la methode.
  if (is.finite(pente_max_pct)) {
    s_pente <- terra::ifel(pre$slope_pct >= pente_max_pct, Inf, s_pente)
  }
  cout <- cout + s_pente

  # 3. Surcout de sol : table classe -> surcout (optionnel).
  if (!is.null(sol) && !is.null(co$bareme_sol)) {
    sol_r <- .desserte_aligner(sol, grille, field = "classe", method = "near")
    codes <- as.numeric(names(co$bareme_sol))
    rcl_sol <- cbind(codes, as.numeric(unlist(co$bareme_sol)))
    s_sol <- terra::classify(sol_r, rcl_sol, others = 0)
    cout <- cout + terra::ifel(is.na(s_sol), 0, s_sol)
  }

  # 4. Franchissement surfacique (pont) : cout ponctuel sur les cellules d'eau.
  masque_pont <- .desserte_couche_masque(plan_eau, grille)
  if (!is.null(masque_pont)) {
    cout <- cout + terra::ifel(masque_pont, co$cout_pont_m, 0)
  }

  # 5. Franchissement lineaire (buse) : proportionnel a la longueur de cours d'eau
  #    dans la cellule (densite = longueur / cote de cellule, plafonnee a 1).
  long_buse <- .desserte_couche_longueur(cours_eau, grille)
  if (!is.null(long_buse)) {
    res <- terra::res(grille)[1]
    densite <- terra::clamp(long_buse / res, lower = 0, upper = 1, values = TRUE)
    cout <- cout + co$cout_buse_m * densite
  }

  # 6. Surcout additionnel libre (EUR/m).
  s_add <- .desserte_couche_valeur(surcout, grille)
  if (!is.null(s_add)) {
    cout <- cout + terra::ifel(is.na(s_add), 0, s_add)
  }

  # 7. Zones interdites et obstacles complets.
  masque_interdit <- .desserte_couche_masque(interdit, grille)
  obst <- pre$obstacles_complets_mask > 0

  # 8. Franchissabilite = dans la grille, hors obstacle/interdit, cout fini.
  #    (Un cout NA ou Inf -- pente non constructible -- ferme la cellule.)
  mauvais <- is.na(cout) | (cout == Inf)
  franch <- !is.na(grille) & !obst & !mauvais
  if (!is.null(masque_interdit)) franch <- franch & !masque_interdit
  names(franch) <- "franchissable"

  # Le cout n'a de sens que sur les cellules franchissables.
  cout <- terra::mask(cout, franch, maskvalues = c(FALSE, NA), updatevalue = NA)
  names(cout) <- "cout"

  structure(
    list(cout = cout, franchissable = franch, config = config),
    class = "foretaccess_cout_construction"
  )
}

# --- Coercions de couches optionnelles vers la grille du MNT -----------------

# Meme grille (emprise + resolution) ? Evite un resample inutile qui perdrait les
# niveaux d'un raster categoriel.
.desserte_meme_grille <- function(x, grille) {
  isTRUE(all.equal(as.vector(terra::ext(x)), as.vector(terra::ext(grille)))) &&
    isTRUE(all.equal(terra::res(x), terra::res(grille)))
}

# Aligne un SpatRaster sur la grille (resample si besoin).
.desserte_aligner_raster <- function(x, grille, method = "near") {
  if (.desserte_meme_grille(x, grille)) x else terra::resample(x, grille, method = method)
}

# SpatRaster (numerique) aligne, quelle que soit l'entree (raster ou sf).
.desserte_aligner <- function(x, grille, field = NULL, method = "near") {
  if (inherits(x, "SpatRaster")) {
    return(.desserte_aligner_raster(x, grille, method = method))
  }
  if (inherits(x, c("sf", "sfc"))) {
    v <- terra::vect(x)
    return(terra::rasterize(v, grille, field = field %||% 1))
  }
  cli::cli_abort("Couche de desserte non reconnue : {.cls SpatRaster} ou {.cls sf} attendu.")
}

# Masque logique : TRUE la ou la couche est presente (> 0 / recouvrement).
.desserte_couche_masque <- function(x, grille) {
  if (is.null(x)) return(NULL)
  if (inherits(x, c("sf", "sfc"))) {
    r <- terra::rasterize(terra::vect(x), grille, field = 1, background = 0)
  } else {
    r <- .desserte_aligner_raster(x, grille, method = "near")
  }
  !is.na(r) & r > 0
}

# Longueur (m) de geometries lineaires par cellule (buses).
.desserte_couche_longueur <- function(x, grille) {
  if (is.null(x)) return(NULL)
  if (inherits(x, c("sf", "sfc"))) {
    return(terra::rasterizeGeom(terra::vect(x), grille, fun = "length"))
  }
  r <- .desserte_aligner_raster(x, grille, method = "near")
  terra::ifel(is.na(r), 0, r)
}

# Raster de valeur numerique (EUR/m) aligne.
.desserte_couche_valeur <- function(x, grille) {
  if (is.null(x)) return(NULL)
  .desserte_aligner(x, grille, method = "near")
}

#' @export
print.foretaccess_cout_construction <- function(x, ...) {
  vals <- terra::values(x$cout)
  fr <- terra::values(x$franchissable)
  n_franch <- sum(fr > 0, na.rm = TRUE)
  cli::cli_h1("Surface de cout de construction de desserte")
  cli::cli_text("Grille : {terra::nrow(x$cout)} x {terra::ncol(x$cout)} cellules")
  cli::cli_text("Franchissables : {n_franch} cellules")
  if (any(is.finite(vals))) {
    cli::cli_text("Cout (EUR/m) : min {round(min(vals, na.rm = TRUE), 1)} | \\
                   median {round(stats::median(vals, na.rm = TRUE), 1)} | \\
                   max {round(max(vals, na.rm = TRUE), 1)}")
  }
  invisible(x)
}
