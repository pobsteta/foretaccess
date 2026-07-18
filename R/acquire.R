#' Acquiert les entrées ForêtAccess depuis une AOI
#'
#' Télécharge automatiquement, à partir d'un simple polygone d'emprise (AOI), les
#' couches attendues par [preprocess()] : MNT (RGE ALTI), desserte (BD TOPO),
#' forêt (BD Forêt v2), obstacles (OpenStreetMap) et, en option, le parcellaire
#' cadastral. Approche **config-driven** (patron nemeton) : endpoints et couches
#' sont déclarés dans `inst/datasources/<pays>.json`, jamais codés en dur
#' (voir [datasources]).
#'
#' @details
#' Les clients réseau (`happign` pour l'IGN, `osmdata` pour OSM) sont en
#' **Suggests** : le cœur du paquet s'installe sans eux, et seule l'acquisition
#' les requiert (message d'installation ciblé sinon). Chaque source est mise en
#' **cache** sous `cache_dir/layers/<couche>/` et réutilisée au 2ᵉ appel, sauf
#' `overwrite = TRUE`.
#'
#' L'AOI est reprojetée dans `crs` (EPSG:2154 par défaut). Un **buffer**
#' (`buffer_m`, défaut 100 m) élargit l'emprise d'acquisition pour capter la
#' desserte juste hors de l'AOI — utile au plus court chemin (Lot 2) ; les couches
#' sont découpées sur cette emprise élargie. L'AOI stricte est conservée dans le
#' résultat (`$aoi`).
#'
#' @param aoi Emprise : chemin d'un fichier vectoriel, ou objet `sf`/`sfc`
#'   polygonal. **Doit porter un CRS** (règle stricte du projet).
#' @param sources Sources à acquérir (sous-ensemble de `mnt`, `desserte`, `foret`,
#'   `obstacles`, `cadastre`).
#' @param cache_dir Répertoire de cache. Défaut `tempdir()`.
#' @param res_m Résolution du MNT (m). Défaut 5.
#' @param res_lidar_m Résolution fine (m) de téléchargement du MNT LIDAR HD,
#'   agrégée à `res_m` (cf. [acquire_mnt()]). Défaut 1.
#' @param crs Code EPSG de sortie. Défaut 2154.
#' @param buffer_m Buffer d'emprise (m) autour de l'AOI. Défaut 100.
#' @param overwrite Re-télécharger même si le cache existe. Défaut `FALSE`.
#' @param country Code pays ISO. Défaut `"FR"`.
#' @param dfci Alimenter le flag DFCI (`CL_DFCI`) sur la desserte, source du camion
#'   DFCI (spec 006) : réseau OSM `ref:FR:DFCI` ([acquire_dfci()]), avec repli
#'   géométrique ([flag_dfci()]) si OSM ne rend rien. Défaut `TRUE`.
#' @param config Objet [foretaccess_config()] fournissant les seuils DFCI
#'   (`dfci$tol_appariement_m`, `emprise_min_m`, `rayon_retournement_m`) passés à
#'   [flag_dfci()]. Défaut `NULL` (seuils par défaut).
#'
#' @return Un objet `foretaccess_inputs` : `mnt` (chemin raster), `desserte`,
#'   `foret`, `obstacles`, `parcellaire` (`sf` ou `NULL`), `aoi` (`sf` stricte),
#'   `meta` (sources, CRS, buffer, date), `cache_dir`. Directement consommable par
#'   [preprocess()].
#' @seealso [preprocess()], [datasources], [acquire_mnt()]
#' @export
#' @examples
#' \dontrun{
#' aoi <- sf::st_read("mon_massif.gpkg")
#' inputs <- acquire_inputs(aoi, cache_dir = "cache")
#' pre <- preprocess(inputs$mnt, inputs$desserte, inputs$foret,
#'                   obstacles_complets = inputs$obstacles)
#' }
acquire_inputs <- function(aoi,
                           sources = c("mnt", "desserte", "foret", "obstacles", "cadastre"),
                           cache_dir = tempdir(),
                           res_m = 5,
                           res_lidar_m = 1,
                           crs = 2154,
                           buffer_m = 100,
                           overwrite = FALSE,
                           country = "FR",
                           dfci = TRUE,
                           config = NULL) {
  sources <- match.arg(sources, c("mnt", "desserte", "foret", "obstacles", "cadastre"),
    several.ok = TRUE)
  checkmate::assert_number(res_m, lower = 0, finite = TRUE)
  checkmate::assert_number(buffer_m, lower = 0, finite = TRUE)
  checkmate::assert_flag(overwrite)
  checkmate::assert_flag(dfci)

  aoi_stricte <- .charger_aoi(aoi, crs)
  emprise <- if (buffer_m > 0) sf::st_buffer(aoi_stricte, buffer_m) else aoi_stricte

  out <- list(
    mnt = NULL, desserte = NULL, foret = NULL, obstacles = NULL,
    parcellaire = NULL, aoi = aoi_stricte
  )

  if ("mnt" %in% sources) {
    out$mnt <- acquire_mnt(emprise, res_m = res_m, res_lidar_m = res_lidar_m, crs = crs,
      cache_dir = cache_dir, overwrite = overwrite, country = country)
  }
  if ("desserte" %in% sources) {
    out$desserte <- acquire_desserte(emprise, crs = crs,
      cache_dir = cache_dir, overwrite = overwrite, country = country)
  }
  if ("foret" %in% sources) {
    out$foret <- acquire_foret(emprise, crs = crs,
      cache_dir = cache_dir, overwrite = overwrite, country = country)
  }
  if ("obstacles" %in% sources) {
    out$obstacles <- acquire_obstacles(emprise, crs = crs,
      cache_dir = cache_dir, overwrite = overwrite)
  }
  if ("cadastre" %in% sources) {
    out$parcellaire <- acquire_cadastre(emprise, crs = crs,
      cache_dir = cache_dir, overwrite = overwrite, country = country)
  }

  # Flag DFCI (CL_DFCI) sur la desserte : reseau OSM `ref:FR:DFCI`, avec repli
  # geometrique si OSM ne rend rien. Orthogonal aux classes route/piste.
  if (isTRUE(dfci) && !is.null(out$desserte) && nrow(out$desserte) > 0) {
    dfci_lignes <- tryCatch(
      acquire_dfci(emprise, crs = crs, cache_dir = cache_dir, overwrite = overwrite),
      error = function(e) NULL
    )
    retournements <- if (is.null(dfci_lignes) || nrow(dfci_lignes) == 0) {
      tryCatch(.acquire_retournements(emprise, crs = crs), error = function(e) NULL)
    } else {
      NULL
    }
    df <- (config %||% foretaccess_config())$dfci
    out$desserte <- flag_dfci(out$desserte, dfci_lignes, retournements,
      emprise_min_m = df$emprise_min_m,
      rayon_retournement_m = df$rayon_retournement_m,
      tol_appariement_m = df$tol_appariement_m)
  }

  out$meta <- list(
    sources = sources, country = country, crs = crs,
    res_m = res_m, buffer_m = buffer_m, date = as.character(Sys.Date())
  )
  out$cache_dir <- cache_dir
  structure(out, class = "foretaccess_inputs")
}

# Charge l'AOI (chemin ou sf/sfc), verrou CRS strict, reprojection vers `crs`.
.charger_aoi <- function(aoi, crs) {
  if (inherits(aoi, "sf") || inherits(aoi, "sfc")) {
    a <- sf::st_sf(geometry = sf::st_geometry(aoi))
  } else if (is.character(aoi) && length(aoi) == 1L) {
    checkmate::assert_file_exists(aoi, access = "r")
    a <- sf::st_read(aoi, quiet = TRUE)
    a <- sf::st_sf(geometry = sf::st_geometry(a))
  } else {
    cli::cli_abort("{.arg aoi} doit etre un chemin de fichier ou un objet {.cls sf}/{.cls sfc}.")
  }
  if (is.na(sf::st_crs(a))) {
    cli::cli_abort(c(
      "{.arg aoi} n'a pas de CRS.",
      "i" = "Aucune couche sans CRS n'est admise : definissez le CRS de l'AOI."
    ))
  }
  a <- sf::st_transform(a, sf::st_crs(crs))
  sf::st_sf(geometry = sf::st_union(a))
}

#' @export
print.foretaccess_inputs <- function(x, ...) {
  n <- function(v) if (is.null(v)) "-" else if (inherits(v, "sf")) nrow(v) else "1"
  cli::cli_inform(c(
    "Entrees ForetAccess acquises depuis une AOI",
    "*" = "pays / CRS : {x$meta$country} / EPSG:{x$meta$crs} (buffer {x$meta$buffer_m} m)",
    "*" = "mnt : {if (is.null(x$mnt)) '-' else 'raster'} ; desserte : {n(x$desserte)} ; \\
           foret : {n(x$foret)} ; obstacles : {n(x$obstacles)} ; parcellaire : {n(x$parcellaire)}"
  ))
  invisible(x)
}
