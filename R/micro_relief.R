# Canaux de micro-relief RVT (spec 021, J3) : sky-view factor et openness (+/-).
# Enveloppe SIG (terra) du noyau Rust `rvt_svf_opns()` : R prepare la grille a
# plat et recolle les canaux sur le MNT, le balayage horizon vit dans le crate
# (regle stricte 3, pas de SIG en Rust). Ces canaux revelent la plateforme, les
# talus (deverss) et banquettes d'une piste sous couvert -- entrees de la
# qualification de desserte (spec 021 sec.6) et utiles a tous les moteurs
# (caracterisation des places de retournement DFCI, filtrage des ancrages cable).

#' Micro-relief channels from a DEM (RVT sky-view factor & openness, spec 021)
#'
#' Derives the **sky-view factor** and **openness** (positive and negative) of a
#' terrain model -- the micro-relief channels that carry the signal of a forest
#' track (platform depression, up-slope and down-slope embankments) far better
#' than the raw DEM. Thin GIS wrapper over the Rust kernel [rvt_svf_opns()]
#' (ported from the Relief Visualization Toolbox, Apache 2.0); the horizon sweep
#' runs in the crate, `terra` only lays the channels back onto the DEM grid.
#'
#' @details
#' **Negative openness** is the openness of the **inverted** DEM (it lights up
#' up-slope banks / ditches), computed here by running the kernel on `-z`.
#'
#' The search radius is given in **metres** and converted to pixels against the
#' DEM resolution. RVT's scale parameters are tuned for archaeological features a
#' few metres wide -- compatible with 3-6 m track platforms, but run a
#' **sensitivity sweep** on a pilot massif before freezing them (spec 021 sec.6).
#' Feed a DEM at **1 m or finer** for road work (see [acquire_desserte_lidar()]).
#'
#' @param mnt Digital terrain model as a single-layer `SpatRaster` (assumed
#'   square cells; the first layer is used if several).
#' @param radius_m Maximal horizon search radius in **metres**. Default 10.
#' @param radius_min_m Minimal search radius in metres (noise reduction). Default
#'   `NULL` -> one pixel.
#' @param num_directions Number of azimuth directions swept. Default 16.
#' @param canaux Which channels to return, any of `"svf"`, `"openness_pos"`,
#'   `"openness_neg"`. Default: all three.
#' @return A `SpatRaster` aligned to `mnt` with one layer per requested channel
#'   (`svf` in 0..1, `openness_pos`/`openness_neg` in degrees), `NA` where the
#'   DEM is `NA`.
#' @seealso [rvt_svf_opns()] (the Rust kernel), [acquire_desserte_lidar()] and
#'   [qualifier_desserte()] (consumers of a >= 1 m DEM).
#' @export
#' @examples
#' mnt <- terra::rast(nrows = 30, ncols = 30, xmin = 0, xmax = 30,
#'                    ymin = 0, ymax = 30, crs = "EPSG:2154")
#' terra::values(mnt) <- 100 # terrain plat -> svf = 1, openness = 90
#' mr <- micro_relief(mnt, radius_m = 5)
#' names(mr)
micro_relief <- function(mnt, radius_m = 10, radius_min_m = NULL,
                         num_directions = 16L,
                         canaux = c("svf", "openness_pos", "openness_neg")) {
  if (!inherits(mnt, "SpatRaster")) {
    cli::cli_abort("{.arg mnt} doit etre un {.cls SpatRaster}.")
  }
  if (terra::nlyr(mnt) > 1L) {
    mnt <- mnt[[1]]
  }
  canaux <- match.arg(canaux, c("svf", "openness_pos", "openness_neg"),
    several.ok = TRUE
  )
  reso <- terra::res(mnt)
  if (abs(reso[1] - reso[2]) > 1e-6 * reso[1]) {
    cli::cli_warn("Cellules non carrees ({reso[1]} x {reso[2]}) : la resolution
                   {.val {reso[1]}} (axe X) est utilisee pour l'angle vertical.")
  }
  res_m <- reso[1]
  radius_max_px <- max(1, round(radius_m / res_m))
  radius_min_px <- if (is.null(radius_min_m)) 1 else max(1, round(radius_min_m / res_m))

  nr <- terra::nrow(mnt)
  nc <- terra::ncol(mnt)
  z <- terra::values(mnt, mat = FALSE) # ordre ligne-major (comme le noyau Rust)

  want_svf <- "svf" %in% canaux
  want_opos <- "openness_pos" %in% canaux
  want_oneg <- "openness_neg" %in% canaux

  couches <- list()
  # SVF et openness positive sortent du MEME balayage (sur le MNT).
  if (want_svf || want_opos) {
    r <- rvt_svf_opns(
      z, nr, nc, res_m, radius_max_px, radius_min_px,
      num_directions, want_svf, want_opos
    )
    if (want_svf) couches$svf <- r$svf
    if (want_opos) couches$openness_pos <- r$opns
  }
  # Openness negative = openness du MNT INVERSE.
  if (want_oneg) {
    r <- rvt_svf_opns(
      -z, nr, nc, res_m, radius_max_px, radius_min_px,
      num_directions, FALSE, TRUE
    )
    couches$openness_neg <- r$opns
  }

  # Recollage sur la grille du MNT, dans l'ordre demande.
  ordre <- intersect(c("svf", "openness_pos", "openness_neg"), names(couches))
  lyrs <- lapply(ordre, function(nm) {
    rr <- terra::rast(mnt)
    terra::values(rr) <- couches[[nm]]
    names(rr) <- nm
    rr
  })
  out <- do.call(c, lyrs)
  out
}
