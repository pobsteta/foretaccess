# Rasters synthetiques pour tester le moteur skidder (spec 002).
#
# Le jeu jouet du Lot 0 ne suffit pas : sa pente vaut 20 % partout, sous le seuil
# skidder de 30 %. On construit ici des MNT deterministes a pente choisie, en
# memoire (aucune fixture volumineuse a versionner).

# MNT plan incliné selon X : altitude = 100 + pente * x. `pente` est un rapport.
mnt_plan <- function(pente = 0.60, n = 50, res = 5) {
  r <- terra::rast(
    nrows = n, ncols = n, xmin = 0, xmax = n * res, ymin = 0, ymax = n * res,
    crs = "EPSG:2154"
  )
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  terra::values(r) <- 100 + pente * xy[, "x"]
  names(r) <- "altitude"
  r
}

# Desserte : une unique ligne nord-sud a l'abscisse `x`, en raster d'indices.
desserte_ns <- function(gabarit, x = 125) {
  d <- terra::rast(gabarit)
  col <- terra::colFromX(gabarit, x)
  v <- rep(NA_real_, terra::ncell(d))
  cellules <- terra::cellFromRowCol(d, seq_len(terra::nrow(d)), col)
  v[cellules] <- cellules
  terra::values(d) <- v
  d
}

# Zone entierement treuillable, sauf les cellules de desserte.
zone_pleine <- function(gabarit, desserte = NULL) {
  z <- terra::rast(gabarit)
  terra::values(z) <- 1
  if (!is.null(desserte)) {
    z[which(!is.na(terra::values(desserte)))] <- 0
  }
  z
}

# Prétraitement du jeu jouet à pente forte (60 %), avec desserte et forêt du jouet.
toy_preprocess_pente_forte <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) {
      cache <<- preprocess(
        mnt = mnt_plan(0.60),
        desserte = toy_desserte(),
        foret = toy_foret()
      )
    }
    cache
  }
})

# Moteur skidder sur le jouet, memoise (le balayage radial est couteux).
toy_skidder <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) cache <<- skidder(toy_preprocess())
    cache
  }
})
