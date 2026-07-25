# Composite VAT (Visualization for Archaeological Topography, Kokalj & Somrak
# 2019 ; RVT / ZRC SAZU, Apache 2.0). Le VAT n'est pas un canal unique mais un
# EMPILEMENT fusionne : sky-view factor + openness positive + pente + ombrage,
# chacun normalise puis compose avec un mode de fusion et une opacite. Le calcul
# lourd (balayage d'horizon) vit deja dans le crate Rust via micro_relief() ; ici
# tout est de l'arithmetique element-par-element sur des rasters (regle stricte 3
# : pas de nouvelle surface Rust pour du compositing trivial).
#
# Les valeurs par defaut de vat_default_layers() sont EPINGLEES au preset livre
# par RVT : settings/blender_VAT.json ("VAT - Archaeological") -- SVF [0.7,1.0]
# Multiply 25 %, Openness+ [68,93] Overlay 50 %, Slope [0,50] Luminosity 50 %
# (echelle inversee, comme normalize_image), Hillshade [0,1] Normal 100 %. La
# mecanique de fusion et ces constantes sont validees pixel-a-pixel contre RVT_py
# (data-raw/oracle_rvt.R -> tests/testthat/fixtures/vat_oracle.rds).

# --- Mecanique de fusion (math pure sur vecteurs, testable sans SIG) ----------

# Etirement lineaire vers [0, 1] avec ecretage ; NA propage. `invert` renverse
# le canal (ex. pente : terrain plat -> clair).
.rvt_normalize <- function(x, vmin, vmax, invert = FALSE) {
  y <- pmin(pmax((x - vmin) / (vmax - vmin), 0), 1)
  if (invert) y <- 1 - y
  y
}

# Modes de fusion RVT sur niveaux de gris normalises [0, 1] (top sur background).
# Ensemble et formules transcrits AU MOT PRES de rvt/blend_func.py (Apache 2.0) :
# blend_normal / _multiply / _screen / _overlay / _soft_light + blend_luminosity.
# Pour du niveau de gris la luminosite du fond vaut le fond lui-meme, donc
# "luminosity" se reduit a "normal" (le canal du dessus remplace) : garde nomme
# pour coller au vocabulaire RVT (lum(2D) == 2D dans blend_func).
.rvt_blend_pair <- function(top, bg, mode) {
  switch(mode,
    normal     = top,
    multiply   = top * bg,
    screen     = 1 - (1 - top) * (1 - bg),
    # blend_overlay : branche sur background (> 0.5), comme RVT.
    overlay    = ifelse(bg > 0.5, 1 - (1 - 2 * (bg - 0.5)) * (1 - top), 2 * bg * top),
    # blend_soft_light : branche sur active (top < 0.5), comme RVT.
    soft_light = ifelse(top < 0.5,
      2 * bg * top + bg^2 * (1 - 2 * top),
      2 * bg * (1 - top) + sqrt(bg) * (2 * top - 1)
    ),
    luminosity = top,
    cli::cli_abort("Mode de fusion inconnu : {.val {mode}}.")
  )
}

# Modes dont blend_func MUTE `background` en place (overlay, soft_light) : dans le
# fold de RVT, render_images recoit alors `top == background`, ce qui NEUTRALISE
# l'opacite (la couche s'applique a 100 %). Reproduit tel quel pour un VAT
# identique a RVT -- NE PAS "corriger" : dans le preset VAT, l'Openness+ en
# Overlay 50 % vaut en realite 100 %. Verifie a l'oracle (data-raw/oracle_rvt.R).
.rvt_opacite_neutralisee <- c("overlay", "soft_light")

# Repli d'une pile de canaux (colonnes de `m`, ordre HAUT -> BAS) en une seule
# image [0, 1]. Le canal du bas sert de fond ; on compose vers le haut :
# res <- opacite * fusion(canal, res) + (1 - opacite) * res, sauf pour les modes
# a opacite neutralisee ou res <- fusion(canal, res).
.rvt_blend_stack <- function(m, specs) {
  n <- length(specs)
  norm_col <- function(k) {
    s <- specs[[k]]
    .rvt_normalize(m[, k], s$min, s$max, isTRUE(s$invert))
  }
  res <- norm_col(n) # fond = canal du bas
  if (n > 1L) {
    for (k in seq.int(n - 1L, 1L)) {
      s <- specs[[k]]
      blended <- .rvt_blend_pair(norm_col(k), res, s$mode)
      res <- if (s$mode %in% .rvt_opacite_neutralisee) {
        blended
      } else {
        s$opacity * blended + (1 - s$opacity) * res
      }
    }
  }
  res
}

# --- API publique -------------------------------------------------------------

#' Default RVT layer stack for the Archaeological (VAT) blend
#'
#' Returns the layer specification of the **Visualization for Archaeological
#' Topography** blend: sky-view factor, positive openness, slope and hillshade,
#' stacked **top to bottom** with per-layer normalization range, blend mode and
#' opacity. These defaults are **pinned to RVT's shipped `blender_VAT.json`**
#' preset (`VAT - Archaeological`) and validated pixel-to-pixel against the
#' RVT_py oracle (`data-raw/oracle_rvt.R`).
#'
#' @return A named list of four layer specs, each a list with `name`, `min`,
#'   `max`, `invert`, `mode` and `opacity`, ordered top (rendered over) to bottom
#'   (base canvas). Field `name` maps to the channels [vat_archeo()] computes:
#'   `"svf"`, `"openness_pos"`, `"slope"`, `"hillshade"`.
#' @seealso [vat_archeo()], [blend_rvt()].
#' @export
vat_default_layers <- function() {
  list(
    svf          = list(name = "svf",          min = 0.7, max = 1.0, invert = FALSE, mode = "multiply",   opacity = 0.25),
    openness_pos = list(name = "openness_pos", min = 68,  max = 93,  invert = FALSE, mode = "overlay",    opacity = 0.50),
    slope        = list(name = "slope",        min = 0,   max = 50,  invert = TRUE,  mode = "luminosity", opacity = 0.50),
    hillshade    = list(name = "hillshade",    min = 0,   max = 1,   invert = FALSE, mode = "normal",     opacity = 1.00)
  )
}

#' Layered RVT blend of a channel stack into a single composite
#'
#' Folds a multi-layer `SpatRaster` -- ordered **top to bottom** -- into one
#' grayscale composite in `[0, 1]`, following the RVT blending model: each layer
#' is linearly normalized (with optional inversion), fused with the accumulated
#' background through its blend mode, then alpha-composited by its opacity. The
#' bottom layer is the base canvas. Thin GIS wrapper: the arithmetic runs on the
#' extracted cell values (mirroring [micro_relief()]).
#'
#' @param stack A `SpatRaster` whose layers are the channels to blend, in the
#'   **same order** as `layers` (layer 1 = top, last layer = bottom / base).
#' @param layers A list of per-layer specs (see [vat_default_layers()]); each is
#'   a list with `min`, `max`, `invert`, `mode` (`"normal"`, `"multiply"`,
#'   `"screen"`, `"overlay"`, `"soft_light"`, `"luminosity"` -- RVT's mode set)
#'   and `opacity` (0..1). Must have one entry per layer of `stack`.
#' @return A single-layer `SpatRaster` named `vat`, values in `[0, 1]`, aligned to
#'   `stack`; `NA` where any contributing layer is `NA`.
#' @details
#' Reproduces RVT's blend faithfully, **including** the quirk that `"overlay"`
#' and `"soft_light"` mutate the background in place, which **neutralizes their
#' opacity** (the layer applies at 100%). This is intentional -- it keeps the
#' output identical to RVT's own VAT -- and is pinned to the RVT_py oracle
#' (`data-raw/oracle_rvt.R`); do not "fix" it.
#' @seealso [vat_archeo()], [vat_default_layers()].
#' @export
blend_rvt <- function(stack, layers) {
  if (!inherits(stack, "SpatRaster")) {
    cli::cli_abort("{.arg stack} doit etre un {.cls SpatRaster}.")
  }
  if (terra::nlyr(stack) != length(layers)) {
    cli::cli_abort(
      "{.arg stack} a {terra::nlyr(stack)} couche{?s} mais {.arg layers} en
       decrit {length(layers)} : il en faut autant."
    )
  }
  m <- terra::values(stack, mat = TRUE)
  vat_vals <- .rvt_blend_stack(m, layers)
  out <- terra::rast(stack[[1]])
  terra::values(out) <- vat_vals
  names(out) <- "vat"
  out
}

#' VAT composite (Visualization for Archaeological Topography) from a DEM
#'
#' Builds the **VAT** blend (Kokalj & Somrak 2019) from a digital terrain model:
#' it derives the four RVT channels -- **sky-view factor** and **positive
#' openness** via the Rust kernel [micro_relief()], **slope** and analytical
#' **hillshade** via `terra` -- then fuses them with [blend_rvt()] into a single
#' grayscale composite that reveals micro-relief (platforms, embankments,
#' ditches, mounds) far better than any single visualization.
#'
#' @details
#' Feed a DEM at **1 m or finer** -- ideally the 0.5 m IGN LiDAR HD DTM (see
#' [acquire_desserte_lidar()]); coarser grids wash out the signal.
#'
#' The default layer stack ([vat_default_layers()]) reproduces RVT's shipped
#' `VAT - Archaeological` preset (`blender_VAT.json`); both the blend machinery
#' and the constants are validated pixel-to-pixel against the RVT_py oracle (as
#' done for [rvt_svf_opns()]). Note that the slope layer is rendered on an
#' **inverted** scale (steep = dark, per RVT's `normalize_image`) and that the
#' Overlay layer's opacity is neutralized (see [blend_rvt()]). Override `layers`
#' to experiment.
#'
#' @param mnt Digital terrain model as a single-layer `SpatRaster` (square cells;
#'   the first layer is used if several).
#' @param radius_m Maximal horizon search radius in metres for the SVF/openness
#'   channels. Default 10.
#' @param num_directions Number of azimuth directions swept. Default 16.
#' @param sun_azimuth Hillshade illumination azimuth in degrees (0 = North,
#'   clockwise). Default 315.
#' @param sun_elevation Hillshade illumination elevation above the horizon, in
#'   degrees. Default 35.
#' @param layers Layer specification passed to [blend_rvt()]; its `name` fields
#'   must be a subset of `"svf"`, `"openness_pos"`, `"slope"`, `"hillshade"`.
#'   Default [vat_default_layers()].
#' @return A single-layer `SpatRaster` named `vat`, values in `[0, 1]`, aligned to
#'   `mnt`.
#' @seealso [micro_relief()] (SVF/openness kernel), [blend_rvt()] (the blend),
#'   [vat_default_layers()] (default recipe).
#' @export
#' @examples
#' mnt <- terra::rast(nrows = 30, ncols = 30, xmin = 0, xmax = 30,
#'                    ymin = 0, ymax = 30, crs = "EPSG:2154")
#' terra::values(mnt) <- 100 + as.vector(terra::rowFromCell(mnt, 1:900)) * 0.2
#' vat <- vat_archeo(mnt, radius_m = 5)
#' names(vat)
vat_archeo <- function(mnt, radius_m = 10, num_directions = 16L,
                       sun_azimuth = 315, sun_elevation = 35,
                       layers = vat_default_layers()) {
  if (!inherits(mnt, "SpatRaster")) {
    cli::cli_abort("{.arg mnt} doit etre un {.cls SpatRaster}.")
  }
  if (terra::nlyr(mnt) > 1L) {
    mnt <- mnt[[1]]
  }
  noms <- vapply(layers, function(s) s$name, character(1))
  connus <- c("svf", "openness_pos", "slope", "hillshade")
  if (!all(noms %in% connus)) {
    inconnu <- setdiff(noms, connus)
    cli::cli_abort("Canaux inconnus dans {.arg layers} : {.val {inconnu}}.")
  }

  # SVF + openness positive : un seul balayage Rust (via l'enveloppe terra).
  besoin_mr <- intersect(c("svf", "openness_pos"), noms)
  canaux <- list()
  if (length(besoin_mr)) {
    mr <- micro_relief(mnt,
      radius_m = radius_m, num_directions = num_directions,
      canaux = besoin_mr
    )
    for (nm in besoin_mr) canaux[[nm]] <- mr[[nm]]
  }
  # Pente (degres) et ombrage analytique : terra suffit.
  if ("slope" %in% noms || "hillshade" %in% noms) {
    sa <- terra::terrain(mnt, v = c("slope", "aspect"), unit = "radians")
    if ("slope" %in% noms) {
      canaux$slope <- terra::terrain(mnt, v = "slope", unit = "degrees")
    }
    if ("hillshade" %in% noms) {
      canaux$hillshade <- terra::shade(
        sa[["slope"]], sa[["aspect"]],
        angle = sun_elevation, direction = sun_azimuth
      )
    }
  }

  # Recolle les couches dans l'ordre HAUT -> BAS decrit par `layers`.
  # terra::rast(liste) combine des SpatRaster mono-couche (dispatch S4 fiable,
  # contrairement a do.call(c, .)).
  stack <- terra::rast(lapply(noms, function(nm) canaux[[nm]]))
  blend_rvt(stack, layers)
}
