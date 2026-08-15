# Qualification de la desserte par LiDAR HD (spec 021, Lot 19 -- ETAPE 1
# deterministe). La desserte n'est jamais calculee : elle est DECLAREE (BD TOPO),
# et ses erreurs de position (pluri-metriques au GPS/tablette), de largeur (champ
# souvent vide) et d'existence se propagent aux quatre moteurs. `qualifier_desserte()`
# produit une desserte QUALIFIEE -- geometrie relocalisee + largeur mesuree -- a
# partir du LiDAR, CONFORME au contrat d'entree de preprocess() (moteurs et
# non-regression Sylvaccess inchanges). C'est l'etape 1 (~80 % du probleme de
# qualite d'intrant) ; les etapes 2+ (canaux RVT portes en Rust, CNN de detection
# des pistes absentes de la BD TOPO) sont des jalons de recherche a venir (spec 021
# sec.5-7, J3-J5), conditionnes a la verite terrain DESSOPT.

#' Qualify a declared road network with airborne LiDAR (spec 021, step 1)
#'
#' Turns a **declared** BD TOPO road network into a **qualified** one, using
#' airborne LiDAR: the geometry is **relocated** onto the LiDAR-detected
#' centerline and the **width** is filled from the LiDAR measurement (the BD TOPO
#' `largeur` field is usually empty). This addresses the weakest link of the
#' pipeline -- the desserte is never computed, only imported, so its position and
#' width errors propagate untouched into all four engines. The output conforms to
#' [preprocess()]'s input contract, so engines and the Sylvaccess non-regression
#' are **unchanged**.
#'
#' @details
#' **Deterministic step 1 (spec 021).** A thin post-processing over
#' [acquire_desserte_lidar()] (which wraps dessertR's `dsr_measure()`): the engine
#' *corrects* an existing map, it does **not** detect roads absent from BD TOPO --
#' those stay absent. Detecting missing tracks is step 2 (a CNN on RVT-derived
#' channels, spec 021 sec.5), a research milestone not implemented here.
#'
#' **Requires a DTM >= 1 m** (see [acquire_desserte_lidar()]). Without dessertR, it
#' falls back to **NDP 0** -- the network is returned unchanged (no relocation,
#' width left as-is) and a message says qualification was inoperative.
#'
#' **State semantics are not ground-truthed on French data.** dessertR is
#' calibrated on BD TOPO / IGN LiDAR HD, but on French pistes a worst-state
#' segment may still be *degraded-but-real*, not *gone*. Dropping segments by
#' state is therefore **opt-in** (`retirer_disparues = FALSE` by default) until a
#' French reference (DESSOPT) quantifies the mapping.
#'
#' @param desserte Declared road network: path or `sf` of lines (the output of
#'   [acquire_desserte()]). Must carry the `classe` field preprocess() expects.
#' @param las_source Airborne LiDAR (see [acquire_desserte_lidar()]).
#' @param mnt Digital terrain model (**1 m or finer**). See
#'   [acquire_desserte_lidar()].
#' @param crs Target EPSG code. Default 2154.
#' @param cache_dir Directory for the measurement cache. Default `tempdir()`.
#' @param dtm_res Resolution (m) of the reference grid built from `mnt`. Default 1.
#' @param mnh Canopy height model for the dessertR surface channel. See
#'   [acquire_desserte_lidar()].
#' @param moteur LiDAR engine passed to [acquire_desserte_lidar()]: `"auto"`
#'   (default) or `"dessertr"`. `"alsroads"` is an error since v1.27.0.
#' @param retirer_disparues Drop segments whose measured state marks them gone
#'   (existence qualification)? Default `FALSE` -- opt-in. Unmeasured segments
#'   (state `NA`) are **never** dropped.
#' @param etats_disparus dessertR state labels deemed gone when
#'   `retirer_disparues = TRUE`. Default `c("abandonnee", "hors_route")`.
#' @param etat_disparue Fallback on the integer `etat_classe`: value at/beyond
#'   which a segment is gone. Used only when the `etat_dessertr` label is absent
#'   (NDP 0, or a state raster that could not be built). Default `4L`.
#' @param retirer_inaptes_grumier Drop segments **unfit for timber trucks**
#'   (`apte_grumier == FALSE`, dessertR trafficability)? Default `FALSE` -- opt-in.
#'   Unmeasured segments are never dropped.
#' @return An `sf` conforming to [acquire_desserte()] (fields `classe`, `largeur`,
#'   geometry) with the LiDAR provenance columns of [acquire_desserte_lidar()]
#'   kept as extras, and a `largeur` filled from the measured drivable width where
#'   available. Attributes: `ndp` (`0L`/`1L`) and `qualifiee` (`TRUE`), plus a
#'   per-row `qualifiee` column carrying the same mark. The **column** is what
#'   `reseau_desserte()` checks (CA-28.4), because it survives subsetting and the
#'   merge with the declared BD TOPO network, whereas the layer attribute does not.
#' @seealso [acquire_desserte_lidar()] (the underlying measurement),
#'   [acquire_desserte()] (the declared input), [preprocess()] (the consumer).
#' @export
#' @examples
#' \dontrun{
#' des  <- acquire_desserte(aoi)                       # declaree (BD TOPO)
#' desq <- qualifier_desserte(des, "cache/lidar_nuage", mnt) # relocalisee + largeur
#' pre  <- preprocess(mnt = mnt, desserte = desq, foret = foret)
#' }
qualifier_desserte <- function(desserte, las_source, mnt, mnh = NULL,
                               moteur = c("auto", "dessertr"),
                               crs = 2154, cache_dir = tempdir(), dtm_res = 1,
                               retirer_disparues = FALSE,
                               etats_disparus = c("abandonnee", "hors_route"),
                               etat_disparue = 4L,
                               retirer_inaptes_grumier = FALSE) {
  dl <- acquire_desserte_lidar(
    desserte, las_source, mnt, mnh = mnh, moteur = moteur,
    crs = crs, cache_dir = cache_dir, dtm_res = dtm_res
  )
  ndp <- attr(dl, "ndp")

  if (identical(ndp, 0L)) {
    cli::cli_inform(c(
      "!" = "Qualification inoperante ({.strong NDP 0}, pas de LiDAR) :
             desserte declaree renvoyee telle quelle (ni relocalisation ni largeur)."
    ))
    attr(dl, "qualifiee") <- TRUE
    dl$qualifiee <- TRUE
    return(dl)
  }

  # nocov start : chemin NDP 1 (dessertR installe, hors CI ; Phase B).
  # Remplir la largeur (contrat preprocess/DFCI) depuis la largeur carrossable
  # mesuree ; conserver la valeur BD TOPO la ou le LiDAR n'a pas mesure.
  n_largeur <- 0L
  if ("largeur" %in% names(dl)) {
    mesuree <- dl$largeur_carrossable_m
    a_remplir <- !is.na(mesuree)
    dl$largeur[a_remplir] <- mesuree[a_remplir]
    n_largeur <- sum(a_remplir)
  }

  # Qualification d'EXISTENCE (opt-in). Critere par LIBELLE d'etat dessertR
  # (`etat_dessertr` in `etats_disparus`) ; repli sur le seuil entier
  # (`etat_classe >= etat_disparue`) si le libelle est absent. Ne JAMAIS retirer un
  # troncon non mesure (etat NA) -- absence de mesure != disparu.
  n_retire <- 0L
  if (isTRUE(retirer_disparues)) {
    disparu <- if ("etat_dessertr" %in% names(dl) && any(!is.na(dl$etat_dessertr))) {
      !is.na(dl$etat_dessertr) & dl$etat_dessertr %in% etats_disparus
    } else {
      !is.na(dl$etat_classe) & dl$etat_classe >= etat_disparue
    }
    n_retire <- sum(disparu)
    dl <- dl[!disparu, ]
  }

  # Qualification de PRATICABILITE (opt-in, dessertR) : retirer les troncons
  # INAPTES au grumier (apte_grumier == FALSE). Non mesures (NA) jamais retires.
  n_inapte <- 0L
  if (isTRUE(retirer_inaptes_grumier) && "apte_grumier" %in% names(dl)) {
    inapte <- !is.na(dl$apte_grumier) & !dl$apte_grumier
    n_inapte <- sum(inapte)
    dl <- dl[!inapte, ]
  }

  cli::cli_inform(c(
    "v" = "Desserte qualifiee ({.strong NDP 1}, moteur {attr(dl, 'moteur')}) :
           {sum(!is.na(dl$largeur_carrossable_m))}/{nrow(dl)} troncon{?s} relocalise{?s}
           et mesure{?s}, {n_largeur} largeur{?s} renseignee{?s}{cli::qty(n_retire)}{?/,
           {n_retire} disparu{?s} retire{?s}}{cli::qty(n_inapte)}{?/, {n_inapte} inapte{?s}
           grumier retire{?s}}."
  ))
  attr(dl, "qualifiee") <- TRUE
  dl$qualifiee <- TRUE
  dl
  # nocov end
}
