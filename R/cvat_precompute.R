# Materialisation du CVAT (VAT combine) sur une emprise AOI + buffer, avec
# GARANTIE DE COUVERTURE. Le fond relief archeo doit couvrir toute l'emprise de
# travail (AOI elargie du buffer) : si le MNT fourni est trop court (dalles LiDAR
# HD manquantes -> mosaique qui ne contient pas l'emprise, ou majorite de NA), on
# (re)acquiert le MNT LiDAR HD sur l'emprise via acquire_mnt (WMS, couvre la bbox
# demandee) puis on recalcule. Sinon un CVAT calcule sur une mosaique partielle
# laisserait des trous / des bords manquants dans le comparateur.

# L'emprise (AOI + buffer, reprojetee dans le CRS du MNT) est-elle couverte ?
# Deux conditions : (1) l'ETENDUE du MNT contient l'emprise (sinon "trop court"),
# (2) au moins `seuil` des cellules DANS l'emprise sont finies (sinon trous).
.emprise_couverte <- function(mnt_path, emprise, seuil = 0.9) {
  if (is.null(mnt_path) || !file.exists(mnt_path)) {
    return(FALSE)
  }
  r <- tryCatch(terra::rast(mnt_path), error = function(e) NULL)
  if (is.null(r)) {
    return(FALSE)
  }
  emp <- tryCatch(terra::vect(sf::st_transform(emprise, terra::crs(r))),
    error = function(e) NULL
  )
  if (is.null(emp)) {
    return(FALSE)
  }
  re <- terra::ext(r)
  ee <- terra::ext(emp)
  # 1. Etendue du MNT >= emprise ? (marge d'un demi-pixel toleree via <=/>=)
  if (ee[1] < re[1] || ee[2] > re[2] || ee[3] < re[3] || ee[4] > re[4]) {
    return(FALSE)
  }
  # 2. Fraction de cellules finies dans l'emprise.
  rc <- tryCatch(terra::mask(terra::crop(r, emp), emp), error = function(e) NULL)
  if (is.null(rc)) {
    return(FALSE)
  }
  v <- terra::values(rc, mat = FALSE)
  length(v) > 0 && mean(is.finite(v)) >= seuil
}

#' Precompute the CVAT relief over an AOI + buffer, guaranteeing coverage
#'
#' Materializes the **CVAT** (Combined VAT, [vat_combined()]) as an 8-bit GeoTIFF
#' covering the working extent (**AOI widened by `buffer_m`**). If a DEM is passed
#' via `mnt_existant` and it **covers the whole AOI + buffer**, it is used as is;
#' otherwise (missing LiDAR HD tiles -> the mosaic is too short, or mostly `NA`)
#' the LiDAR HD DEM is **re-acquired over the buffered extent** with
#' [acquire_mnt()] (WMS, which always spans the requested bbox) and the CVAT is
#' recomputed. This prevents a CVAT built on a partial mosaic from leaving holes
#' or a truncated relief in the comparator background.
#'
#' @details
#' foretaccess does **not** download individual LiDAR HD tiles (`.copc.laz`): it
#' acquires the DEM through the IGN WMS, so re-acquisition inherently spans the
#' full AOI + buffer (no "missing tile" to chase). A caller that owns a native
#' 0.5 m tile mosaic (e.g. an app's LiDAR ingestion) should pass it as
#' `mnt_existant`; it is kept whenever it already covers the extent, and only
#' replaced by the (coarser-looking) WMS DEM when it is too short.
#'
#' @param aoi Working area: a path to a vector file, or an `sf`/`sfc` object.
#' @param cache_dir Directory for the (re-)acquired DEM and, by default, the CVAT.
#' @param buffer_m Buffer (m) grown around the AOI to define the extent to cover.
#'   Default 100.
#' @param res_lidar_m LiDAR HD DEM resolution (m) used when (re-)acquiring.
#'   Default 0.5 (native IGN LiDAR HD DTM).
#' @param crs Target CRS (EPSG code or WKT). Default 2154 (Lambert-93).
#' @param mnt_existant Optional path to an existing DEM (e.g. a native LiDAR
#'   mosaic). Reused when it covers the AOI + buffer; otherwise ignored.
#' @param out Output path for the 8-bit CVAT. Default `cache_dir/cvat_8bit.tif`.
#' @param overwrite Force re-acquisition (if needed) and recomputation even if
#'   `out` already exists.
#' @param seuil_couverture Minimal finite-cell fraction inside the extent for a
#'   DEM to count as covering it. Default 0.9.
#' @param country Country code for [acquire_mnt()] layer resolution. Default
#'   `"FR"`.
#' @return Path to the 8-bit CVAT GeoTIFF (`0..255`, `NA`->255), covering the
#'   AOI + buffer.
#' @seealso [vat_combined()], [acquire_mnt()].
#' @export
#' @examples
#' \donttest{
#' # Emprise + MNT deja couvrant -> pas de reacquisition reseau :
#' aoi <- sf::st_as_sf(sf::st_sfc(
#'   sf::st_polygon(list(rbind(c(0, 0), c(20, 0), c(20, 20), c(0, 20), c(0, 0)))),
#'   crs = 2154))
#' mnt <- terra::rast(xmin = -10, xmax = 30, ymin = -10, ymax = 30,
#'                    resolution = 1, crs = "EPSG:2154")
#' terra::values(mnt) <- 100 + terra::rowFromCell(mnt, seq_len(terra::ncell(mnt)))
#' d <- withr::local_tempdir()
#' terra::writeRaster(mnt, file.path(d, "mnt.tif"))
#' p <- build_cvat_precomputed(aoi, cache_dir = d, buffer_m = 5,
#'                             mnt_existant = file.path(d, "mnt.tif"))
#' terra::rast(p)
#' }
build_cvat_precomputed <- function(aoi, cache_dir, buffer_m = 100,
                                   res_lidar_m = 0.5, crs = 2154,
                                   mnt_existant = NULL, out = NULL,
                                   overwrite = FALSE, seuil_couverture = 0.9,
                                   country = "FR") {
  checkmate::assert_number(buffer_m, lower = 0, finite = TRUE)
  checkmate::assert_number(res_lidar_m, lower = 0, finite = TRUE)
  checkmate::assert_number(seuil_couverture, lower = 0, upper = 1)
  if (!dir.exists(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  }
  if (is.null(out)) {
    out <- file.path(cache_dir, "cvat_8bit.tif")
  }
  if (file.exists(out) && !isTRUE(overwrite)) {
    return(out)
  }

  # Emprise de travail = AOI + buffer (le CVAT doit la couvrir entierement).
  aoi_stricte <- .charger_aoi(aoi, crs)
  emprise <- if (buffer_m > 0) sf::st_buffer(aoi_stricte, buffer_m) else aoi_stricte

  # MNT couvrant l'emprise : on reutilise `mnt_existant` s'il couvre tout, sinon
  # on (re)acquiert le LiDAR HD sur l'emprise (WMS -> couvre la bbox demandee).
  if (!is.null(mnt_existant) && !isTRUE(overwrite) &&
    .emprise_couverte(mnt_existant, emprise, seuil_couverture)) {
    mnt_path <- mnt_existant
  } else {
    if (!is.null(mnt_existant)) {
      cli::cli_inform(
        "MNT fourni absent ou ne couvrant pas l'emprise AOI+buffer : (re)acquisition
         LiDAR HD sur l'emprise."
      )
    }
    mnt_path <- acquire_mnt(emprise,
      res_m = res_lidar_m, res_lidar_m = res_lidar_m, crs = crs,
      cache_dir = cache_dir, overwrite = TRUE, country = country
    )
    if (!.emprise_couverte(mnt_path, emprise, seuil_couverture)) {
      cli::cli_warn(
        "Le MNT (re)acquis ne couvre que partiellement l'emprise (LiDAR HD
         indisponible ?) : le CVAT peut comporter des zones NA."
      )
    }
  }

  mnt <- terra::rast(mnt_path)
  if (terra::nlyr(mnt) > 1L) {
    mnt <- mnt[[1]]
  }
  cvat <- vat_combined(mnt, as_byte = TRUE)
  terra::writeRaster(cvat, out,
    overwrite = TRUE, datatype = "INT1U",
    gdal = c("COMPRESS=DEFLATE")
  )
  out
}
