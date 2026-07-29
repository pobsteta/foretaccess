# Desserte enrichie/corrigee par LiDAR aerien (NDP 1). ForetAccess CONSOMME un
# moteur LiDAR externe, ne le reimplemente pas (regle stricte 1) :
#   * MOTEUR PAR DEFAUT : dessertR (pobsteta/dessertR, GPL-3, noyau Rust) --
#     reimplementation FRANCAISE de la methode Roussel et al. 2022, MAINTENUE,
#     sur-ensemble fonctionnel. Specs 023 + ADR-009.
#   * REPLI DE TRANSITION : ALSroads (r-lidar-lab, POC non maintenu, calibre
#     Quebec) -- deprecie, retire en Phase C. Spec 020.
#   * REPLI NDP 0 : ni dessertR ni ALSroads -> desserte BD TOPO inchangee,
#     colonnes LiDAR a NA. Ne plante jamais.
# Les moteurs sont des dependances OPTIONNELLES accedees dynamiquement (hors CRAN,
# non declarees) : R CMD check ne les compte pas, la CI n'exerce que le repli
# NDP 0. Le chemin dessertR/ALSroads est valide hors CI (Phase B, dalles reelles).

# Colonnes ajoutees par l'enrichissement LiDAR (presentes meme en repli NDP 0).
# Contrat PRESERVE (dessertR ou ALSroads) : largeur_carrossable_m,
# largeur_plateforme_m, pente_pct, etat_classe, score_lidar. Colonnes BONUS
# (dessertR uniquement ; NA avec ALSroads / NDP 0) : etat_dessertr, devers,
# fosses, rayon_courbure_p05, apte_grumier, motif_inaptitude.
.COLONNES_LIDAR <- c(
  "largeur_carrossable_m", "largeur_plateforme_m", "pente_pct",
  "etat_classe", "score_lidar"
)
.COLONNES_LIDAR_BONUS <- c(
  "etat_dessertr", "devers", "fosses", "rayon_courbure_p05",
  "apte_grumier", "motif_inaptitude"
)

# lidR ET ALSroads installes ? Dependances OPTIONNELLES et hors CRAN pour ALSroads
# (POC non maintenu) : on ne les DECLARE pas (ni Imports ni Suggests) pour ne pas
# forcer leur installation en CI ni alourdir le paquet. Les noms sont passes en
# VARIABLES a requireNamespace/getExportedValue : le chemin reel ne s'exerce que si
# l'utilisateur les a installes, et R CMD check ne les compte pas comme
# dependances non declarees. Requirement documente dans @details.
.PKG_LIDR <- "lidR"
.PKG_ALSROADS <- "ALSroads"
.PKG_RASTER <- "raster"
.PKG_DESSERTR <- "dessertR"

.alsroads_dispo <- function() {
  requireNamespace(.PKG_LIDR, quietly = TRUE) &&
    requireNamespace(.PKG_ALSROADS, quietly = TRUE)
}

.dessertr_dispo <- function() {
  requireNamespace(.PKG_DESSERTR, quietly = TRUE)
}

# Moteur effectivement retenu selon `moteur` et ce qui est installe.
# "auto" -> dessertR si dispo, sinon ALSroads si dispo, sinon "ndp0".
.moteur_lidar <- function(moteur = c("auto", "dessertr", "alsroads")) {
  moteur <- match.arg(moteur)
  if (moteur == "dessertr") {
    return(if (.dessertr_dispo()) "dessertr" else "ndp0")
  }
  if (moteur == "alsroads") {
    return(if (.alsroads_dispo()) "alsroads" else "ndp0")
  }
  if (.dessertr_dispo()) {
    return("dessertr")
  }
  if (.alsroads_dispo()) {
    return("alsroads")
  }
  "ndp0"
}

#' Enrich/correct a road network with airborne LiDAR (dessertR, NDP 1)
#'
#' Recomputes, from an airborne LiDAR HD point cloud, a **realigned geometry** and
#' per-segment attributes for a BD TOPO road network: **drivable width**, platform
#' width, longitudinal slope, **state** and (dessertR) cross-slope, ditches,
#' curvature and **timber-truck trafficability**. The drivable width is the
#' discriminator [places_depot()] lacks on raw BD TOPO (its truck-access criterion
#' is blind without a measured width); a measured width turns that criterion on.
#'
#' @details
#' **Engine.** The default engine is **dessertR** (`pobsteta/dessertR`, GPL-3, Rust
#' core) -- a maintained **French** reimplementation of the ALSroads method
#' (Roussel et al. 2022), calibrated for BD TOPO / IGN LiDAR HD (specs 023 +
#' ADR-009). **ALSroads** (`r-lidar-lab/ALSroads`, unmaintained, Quebec-calibrated)
#' is kept as a **deprecated transition fallback** (`moteur = "alsroads"`). Both
#' are **optional, undeclared** dependencies accessed dynamically; install dessertR
#' with `remotes::install_github("pobsteta/dessertR")` (it is **not** published on
#' any r-universe).
#' Without any engine, the function falls back to **NDP 0**: the road network is
#' returned unchanged, the LiDAR columns set to `NA`. It **never** errors on a
#' missing point cloud.
#'
#' **DTM resolution is critical.** ALSroads builds its edge-detection profiles at
#' `profile_resolution = 0.5 m`; a DTM coarser than 1 m yields `NA` widths (this
#' was the cause of the initial 0/6 in spec 020 Phase B, fed a 5 m accessibility
#' grid). When the supplied `mnt` is coarser than 1.5 m, a `dtm_res`-metre DTM is
#' derived here from the tile's ground points -- prefer passing IGN's 0.5 m LiDAR
#' HD DTM directly.
#'
#' **Calibration.** ALSroads is calibrated on Quebec (MFFP) forest roads, but with
#' a >= 1 m DTM it **does** measure French BD TOPO forest roads (spec 020 Phase B,
#' Chastel-Nouvel: Class-1 pistes measured at ~7 m). Still treat widths as
#' experimental and cross-check against an orthophoto on sensitive sites.
#'
#' **Geometry and coverage.** ALSroads requires a **single `LINESTRING`** centerline
#' and errors on the `MULTILINESTRING` of BD TOPO `troncon_de_route`; each tronçon
#' is therefore recast to one `LINESTRING` (contiguous parts merged, else the
#' longest part kept). Tronçons **outside the tiles' footprint** are dropped to
#' `NA` **before** any `measure_road` call: this is not just an optimisation but a
#' **safety guard** -- calling ALSroads on the thousands of point-less tronçons of a
#' full project desserte (hundreds of km for a handful of tiles) makes lidR/ALSroads
#' **segfault** (an uncatchable C++ crash). Tronçons **shorter than `long_min_m`**
#' are likewise skipped. Expect **most of a full desserte to be `NA`** and only the
#' long tronçons lying under a tile to carry a width. The `bilan` attribute of the
#' result breaks the outcome down: `mesure`, `trop_court`, `hors_couverture`,
#' `geometrie`, `echec`, `total`.
#'
#' @param desserte Road network: path to a vector file or an `sf` of lines (the
#'   output of [acquire_desserte()]).
#' @param las_source Airborne LiDAR: a directory/vector of `.las`/`.laz`/`.copc.laz`
#'   tiles, or a lidR `LAScatalog`. Passed to `lidR::readLAScatalog()`. Not
#'   downloaded here -- the caller provides it (e.g. the app's
#'   `download_ign_lidar_hd(product = "nuage")`).
#' @param mnt Digital terrain model: `SpatRaster` or path. Must share the CRS of
#'   `desserte` (no implicit reprojection, ADR-004).
#' @param mnh Canopy height model (`SpatRaster`/path) or `NULL`. Used by the
#'   dessertR surface channel (`sigma_surf`) and left `NULL` for ALSroads.
#' @param moteur LiDAR engine: `"auto"` (default -- dessertR if installed, else
#'   ALSroads, else NDP 0), `"dessertr"` or `"alsroads"` (deprecated).
#' @param crs Target EPSG code. Default 2154.
#' @param cache_dir Directory for the per-segment measurement cache. Default
#'   `tempdir()`.
#' @param dtm_res Resolution (m) of the DTM derived from ground points when `mnt`
#'   is coarser than 1.5 m. Default 1 (robust under canopy). 0.5 matches
#'   ALSroads' internal profile but needs a denser ground return.
#' @param long_min_m Minimum tronçon length (m) below which measurement is skipped
#'   (returned `NA`) without calling ALSroads -- shorter roads are unstable under
#'   its search buffer. Default 40. A full BD TOPO desserte has many short
#'   segments; only long tronçons under a tile get a width.
#' @param deviation_max Maximum lateral shift (m) allowed when dessertR
#'   re-registers a tronçon onto the LiDAR-detected roadbed
#'   (`dsr_repositionner()`). BD TOPO stays authoritative: beyond this budget the
#'   declared geometry is kept rather than snapped to a neighbouring track.
#'   Default 10. Ignored by the ALSroads engine, which has its own search buffer.
#' @return An `sf` in the format of [acquire_desserte()] **plus** the contract
#'   columns `largeur_carrossable_m`, `largeur_plateforme_m`, `pente_pct`,
#'   `etat_classe` (state, 4 classes) and `score_lidar`. **`score_lidar` is not a
#'   0-100 confidence like ALSroads' `SCORE`**: with the dessertR engine it is
#'   dessertR's `CONFIANCE_MNT`, i.e. the **ground point density** (pts/m²)
#'   sampled along the tronçon -- higher means the DTM under the road rests on
#'   more ground returns. Compare it across tronçons, not against a fixed scale.
#'   With the **dessertR**
#'   engine, also the bonus columns `etat_dessertr` (state label), `devers`
#'   (cross-slope), `fosses` (ditches 0/1/2), `rayon_courbure_p05`, `apte_grumier`
#'   and `motif_inaptitude`. In NDP 0 all these are `NA`. Attributes: `ndp`
#'   (`0L`/`1L`) and `moteur` (`"dessertr"`/`"alsroads"`/`"ndp0"`).
#' @seealso [places_depot()] (consumes the drivable width), [acquire_desserte()].
#' @export
#' @examples
#' \dontrun{
#' # NDP 1 (requires lidR + ALSroads + a point cloud):
#' des <- acquire_desserte(aoi)
#' des_lidar <- acquire_desserte_lidar(des, las_source = "cache/lidar_nuage", mnt = mnt)
#' places <- places_depot(des_lidar, mnt, largeur_min_m = 4) # acces camion discriminant
#' }
acquire_desserte_lidar <- function(desserte, las_source, mnt, mnh = NULL,
                                   moteur = c("auto", "dessertr", "alsroads"),
                                   crs = 2154, cache_dir = tempdir(), dtm_res = 1,
                                   long_min_m = 40, deviation_max = 10) {
  des <- .as_vector(desserte, "desserte")
  des <- sf::st_zm(sf::st_as_sf(des), drop = TRUE)
  if (nrow(des) == 0) {
    cli::cli_abort("La couche {.arg desserte} est vide.")
  }
  types <- as.character(sf::st_geometry_type(des))
  if (!any(grepl("LINE", types))) {
    cli::cli_abort("{.arg desserte} doit etre une couche de lignes.")
  }

  eng <- .moteur_lidar(moteur)

  # Repli NDP 0 : aucun moteur LiDAR installe -> desserte inchangee, colonnes NA.
  if (eng == "ndp0") {
    cli::cli_inform(c(
      "!" = "LiDAR indisponible (ni {.pkg dessertR} ni {.pkg ALSroads}) : repli
             {.strong NDP 0} -- desserte BD TOPO inchangee, largeurs a {.val NA}.",
      "i" = "Installer dessertR :
             {.code remotes::install_github(\"pobsteta/dessertR\")}."
    ))
    return(.desserte_lidar_ndp0(des))
  }

  # nocov start
  # Chemins NDP 1 : ne s'exercent qu'avec dessertR / ALSroads installes (absents en
  # CI, ou seul le repli NDP 0 tourne). VALIDES hors CI (Phase B, dalles reelles).
  mnt <- .as_raster(mnt, "mnt")
  .verifier_crs(des, mnt, "desserte")
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

  if (eng == "dessertr") {
    cli::cli_inform("Desserte LiDAR : moteur {.pkg dessertR} (NDP 1).")
    return(.desserte_lidar_dessertr(des, las_source, mnt, mnh, cache_dir,
      dtm_res, long_min_m, deviation_max))
  }
  cli::cli_warn("Desserte LiDAR : moteur {.pkg ALSroads} (deprecie, cf. ADR-009).")

  ctg <- .lidar_catalogue(las_source)
  # MNT >= 1 m EXIGE par ALSroads (profils a profile_resolution = 0.5 m ; un MNT
  # plus grossier -- p.ex. la grille d'accessibilite a 5 m -- rend des largeurs
  # NA : c'etait la cause du 0/6 initial en Phase B). Si le MNT fourni est plus
  # grossier, on en derive un a 1 m depuis les points sol de la dalle.
  dtm_fin <- .mnt_alsroads(mnt, ctg, cache_dir, dtm_res)
  # Densite IGN LiDAR HD ~ 10-45 pts/m2 ; ALSroads est cale sur 5-10, on decime
  # au-dela (recommandation du guide ALSroads) -- gain de vitesse, mesure stable.
  ctg <- .decimer_ctg(ctg)
  mesures <- .desserte_lidar_mesurer(des, ctg, dtm_fin, mnt, cache_dir, long_min_m)

  b <- attr(mesures, "bilan")
  cli::cli_inform(c(
    "v" = "Desserte enrichie LiDAR ({.strong NDP 1}) : {b[['mesure']]}/{b[['total']]}
           troncon{?s} mesure{?s}.",
    "i" = "{b[['hors_couverture']]} hors couverture des dalles (non mesures, sans
           appel ALSroads), {b[['trop_court']]} trop court{?s} (< {long_min_m} m),
           {b[['echec']]} echec{?s} ALSroads, {b[['geometrie']]} geometrie inexploitable.",
    "i" = "Une desserte de projet complete depasse souvent l'emprise des dalles
           fournies : seuls les troncons {.strong longs et sous une dalle} se
           mesurent. Largeurs a recouper avec une orthophoto sur site sensible."
  ))
  mesures
  # nocov end
}

# --- Repli NDP 0 : la desserte, augmentee des colonnes LiDAR a NA -------------
.desserte_lidar_ndp0 <- function(des) {
  des$largeur_carrossable_m <- NA_real_
  des$largeur_plateforme_m <- NA_real_
  des$pente_pct <- NA_real_
  des$etat_classe <- NA_integer_ # etat en 4 classes
  des$score_lidar <- NA_real_
  # Colonnes bonus (dessertR) : NA aussi en NDP 0, pour un contrat stable.
  des$etat_dessertr <- NA_character_
  des$devers <- NA_real_
  des$fosses <- NA_integer_
  des$rayon_courbure_p05 <- NA_real_
  des$apte_grumier <- NA
  des$motif_inaptitude <- NA_character_
  attr(des, "ndp") <- 0L
  attr(des, "moteur") <- "ndp0"
  des
}

# --- Chemin NDP 1 dessertR (moteur par defaut, spec 023 / ADR-009) ------------
# nocov start : ne tourne qu'avec dessertR installe (hors CI ; valide en Phase B
# sur dalles reelles, comme le chemin ALSroads). Suit le pipeline documente du
# README dessertR : catalog -> conductivite (sigma_geo) / sigma_surf -> etat ->
# repositionner -> measure (par troncon) -> trafficability.
.dsr <- function(nom) getExportedValue(.PKG_DESSERTR, nom)

.desserte_lidar_dessertr <- function(des, las_source, mnt, mnh, cache_dir,
                                     dtm_res, long_min_m, deviation_max) {
  # Chaine commune : grille, canaux geomorpho (sigma_geo) et surface (sigma_surf),
  # etat, une seule fois pour toute la desserte.
  grille <- .dsr("dsr_grille_reference")(mnt, res = dtm_res)
  pile <- .dsr("dsr_layers_dtm")(mnt, grille = grille)
  sigma_geo <- .dsr("dsr_conductivite")(pile)
  theta <- if ("theta" %in% names(pile)) pile[["theta"]] else NULL
  dalles <- tryCatch(.dsr("dsr_catalog")(laz = las_source),
    error = function(e) NULL)
  laz <- if (!is.null(dalles) && !is.null(dalles$laz)) as.character(dalles$laz) else character(0)
  # Canaux du nuage : sigma_surf (etat) ET densite de points sol (confiance du
  # MNT). Les deux derivent des memes `dsr_layers_pc`, calcules une seule fois.
  canaux <- .dsr_canaux_dalles(laz, grille)
  sigma_surf <- canaux$sigma_surf
  confiance <- canaux$confiance
  etat_r <- if (!is.null(sigma_surf)) {
    tryCatch(.dsr("dsr_etat")(sigma_geo, sigma_surf), error = function(e) NULL)
  } else {
    NULL
  }

  # Recalage contraint de TOUTE la desserte (BD TOPO autoritaire, deviation_max) ;
  # dessertR conserve tous les troncons. On travaille en LINESTRING (BD TOPO =
  # MULTILINESTRING) et on garde la correspondance ligne a ligne.
  ls_list <- lapply(seq_len(nrow(des)), function(i) .troncon_linestring(des[i, ]))
  ok_geom <- !vapply(ls_list, is.null, logical(1))
  des_ls <- do.call(rbind, ls_list[ok_geom])
  recale <- tryCatch(
    .dsr("dsr_repositionner")(des_ls, sigma_geo, theta = theta,
      deviation_max = deviation_max),
    error = function(e) des_ls
  )

  # Couverture (bbox du MNT LiDAR = emprise des dalles) : hors emprise -> NA sans
  # mesure (coherence, et le sigma_surf y est de toute facon indefini).
  couv <- tryCatch(sf::st_as_sfc(sf::st_bbox(mnt)), error = function(e) NULL)
  couverts <- .troncons_couverts(sf::st_geometry(recale), couv)

  seuils <- .dsr("dsr_seuils_grumier")()
  n_mesure <- 0L; n_court <- 0L; n_hors <- 0L; n_echec <- 0L
  lignes_ok <- vector("list", nrow(recale))
  for (i in seq_len(nrow(recale))) {
    road_l <- recale[i, ]
    if (!isTRUE(couverts[i])) {
      n_hors <- n_hors + 1L
      lignes_ok[[i]] <- .fusionner_mesure_dsr(road_l, NULL, NULL, NULL, mnt, etat_r)
      next
    }
    if (as.numeric(sf::st_length(sf::st_geometry(road_l))) < long_min_m) {
      n_court <- n_court + 1L
      lignes_ok[[i]] <- .fusionner_mesure_dsr(road_l, NULL, NULL, NULL, mnt, etat_r)
      next
    }
    # `confiance` alimente CONFIANCE_MNT (densite de points sol) : sans cet
    # argument dessertR n'emet PAS la colonne, et `score_lidar` reste NA.
    m <- tryCatch(.dsr("dsr_measure")(road_l, mnt, methode_largeur = "chaussee",
      confiance = confiance), error = function(e) NULL)
    mp <- tryCatch(.dsr("dsr_measure")(road_l, mnt, methode_largeur = "planeite",
      confiance = confiance), error = function(e) NULL)
    if (is.null(m)) {
      n_echec <- n_echec + 1L
    } else {
      n_mesure <- n_mesure + 1L
    }
    traf <- if (!is.null(m)) {
      tryCatch(.dsr("dsr_trafficability")(m$stations, seuils), error = function(e) NULL)
    } else {
      NULL
    }
    lignes_ok[[i]] <- .fusionner_mesure_dsr(road_l, m, mp, traf, mnt, etat_r)
  }

  # Reinjecte les troncons a geometrie inexploitable (NA) pour conserver nrow(des).
  out <- .reinjecter_geom_ko(des, ok_geom, do.call(rbind, lignes_ok), mnt)
  attr(out, "ndp") <- 1L
  attr(out, "moteur") <- "dessertr"
  attr(out, "bilan") <- c(
    mesure = n_mesure, trop_court = n_court, hors_couverture = n_hors,
    geometrie = sum(!ok_geom), echec = n_echec, total = nrow(des)
  )
  out
}

# Canaux du nuage sur PLUSIEURS dalles : couches_pc par dalle (dsr_layers_pc
# traite une dalle a la fois) mosaiquees, puis sigma_surf (entree de dsr_etat) et
# densite_sol (confiance du MNT, entree de CONFIANCE_MNT). Les deux sortent des
# memes couches : on ne les calcule qu'une fois. Champs a NULL si aucune dalle.
.dsr_canaux_dalles <- function(laz, grille) {
  vide <- list(sigma_surf = NULL, confiance = NULL)
  laz <- laz[file.exists(laz)]
  if (length(laz) == 0L) {
    return(vide)
  }
  couches <- lapply(laz, function(f) {
    tryCatch(.dsr("dsr_layers_pc")(f, grille = grille), error = function(e) NULL)
  })
  couches <- couches[!vapply(couches, is.null, logical(1))]
  if (length(couches) == 0L) {
    return(vide)
  }
  cp <- if (length(couches) == 1L) {
    couches[[1]]
  } else {
    do.call(terra::mosaic, c(couches, list(fun = "mean")))
  }
  list(
    sigma_surf = tryCatch(.dsr("dsr_sigma_surf")(cp), error = function(e) NULL),
    # Source recommandee par dessertR pour CONFIANCE_MNT (cf. ?dsr_measure).
    confiance = if ("densite_sol" %in% names(cp)) cp[["densite_sol"]] else NULL
  )
}

# Assemble une mesure dessertR (m = chaussee, mp = planeite, traf) dans le troncon
# recale. Extraction DEFENSIVE (NA si absent). pente_pct : notre calcul en long,
# coherent avec le chemin ALSroads. etat : classe dominante echantillonnee sur
# `etat_r` le long du troncon.
.fusionner_mesure_dsr <- function(road_l, m, mp, traf, mnt, etat_r) {
  geom <- sf::st_geometry(road_l)
  med <- function(x) if (is.null(x) || !length(x) || all(is.na(x))) NA_real_ else stats::median(x, na.rm = TRUE)
  rez <- function(l, nom) if (!is.null(l) && !is.null(l$resume[[nom]])) as.numeric(l$resume[[nom]]) else NA_real_
  st_col <- function(l, nom) if (!is.null(l) && !is.null(l$stations[[nom]])) l$stations[[nom]] else NULL

  larg_carr <- rez(m, "LARGEUR_ROULABLE_MED")
  larg_plat <- rez(mp, "LARGEUR_ROULABLE_MED")
  score <- med(st_col(m, "CONFIANCE_MNT"))
  devers <- med(st_col(m, "DEVERS"))
  fosses <- {
    fo <- st_col(m, "FOSSES")
    if (is.null(fo) || all(is.na(fo))) NA_integer_ else as.integer(max(fo, na.rm = TRUE))
  }
  rayon_p05 <- rez(m, "RAYON_COURBURE_P05")

  apte <- NA
  motif <- NA_character_
  # dsr_trafficability() rend list(stations, resume) : APTE_GRUMIER/MOTIF_INAPTITUDE
  # vivent dans `stations`, PAS au premier niveau de la liste.
  st_traf <- if (!is.null(traf) && !is.null(traf$stations)) traf$stations else NULL
  if (!is.null(st_traf) && !is.null(st_traf$APTE_GRUMIER)) {
    apte <- all(st_traf$APTE_GRUMIER, na.rm = TRUE) # apte ssi toutes stations aptes
    # Chaque station peut porter PLUSIEURS motifs deja joints par "+" : on
    # rescinde avant de dedupliquer, sinon on recolle "largeur+largeur+pente".
    mot <- unlist(strsplit(stats::na.omit(st_traf$MOTIF_INAPTITUDE), "+", fixed = TRUE))
    mot <- sort(unique(mot[nzchar(mot)]))
    motif <- if (length(mot)) paste(mot, collapse = "+") else ""
  }

  et <- .echantillonner_etat(geom, etat_r)

  att <- sf::st_drop_geometry(road_l)
  att$largeur_carrossable_m <- larg_carr
  att$largeur_plateforme_m <- larg_plat
  att$pente_pct <- .pente_en_long_geom(geom, mnt)
  att$etat_classe <- et$code
  att$score_lidar <- score
  att$etat_dessertr <- et$label
  att$devers <- devers
  att$fosses <- fosses
  att$rayon_courbure_p05 <- rayon_p05
  att$apte_grumier <- apte
  att$motif_inaptitude <- motif
  sf::st_sf(att, geometry = geom)
}

# Classe d'etat dominante le long du troncon (echantillonnage de `etat_r` aux
# sommets). Renvoie list(code entier, label). NA si etat_r absent.
.echantillonner_etat <- function(geom, etat_r) {
  if (is.null(etat_r)) {
    return(list(code = NA_integer_, label = NA_character_))
  }
  m <- tryCatch(sf::st_coordinates(geom)[, 1:2, drop = FALSE], silent = TRUE,
    error = function(e) NULL)
  if (is.null(m) || nrow(m) == 0) {
    return(list(code = NA_integer_, label = NA_character_))
  }
  # terra::extract() sur une MATRICE de coordonnees ne rend PAS de colonne `ID` :
  # la valeur est en DERNIERE colonne (indexer [, 2] levait "undefined columns
  # selected", avale par le tryCatch -> etat NA partout). Et `dsr_etat()` rend un
  # raster CATEGORIEL : l'extraction sort le LIBELLE, qu'on remappe en code via
  # la table des niveaux (as.integer() direct donnerait NA).
  ex <- tryCatch(terra::extract(etat_r, m), error = function(e) NULL)
  if (is.null(ex) || !NCOL(ex)) {
    return(list(code = NA_integer_, label = NA_character_))
  }
  brut <- ex[[NCOL(ex)]]
  lev <- tryCatch(terra::levels(etat_r)[[1]], error = function(e) NULL)
  a_niveaux <- is.data.frame(lev) && ncol(lev) >= 2
  v <- if (a_niveaux && !is.numeric(brut)) {
    as.integer(lev[[1]])[match(as.character(brut), as.character(lev[[2]]))]
  } else {
    suppressWarnings(as.integer(brut))
  }
  v <- v[!is.na(v)]
  if (!length(v)) {
    return(list(code = NA_integer_, label = NA_character_))
  }
  code <- as.integer(names(sort(table(v), decreasing = TRUE))[1])
  label <- NA_character_
  if (a_niveaux) {
    hit <- lev[[1]] == code
    if (any(hit)) label <- as.character(lev[[2]][which(hit)[1]])
  }
  list(code = code, label = label)
}

# Reinjecte les troncons a geometrie inexploitable (exclus du recalage) avec des
# colonnes LiDAR a NA, en conservant l'ordre et nrow d'origine.
.reinjecter_geom_ko <- function(des, ok_geom, mesures, mnt) {
  if (all(ok_geom)) {
    return(mesures)
  }
  out <- vector("list", nrow(des))
  j <- 1L
  for (i in seq_len(nrow(des))) {
    if (ok_geom[i]) {
      out[[i]] <- mesures[j, ]
      j <- j + 1L
    } else {
      out[[i]] <- .fusionner_mesure_dsr(des[i, ], NULL, NULL, NULL, mnt, NULL)
    }
  }
  do.call(rbind, out)
}
# nocov end

# --- Chemin NDP 1 (ALSroads) : isole, calibre Quebec, valide en Phase B -------
# nocov start : ne tourne qu'avec ALSroads installe (hors CI ; valide manuellement).

# LAScatalog lidR depuis un chemin de dalles ou un catalogue deja construit.
.lidar_catalogue <- function(las_source) {
  if (inherits(las_source, "LAScatalog")) {
    return(las_source)
  }
  read_ctg <- getExportedValue(.PKG_LIDR, "readLAScatalog")
  read_ctg(las_source)
}

# MNT >= 1 m pour ALSroads. Si le MNT fourni est deja assez fin (<= 1,5 m --
# p.ex. le MNT LiDAR HD officiel de l'IGN a 0,5 m, ou RGE ALTI a 1 m), on le
# garde. Sinon (grille d'accessibilite a 5 m) on en derive un a `dtm_res` m par
# triangulation des points sol (classe ASPRS 2) de la dalle, mis en cache.
.mnt_alsroads <- function(mnt, ctg, cache_dir, dtm_res = 1) {
  en_raster <- if (requireNamespace(.PKG_RASTER, quietly = TRUE)) {
    getExportedValue(.PKG_RASTER, "raster")
  } else {
    identity
  }
  res_max <- max(terra::res(mnt))
  if (res_max <= 1.5) {
    return(en_raster(mnt))
  }
  cli::cli_inform(c("!" = "MNT a {round(res_max, 1)} m > 1 m : ALSroads exige >= 1 m
    (profils a 0,5 m). Derivation d'un MNT a {dtm_res} m depuis les points sol
    de la dalle -- fournir le MNT LiDAR HD IGN (0,5 m) pour l'eviter."))
  f <- file.path(cache_dir, sprintf("dtm_alsroads_%gm.tif", dtm_res))
  if (!file.exists(f)) {
    read_las <- getExportedValue(.PKG_LIDR, "readLAS")
    rasterize_terrain <- getExportedValue(.PKG_LIDR, "rasterize_terrain")
    tin <- getExportedValue(.PKG_LIDR, "tin")
    sol <- read_las(ctg$filename, filter = "-keep_class 2") # sol seul
    d <- rasterize_terrain(sol, res = dtm_res, algorithm = tin())
    terra::writeRaster(d, f, overwrite = TRUE)
  }
  en_raster(terra::rast(f))
}

# IGN LiDAR HD ~ 10-45 pts/m2 ; ALSroads est cale sur 5-10 (guide ALSroads). On
# decime au-dela de 15 (marge) vers ~10 : mesure stable, forte accelaration.
.decimer_ctg <- function(ctg, cible = 10) {
  dens <- try(getExportedValue(.PKG_LIDR, "density")(ctg), silent = TRUE)
  if (inherits(dens, "try-error") || !is.finite(dens) || dens <= 1.5 * cible) {
    return(ctg)
  }
  set_filter <- getExportedValue(.PKG_LIDR, "opt_filter<-")
  set_filter(ctg, value = sprintf("-keep_random_fraction %.3f", cible / dens))
}

# Emprise couverte par le nuage : union des empreintes des dalles du catalogue
# (repli sur la bbox globale). Sert a NE PAS appeler measure_road hors couverture.
.couverture_dalles <- function(ctg) {
  g <- try(sf::st_geometry(ctg), silent = TRUE) # empreintes par dalle (lidR)
  if (inherits(g, "try-error") || length(g) == 0L) {
    g <- sf::st_as_sfc(sf::st_bbox(ctg)) # repli : emprise globale du catalogue
  }
  sf::st_make_valid(sf::st_union(g))
}

# Mesure ALSroads tronçon par tronçon, avec cache par identifiant. `measure_road`
# traite UNE route a la fois (cf. spec 020 sec.2) ; on boucle et on assemble.
# Chaque troncon est d'abord ramene a une LINESTRING unique (BD TOPO =
# MULTILINESTRING), les troncons HORS COUVERTURE des dalles ou plus courts que
# `long_min_m` sont sautes SANS appeler la mesure. Le filtre de couverture est
# VITAL : sur une desserte de projet (806 km) pour quelques dalles, appeler
# measure_road sur les milliers de troncons sans points fait segfaulter lidR/
# ALSroads (crash C++ non rattrapable) -- cf. brief segfault. L'attribut `bilan`
# decompose l'issue (mesure / trop court / hors couverture / geometrie / echec).
.desserte_lidar_mesurer <- function(des, ctg, dtm_fin, mnt, cache_dir,
                                    long_min_m = 40) {
  measure_road <- getExportedValue(.PKG_ALSROADS, "measure_road")
  ras <- dtm_fin # MNT >= 1 m deja au format RasterLayer (cf. .mnt_alsroads)
  cache_f <- file.path(cache_dir, "desserte_lidar.rds")
  cache <- if (file.exists(cache_f)) readRDS(cache_f) else list()

  # Couverture des dalles, calculee UNE fois. `couverts[i]` = le troncon i
  # touche-t-il au moins une dalle ? (test sur la geometrie d'origine, robuste au
  # type). Hors couverture -> NA propre, jamais de measure_road (anti-segfault).
  couv <- tryCatch(.couverture_dalles(ctg), error = function(e) NULL)
  couverts <- .troncons_couverts(sf::st_geometry(des), couv)

  n_mesure <- 0L
  n_court <- 0L
  n_geom <- 0L
  n_echec <- 0L
  n_hors_couv <- 0L
  lignes <- vector("list", nrow(des))
  for (i in seq_len(nrow(des))) {
    road_i <- des[i, ]
    road_l <- .troncon_linestring(road_i)
    if (is.null(road_l)) {
      n_geom <- n_geom + 1L
      lignes[[i]] <- .fusionner_mesure(road_i, NULL, mnt)
      next
    }
    if (!isTRUE(couverts[i])) {
      # Hors emprise des dalles : NA sans appeler measure_road (evite le segfault).
      n_hors_couv <- n_hors_couv + 1L
      lignes[[i]] <- .fusionner_mesure(road_l, NULL, mnt)
      next
    }
    if (as.numeric(sf::st_length(sf::st_geometry(road_l))) < long_min_m) {
      n_court <- n_court + 1L
      lignes[[i]] <- .fusionner_mesure(road_l, NULL, mnt)
      next
    }
    # Cle de cache : WKT de la LINESTRING (stable par troncon, sans dependance).
    cle <- as.character(sf::st_as_text(sf::st_geometry(road_l)))
    if (!is.null(cache[[cle]])) {
      res <- cache[[cle]]$res
    } else {
      res <- tryCatch(measure_road(ctg, road_l, ras), error = function(e) NULL)
      cache[[cle]] <- list(res = res) # memoise meme un echec (NULL)
    }
    if (is.null(res)) n_echec <- n_echec + 1L else n_mesure <- n_mesure + 1L
    lignes[[i]] <- .fusionner_mesure(road_l, res, mnt)
  }
  saveRDS(cache, cache_f)
  out <- do.call(rbind, lignes)
  attr(out, "ndp") <- 1L
  attr(out, "bilan") <- c(
    mesure = n_mesure, trop_court = n_court, hors_couverture = n_hors_couv,
    geometrie = n_geom, echec = n_echec, total = nrow(des)
  )
  out
}

# Fusionne la mesure ALSroads (`res`, ou NULL en echec) dans le troncon : geometrie
# recalee + colonnes, extraction DEFENSIVE (les noms varient selon la version
# d'ALSroads ; on prend ce qui existe, NA sinon).
.fusionner_mesure <- function(road_i, res, mnt) {
  col <- function(x, nom) if (!is.null(x[[nom]])) x[[nom]][1] else NA
  geom <- sf::st_geometry(road_i)
  larg_carr <- NA_real_
  larg_plat <- NA_real_
  etat_classe <- NA_integer_
  score <- NA_real_
  if (!is.null(res) && inherits(res, c("sf", "sfc", "data.frame"))) {
    if (inherits(res, c("sf", "sfc"))) {
      g <- try(sf::st_geometry(sf::st_zm(sf::st_as_sf(res), drop = TRUE)), silent = TRUE)
      if (!inherits(g, "try-error") && length(g) >= 1) geom <- g[1]
    }
    # Noms verifies sur la sortie reelle d'ALSroads (donnees d'exemple).
    larg_plat <- as.numeric(col(res, "ROADWIDTH"))
    larg_carr <- as.numeric(col(res, "DRIVABLEWIDTH"))
    etat_classe <- suppressWarnings(as.integer(col(res, "CLASS"))) # etat en 4 classes
    score <- as.numeric(col(res, "SCORE"))
  }
  att <- sf::st_drop_geometry(road_i)
  att$largeur_carrossable_m <- larg_carr
  att$largeur_plateforme_m <- larg_plat
  att$pente_pct <- .pente_en_long_geom(geom, mnt)
  att$etat_classe <- etat_classe
  att$score_lidar <- score
  sf::st_sf(att, geometry = geom)
}
# nocov end

# Quels troncons touchent la couverture des dalles ? (`couv` = polygone d'union,
# ou NULL si indeterminable -> on n'exclut rien). Hors couverture, on NE mesure PAS
# (anti-segfault). Geometrie pure, testable sans LiDAR.
.troncons_couverts <- function(geoms, couv) {
  if (is.null(couv) || length(couv) == 0L) {
    return(rep(TRUE, length(geoms)))
  }
  suppressWarnings(lengths(sf::st_intersects(geoms, couv)) > 0L)
}

# Ramene la geometrie d'un troncon a une LINESTRING UNIQUE. `measure_road` exige
# une centerline LINESTRING et ERREUR sur une MULTILINESTRING ("Expecting
# LINESTRING geometry ...") -- c'est la cause du 0/N sur une desserte BD TOPO
# reelle (troncon_de_route est en MULTILINESTRING). On fusionne les parties
# contigues ; si elles restent disjointes, on garde la plus longue. Renvoie le
# troncon (sf, 1 ligne) recale sur cette LINESTRING, ou NULL si inexploitable.
# Hors nocov : geometrie pure, testable sans LiDAR.
.troncon_linestring <- function(road_i) {
  g <- sf::st_geometry(road_i)
  if (as.character(sf::st_geometry_type(g)) == "MULTILINESTRING") {
    g <- sf::st_line_merge(g) # recolle les parties contigues
    if (as.character(sf::st_geometry_type(g)) == "MULTILINESTRING") {
      parts <- suppressWarnings(sf::st_cast(g, "LINESTRING"))
      if (length(parts) == 0) {
        return(NULL)
      }
      g <- parts[which.max(as.numeric(sf::st_length(parts)))]
    }
  }
  if (as.character(sf::st_geometry_type(g)) != "LINESTRING") {
    return(NULL)
  }
  sf::st_set_geometry(road_i, g)
}

# Pente en long (%) d'une geometrie sur le MNT : denivele entre extremites /
# longueur parcourue. Notre calcul, pas celui d'ALSroads.
.pente_en_long_geom <- function(geom, mnt) {
  m <- try(sf::st_coordinates(geom)[, 1:2, drop = FALSE], silent = TRUE)
  if (inherits(m, "try-error") || nrow(m) < 2) {
    return(NA_real_)
  }
  lg <- sum(sqrt(diff(m[, 1])^2 + diff(m[, 2])^2))
  if (lg <= 0) {
    return(NA_real_)
  }
  z <- as.numeric(terra::extract(mnt, m[c(1, nrow(m)), , drop = FALSE])[, 1])
  if (anyNA(z)) {
    return(NA_real_)
  }
  100 * abs(z[2] - z[1]) / lg
}
