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
#' [acquire_desserte_lidar()] (which wraps `ALSroads::measure_road`): ALSroads
#' *corrects* an existing map, it does **not** detect roads absent from BD TOPO --
#' those stay absent. Detecting missing tracks is step 2 (a CNN on RVT-derived
#' channels, spec 021 sec.5), a research milestone not implemented here.
#'
#' **Requires a DTM >= 1 m** (see [acquire_desserte_lidar()]): a coarser DTM is
#' auto-refined from ground points. Without lidR/ALSroads, it falls back to
#' **NDP 0** -- the network is returned unchanged (no relocation, width left as-is)
#' and a message says qualification was inoperative.
#'
#' **State semantics are not ground-truthed on French data.** ALSroads' `CLASS`
#' (road state) is calibrated on boreal roads; on French pistes a worst-class
#' segment may be *degraded-but-real*, not *gone*. Dropping segments by state is
#' therefore **opt-in** (`retirer_disparues = FALSE` by default) until a French
#' reference (DESSOPT) quantifies the mapping.
#'
#' @param desserte Declared road network: path or `sf` of lines (the output of
#'   [acquire_desserte()]). Must carry the `classe` field preprocess() expects.
#' @param las_source Airborne LiDAR (see [acquire_desserte_lidar()]).
#' @param mnt Digital terrain model (>= 1 m; refined from ground points if
#'   coarser). See [acquire_desserte_lidar()].
#' @param crs Target EPSG code. Default 2154.
#' @param cache_dir Directory for the measurement cache. Default `tempdir()`.
#' @param dtm_res Resolution (m) of the DTM derived when `mnt` is coarse. Default 1.
#' @param retirer_disparues Drop segments whose measured state is at/beyond
#'   `etat_disparue` (existence qualification)? Default `FALSE` -- opt-in, as the
#'   French state semantics are not yet ground-truthed. Unmeasured segments
#'   (`etat_classe` `NA`) are **never** dropped.
#' @param etat_disparue ALSroads `CLASS` at/beyond which a segment is deemed gone
#'   when `retirer_disparues = TRUE`. Default `4L` (worst state).
#' @return An `sf` conforming to [acquire_desserte()] (fields `classe`, `largeur`,
#'   geometry) with the LiDAR provenance columns of [acquire_desserte_lidar()]
#'   kept as extras, and a `largeur` filled from the measured drivable width where
#'   available. Attributes: `ndp` (`0L`/`1L`) and `qualifiee` (`TRUE`).
#' @seealso [acquire_desserte_lidar()] (the underlying measurement),
#'   [acquire_desserte()] (the declared input), [preprocess()] (the consumer).
#' @export
#' @examples
#' \dontrun{
#' des  <- acquire_desserte(aoi)                       # declaree (BD TOPO)
#' desq <- qualifier_desserte(des, "cache/lidar_nuage", mnt) # relocalisee + largeur
#' pre  <- preprocess(mnt = mnt, desserte = desq, foret = foret)
#' }
qualifier_desserte <- function(desserte, las_source, mnt, crs = 2154,
                               cache_dir = tempdir(), dtm_res = 1,
                               retirer_disparues = FALSE, etat_disparue = 4L) {
  dl <- acquire_desserte_lidar(
    desserte, las_source, mnt,
    crs = crs, cache_dir = cache_dir, dtm_res = dtm_res
  )
  ndp <- attr(dl, "ndp")

  if (identical(ndp, 0L)) {
    cli::cli_inform(c(
      "!" = "Qualification inoperante ({.strong NDP 0}, pas de LiDAR/ALSroads) :
             desserte declaree renvoyee telle quelle (ni relocalisation ni largeur)."
    ))
    attr(dl, "qualifiee") <- TRUE
    return(dl)
  }

  # nocov start : chemin NDP 1 (ALSroads installe, hors CI ; valide en Phase B).
  # Remplir la largeur (contrat preprocess/DFCI) depuis la largeur carrossable
  # mesuree ; conserver la valeur BD TOPO la ou le LiDAR n'a pas mesure.
  n_largeur <- 0L
  if ("largeur" %in% names(dl)) {
    mesuree <- dl$largeur_carrossable_m
    a_remplir <- !is.na(mesuree)
    dl$largeur[a_remplir] <- mesuree[a_remplir]
    n_largeur <- sum(a_remplir)
  }

  # Qualification d'EXISTENCE (opt-in) : retirer les troncons d'etat >= seuil.
  # Ne jamais retirer un troncon NON mesure (etat NA) -- absence de mesure != disparu.
  n_retire <- 0L
  if (isTRUE(retirer_disparues)) {
    disparu <- !is.na(dl$etat_classe) & dl$etat_classe >= etat_disparue
    n_retire <- sum(disparu)
    dl <- dl[!disparu, ]
  }

  cli::cli_inform(c(
    "v" = "Desserte qualifiee ({.strong NDP 1}) : {sum(!is.na(dl$largeur_carrossable_m))}/{nrow(dl)}
           troncon{?s} relocalise{?s} et mesure{?s}, {n_largeur} largeur{?s} renseignee{?s}
           {cli::qty(n_retire)}{?/, {n_retire} disparu{?s} retire{?s}}."
  ))
  attr(dl, "qualifiee") <- TRUE
  dl
  # nocov end
}
