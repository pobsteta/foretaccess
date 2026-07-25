# Composite CVAT (Combined Visualization for Archaeological Topography) -- la
# combinaison PAR DEFAUT du plugin QGIS RVT (fichier de sortie `*_CVAT_8bit.tif`).
# CVAT n'est pas un empilement simple mais le MELANGE 50/50 de DEUX VAT calcules
# avec des presets de terrain differents :
#
#   CVAT = 0.5 * VAT_general + 0.5 * VAT_flat        (fusion Normal, 50 % / 100 %)
#
# ou VAT_general reprend le preset blender_VAT.json (= vat_default_layers()) et
# VAT_flat le meme empilement avec des parametres "plat" (SVF plus large et moins
# bruite, pentes/openness plus serres, soleil rasant). TRANSCRIT du plugin RVT
# (qrvt.py `_render_advanced_combination` handle "CVAT" + settings/
# default_terrains_settings.json presets "general"/"flat"). Les canaux SVF /
# openness viennent du noyau Rust valide (rvt_svf_opns) ; la pente, l'ombrage et
# la conversion 8 bits sont PORTES au mot pres de rvt/vis.py (slope_aspect,
# hillshade, byte_scale). Valide pixel a pixel contre RVT (data-raw/oracle_rvt.R
# -> tests/testthat/fixtures/cvat_oracle.rds).

# --- Pente / aspect / ombrage : portage de rvt/vis.py (differences centrales) --

# slope_aspect : derivees centrales a 2 cellules avec padding de bord (mode edge),
# comme rvt.vis.slope_aspect (PAS la methode de Horn a 8 voisins de terra::terrain).
# `m` est la grille d'altitude en matrice (lignes = Y descendant, colonnes = X).
# Renvoie pente (radians et degres) et aspect (radians), memes dimensions que `m`.
.rvt_slope_aspect <- function(m, res_x, res_y) {
  nr <- nrow(m)
  nc <- ncol(m)
  # Voisins avec bord repete (edge padding) : gauche/droite (X), haut/bas (Y).
  left <- cbind(m[, 1], m[, -nc, drop = FALSE])
  right <- cbind(m[, -1, drop = FALSE], m[, nc])
  up <- rbind(m[1, ], m[-nr, , drop = FALSE])
  down <- rbind(m[-1, , drop = FALSE], m[nr, ])
  # roll_fill_nans : un voisin NoData mais centre valide -> remplace par le centre
  # (pas de dilatation du NoData dans le gradient, comme RVT).
  fill <- function(nb) {
    idx <- is.na(nb) & !is.na(m)
    nb[idx] <- m[idx]
    nb
  }
  left <- fill(left)
  right <- fill(right)
  up <- fill(up)
  down <- fill(down)
  # RVT : dzdx = (roll(+1) - roll(-1))/2/res ; dzdy = (roll(-1) - roll(+1))/2/res.
  dzdx <- ((left - right) / 2) / res_x
  dzdy <- ((down - up) / 2) / res_y
  tan_slope <- sqrt(dzdx^2 + dzdy^2)
  # Stabilite numerique : dzdy nul -> tangente tres grande (comme RVT, 10e-9).
  dzdy[dzdy == 0] <- 1e-8
  aspect <- atan2(dzdx, dzdy)
  # Masque NaN reapplique sur l'altitude d'origine (slope NaN ssi dem NaN).
  nan <- is.na(m)
  slope_rad <- atan(tan_slope)
  slope_rad[nan] <- NA
  aspect[nan] <- NA
  list(slope_rad = slope_rad, slope_deg = slope_rad * 180 / pi, aspect = aspect)
}

# hillshade : reproduit rvt.vis.hillshade -- padding de bord d'1 pixel PUIS
# slope_aspect (qui re-pad), d'ou un double bord au ras du raster (fidele a RVT).
# `sun_azimuth`/`sun_elevation` en degres. Renvoie [0, 1], negatifs remis a 0.
.rvt_hillshade <- function(m, res_x, res_y, sun_azimuth, sun_elevation) {
  nr <- nrow(m)
  nc <- ncol(m)
  # Padding de bord d'1 pixel (comme RVT avant l'appel a slope_aspect).
  mp <- rbind(m[1, ], m, m[nr, ])
  mp <- cbind(mp[, 1], mp, mp[, nc])
  sa <- .rvt_slope_aspect(mp, res_x, res_y)
  az <- sun_azimuth * pi / 180
  zen <- pi / 2 - sun_elevation * pi / 180
  hs <- cos(zen) * cos(sa$slope_rad) + sin(zen) * sin(sa$slope_rad) * cos(sa$aspect - az)
  hs[hs < 0] <- 0
  # Retire le padding -> dimensions d'origine.
  hs[2:(nr + 1L), 2:(nc + 1L)]
}

# byte_scale : portage de rvt.vis.byte_scale pour data float, bornes [0, 1] (le
# plugin sauve le CVAT 8 bits avec c_min=0, c_max=1). uint8 = TRONCATURE (pas
# arrondi) de (255.9999 * v), ecrete a [0, 255] ; NaN -> 255.
.rvt_byte_scale01 <- function(v) {
  b <- (255 + 0.9999) * v # c_min=0, c_max=1
  b[b > 255] <- 255
  b[b < 0] <- 0
  b <- as.integer(b) # troncature vers zero, comme np.asarray(., uint8)
  b[is.na(v)] <- 255L
  b
}

# --- Presets de terrain (default_terrains_settings.json : general / flat) ------

#' RVT terrain presets used by the CVAT combination
#'
#' Returns the two parameter sets that [vat_combined()] blends -- `general` and
#' `flat` -- transcribed from the RVT QGIS plugin's
#' `settings/default_terrains_settings.json`. Each set carries the SVF/openness
#' search geometry (in **pixels**), the hillshade sun elevation and the four VAT
#' layer stretches; the blend modes, opacities and slope inversion are those of
#' the base VAT ([vat_default_layers()]).
#'
#' @return A named list with elements `general` and `flat`, each a list of
#'   `svf_r_max`, `svf_r_min`, `svf_n_dir`, `sun_elevation`, `sun_azimuth` and a
#'   `layers` spec (as in [vat_default_layers()]) with the terrain-specific
#'   normalization ranges.
#' @seealso [vat_combined()], [vat_default_layers()].
#' @export
cvat_terrain_params <- function() {
  base <- vat_default_layers()
  mk <- function(svf_rng, opns_rng, slp_max) {
    l <- base
    l$svf$min <- svf_rng[1]
    l$svf$max <- svf_rng[2]
    l$openness_pos$min <- opns_rng[1]
    l$openness_pos$max <- opns_rng[2]
    l$slope$min <- 0
    l$slope$max <- slp_max
    l
  }
  list(
    # svf_noise 0 -> r_min = max(round(10*0*0.01),1) = 1
    general = list(
      svf_r_max = 10, svf_r_min = 1, svf_n_dir = 16L,
      sun_elevation = 35, sun_azimuth = 315,
      layers = mk(c(0.7, 1.0), c(68, 93), 50)
    ),
    # svf_noise 3 -> r_min = max(round(20*40*0.01),1) = 8
    flat = list(
      svf_r_max = 20, svf_r_min = 8, svf_n_dir = 16L,
      sun_elevation = 15, sun_azimuth = 315,
      layers = mk(c(0.9, 1.0), c(85, 93), 15)
    )
  )
}

# Rend un VAT (vecteur ligne-major [0,1]) pour un jeu de parametres terrain `p`,
# avec les canaux RVT fideles : SVF/openness du noyau Rust (rayons en PIXELS),
# pente et ombrage portes. `m` = matrice d'altitude, `zrm` = son aplatissement
# ligne-major, `res` = taille de cellule (m).
.vat_render_rvt <- function(m, zrm, nr, nc, res, p) {
  # SVF + openness positive : un seul balayage (rayons en pixels, comme RVT).
  r <- rvt_svf_opns(zrm, nr, nc, res, p$svf_r_max, p$svf_r_min, p$svf_n_dir, TRUE, TRUE)
  # Pente (degres) et ombrage : matrices -> vecteurs ligne-major.
  slope_deg <- as.vector(t(.rvt_slope_aspect(m, res, res)$slope_deg))
  hs <- as.vector(t(.rvt_hillshade(m, res, res, p$sun_azimuth, p$sun_elevation)))
  # Pile HAUT -> BAS : svf, openness+, pente, ombrage.
  mat <- cbind(r$svf, r$opns, slope_deg, hs)
  .rvt_blend_stack(mat, p$layers)
}

#' CVAT composite (Combined VAT) from a DEM -- RVT QGIS default
#'
#' Reproduces the RVT QGIS plugin's default archaeological product, **CVAT**
#' (Combined Visualization for Archaeological Topography): the 50/50 blend of two
#' [vat_archeo()]-style VATs computed with the `general` and `flat` terrain
#' presets. It adapts to both flat and steep ground far better than a single VAT.
#'
#' @details
#' The SVF and positive-openness channels come from the validated Rust kernel
#' [rvt_svf_opns()] (search radii taken **in pixels** from the terrain preset);
#' slope, hillshade and the 8-bit conversion are ported to the letter from
#' `rvt/vis.py` (`slope_aspect`, `hillshade`, `byte_scale`) -- RVT uses 2-cell
#' central differences with edge padding, **not** `terra`'s Horn slope. Feed a
#' DEM at **1 m or finer** (the 0.5 m IGN LiDAR HD DTM). Validated pixel-to-pixel
#' against the RVT oracle (`data-raw/oracle_rvt.R`).
#'
#' @param mnt Digital terrain model as a single-layer `SpatRaster` (square cells;
#'   the first layer is used if several).
#' @param params Terrain parameter sets, default [cvat_terrain_params()].
#' @param as_byte If `TRUE`, return the 8-bit raster (`0..255`, `NA`->255) as the
#'   plugin writes it (`*_CVAT_8bit.tif`); if `FALSE` (default), the float
#'   composite in `[0, 1]`.
#' @return A single-layer `SpatRaster` named `cvat`, aligned to `mnt`.
#' @seealso [vat_archeo()] (single VAT), [cvat_terrain_params()], [blend_rvt()].
#' @export
#' @examples
#' mnt <- terra::rast(nrows = 30, ncols = 30, xmin = 0, xmax = 30,
#'                    ymin = 0, ymax = 30, crs = "EPSG:2154")
#' terra::values(mnt) <- 100 + as.vector(terra::rowFromCell(mnt, 1:900)) * 0.2
#' cvat <- vat_combined(mnt)
#' names(cvat)
vat_combined <- function(mnt, params = cvat_terrain_params(), as_byte = FALSE) {
  if (!inherits(mnt, "SpatRaster")) {
    cli::cli_abort("{.arg mnt} doit etre un {.cls SpatRaster}.")
  }
  if (terra::nlyr(mnt) > 1L) {
    mnt <- mnt[[1]]
  }
  reso <- terra::res(mnt)
  if (abs(reso[1] - reso[2]) > 1e-6 * reso[1]) {
    cli::cli_warn("Cellules non carrees : resolution {.val {reso[1]}} (axe X) utilisee.")
  }
  res_m <- reso[1]
  nr <- terra::nrow(mnt)
  nc <- terra::ncol(mnt)
  m <- terra::as.matrix(mnt, wide = TRUE) # grille spatiale (nr x nc)
  zrm <- as.vector(t(m)) # aplatissement ligne-major (comme le noyau Rust)

  vat_general <- .vat_render_rvt(m, zrm, nr, nc, res_m, params$general)
  vat_flat <- .vat_render_rvt(m, zrm, nr, nc, res_m, params$flat)
  # CVAT = fond VAT_flat (100 %) + VAT_general en Normal 50 % = moyenne 50/50.
  cvat <- 0.5 * vat_general + 0.5 * vat_flat

  out <- terra::rast(mnt)
  if (as_byte) {
    terra::values(out) <- .rvt_byte_scale01(cvat)
  } else {
    terra::values(out) <- cvat
  }
  names(out) <- "cvat"
  out
}
