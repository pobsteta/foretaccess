# Desserte enrichie/corrigee par LiDAR aerien (NDP 1, spec 020). Enveloppe FINE
# d'ALSroads (r-lidar-lab) : ForetAccess consomme le paquet, ne le reimplemente
# pas (regle stricte 1 -- la mecanique LiDAR n'est pas de la logique metier
# ForetAccess). ALSroads et lidR sont des dependances OPTIONNELLES accedees
# dynamiquement (POC experimental hors CRAN) : sans elles, repli NDP 0 (desserte
# BD TOPO inchangee, colonnes LiDAR a NA). Voir specs/020-desserte-lidar-alsroads.md.
#
# STATUT DE VALIDATION : le repli NDP 0 et l'orchestration sont testes (CI, sans
# LiDAR). Le chemin ALSroads (mesure reelle) est calibre Quebec (MFFP) mais mesure
# BIEN les routes forestieres francaises A CONDITION d'un MNT >= 1 m -- Phase B de
# la spec 020 (Chastel-Nouvel) : le 0/6 initial venait d'un MNT a 5 m, pas d'un
# defaut de calibrage. Reste "experimental" (largeurs a recouper sur site).

# Colonnes ajoutees par l'enrichissement LiDAR (presentes meme en repli NDP 0).
# Noms verifies sur la sortie reelle d'ALSroads (donnees d'exemple du paquet) :
# ROADWIDTH, DRIVABLEWIDTH, SCORE, CLASS (etat en 4 classes -- pas de champ STATE).
.COLONNES_LIDAR <- c(
  "largeur_carrossable_m", "largeur_plateforme_m", "pente_pct",
  "etat_classe", "score_lidar"
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

.alsroads_dispo <- function() {
  requireNamespace(.PKG_LIDR, quietly = TRUE) &&
    requireNamespace(.PKG_ALSROADS, quietly = TRUE)
}

#' Enrich/correct a road network with airborne LiDAR (ALSroads, NDP 1)
#'
#' Wraps **ALSroads** (`measure_road`) to recompute, from an airborne LiDAR point
#' cloud, a **realigned geometry** and per-segment attributes for a BD TOPO road
#' network: **drivable width**, platform width, longitudinal slope and **state**
#' (in use / decommissioned / gone). The drivable width is the discriminator
#' [places_depot()] lacks on raw BD TOPO (its truck-access criterion is blind
#' without a measured width, hence loose departures -- see its *Performance et
#' selectivite* section); a measured width turns that criterion on.
#'
#' @details
#' **Optional, experimental (NDP 1).** ALSroads and lidR are **not** declared
#' dependencies -- ALSroads is an unmaintained proof-of-concept
#' (`r-lidar-lab/ALSroads`, v0.2.0). Install them yourself to use this:
#' `install.packages("lidR")` and `remotes::install_github("r-lidar-lab/ALSroads")`.
#' Without them, the function falls back to **NDP 0**: the road network is returned
#' unchanged, the LiDAR columns set to `NA`, and a message says so. It **never**
#' errors on a missing point cloud.
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
#' @param desserte Road network: path to a vector file or an `sf` of lines (the
#'   output of [acquire_desserte()]).
#' @param las_source Airborne LiDAR: a directory/vector of `.las`/`.laz`/`.copc.laz`
#'   tiles, or a lidR `LAScatalog`. Passed to `lidR::readLAScatalog()`. Not
#'   downloaded here -- the caller provides it (e.g. the app's
#'   `download_ign_lidar_hd(product = "nuage")`).
#' @param mnt Digital terrain model: `SpatRaster` or path. Must share the CRS of
#'   `desserte` (no implicit reprojection, ADR-004).
#' @param crs Target EPSG code. Default 2154.
#' @param cache_dir Directory for the per-segment measurement cache. Default
#'   `tempdir()`.
#' @param dtm_res Resolution (m) of the DTM derived from ground points when `mnt`
#'   is coarser than 1.5 m. Default 1 (robust under canopy). 0.5 matches
#'   ALSroads' internal profile but needs a denser ground return.
#' @return An `sf` in the format of [acquire_desserte()] **plus** the columns
#'   `largeur_carrossable_m` (ALSroads `DRIVABLEWIDTH`), `largeur_plateforme_m`
#'   (`ROADWIDTH`), `pente_pct` (computed here from the realigned geometry),
#'   `etat_classe` (ALSroads `CLASS` -- road **state in four classes**) and
#'   `score_lidar` (`SCORE`). In NDP 0 (no LiDAR/ALSroads) the geometry is
#'   unchanged and those columns are `NA`. The `ndp` attribute is `0L` or `1L`.
#' @seealso [places_depot()] (consumes the drivable width), [acquire_desserte()].
#' @export
#' @examples
#' \dontrun{
#' # NDP 1 (requires lidR + ALSroads + a point cloud):
#' des <- acquire_desserte(aoi)
#' des_lidar <- acquire_desserte_lidar(des, las_source = "cache/lidar_nuage", mnt = mnt)
#' places <- places_depot(des_lidar, mnt, largeur_min_m = 4) # acces camion discriminant
#' }
acquire_desserte_lidar <- function(desserte, las_source, mnt, crs = 2154,
                                   cache_dir = tempdir(), dtm_res = 1) {
  des <- .as_vector(desserte, "desserte")
  des <- sf::st_zm(sf::st_as_sf(des), drop = TRUE)
  if (nrow(des) == 0) {
    cli::cli_abort("La couche {.arg desserte} est vide.")
  }
  types <- as.character(sf::st_geometry_type(des))
  if (!any(grepl("LINE", types))) {
    cli::cli_abort("{.arg desserte} doit etre une couche de lignes.")
  }

  # Repli NDP 0 : pas de LiDAR / pas d'ALSroads -> desserte inchangee, colonnes NA.
  if (!.alsroads_dispo()) {
    cli::cli_inform(c(
      "!" = "LiDAR indisponible ({.pkg lidR} / {.pkg ALSroads} non installes) :
             repli {.strong NDP 0} -- desserte BD TOPO inchangee, largeurs a {.val NA}.",
      "i" = "Installer : {.code install.packages(\"lidR\")} et
             {.code remotes::install_github(\"r-lidar-lab/ALSroads\")}."
    ))
    return(.desserte_lidar_ndp0(des))
  }

  # nocov start
  # Chemin NDP 1 : ne s'exerce qu'avec lidR + ALSroads installes (absent en CI, ou
  # seul le repli NDP 0 tourne). VALIDE hors CI de bout en bout : exemple ALSroads
  # (spec 020 sec.2) et donnee reelle Chastel-Nouvel (Phase B) -- pas du code non teste.
  mnt <- .as_raster(mnt, "mnt")
  .verifier_crs(des, mnt, "desserte")
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

  ctg <- .lidar_catalogue(las_source)
  # MNT >= 1 m EXIGE par ALSroads (profils a profile_resolution = 0.5 m ; un MNT
  # plus grossier -- p.ex. la grille d'accessibilite a 5 m -- rend des largeurs
  # NA : c'etait la cause du 0/6 initial en Phase B). Si le MNT fourni est plus
  # grossier, on en derive un a 1 m depuis les points sol de la dalle.
  dtm_fin <- .mnt_alsroads(mnt, ctg, cache_dir, dtm_res)
  # Densite IGN LiDAR HD ~ 10-45 pts/m2 ; ALSroads est cale sur 5-10, on decime
  # au-dela (recommandation du guide ALSroads) -- gain de vitesse, mesure stable.
  ctg <- .decimer_ctg(ctg)
  mesures <- .desserte_lidar_mesurer(des, ctg, dtm_fin, mnt, cache_dir)

  cli::cli_inform(c(
    "v" = "Desserte enrichie LiDAR ({.strong NDP 1}) : {sum(!is.na(mesures$largeur_carrossable_m))}/{nrow(des)}
           troncon{?s} mesure{?s}.",
    "i" = "ALSroads valide sur donnee francaise avec un MNT >= 1 m (spec 020
           Phase B) ; largeurs a recouper avec une orthophoto sur site sensible."
  ))
  mesures
  # nocov end
}

# --- Repli NDP 0 : la desserte, augmentee des colonnes LiDAR a NA -------------
.desserte_lidar_ndp0 <- function(des) {
  des$largeur_carrossable_m <- NA_real_
  des$largeur_plateforme_m <- NA_real_
  des$pente_pct <- NA_real_
  des$etat_classe <- NA_integer_ # CLASS ALSroads : etat en 4 classes
  des$score_lidar <- NA_real_
  attr(des, "ndp") <- 0L
  des
}

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

# Mesure ALSroads tronçon par tronçon, avec cache par identifiant. `measure_road`
# traite UNE route a la fois (cf. spec 020 sec.2) ; on boucle et on assemble.
.desserte_lidar_mesurer <- function(des, ctg, dtm_fin, mnt, cache_dir) {
  measure_road <- getExportedValue(.PKG_ALSROADS, "measure_road")
  ras <- dtm_fin # MNT >= 1 m deja au format RasterLayer (cf. .mnt_alsroads)
  # Cle de cache : hachage de la geometrie (stable par troncon).
  cache_f <- file.path(cache_dir, "desserte_lidar.rds")
  cache <- if (file.exists(cache_f)) readRDS(cache_f) else list()

  lignes <- vector("list", nrow(des))
  for (i in seq_len(nrow(des))) {
    road_i <- des[i, ]
    # Cle de cache : WKT de la geometrie (stable par troncon, sans dependance).
    cle <- as.character(sf::st_as_text(sf::st_geometry(road_i)))
    res <- cache[[cle]]
    if (is.null(res)) {
      res <- tryCatch(measure_road(ctg, road_i, ras), error = function(e) NULL)
      cache[[cle]] <- list(res = res) # memoise meme un echec (NULL)
    } else {
      res <- res$res
    }
    lignes[[i]] <- .fusionner_mesure(road_i, res, mnt)
  }
  saveRDS(cache, cache_f)
  out <- do.call(rbind, lignes)
  attr(out, "ndp") <- 1L
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
