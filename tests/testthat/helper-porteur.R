# Fixtures deterministes pour le moteur porteur (spec 003), en memoire.
#
# Sur un plan incliné selon X (`mnt_plan`), l'altitude croît vers l'est : l'exposition
# pointe vers l'ouest (270°). Rouler **est-ouest** est donc dans le sens de la pente
# (aucun devers) ; rouler **nord-sud** est en travers (devers maximal). Ce seul plan
# suffit a exercer les trois regimes du devers (CA-3.2).

# Foret couvrant tout le gabarit.
foret_pleine <- function(gabarit) {
  e <- terra::ext(gabarit)
  sf::st_sf(
    id = 1,
    geometry = sf::st_sfc(sf::st_polygon(list(rbind(
      c(e[1], e[3]), c(e[2], e[3]), c(e[2], e[4]), c(e[1], e[4]), c(e[1], e[3])
    ))), crs = 2154)
  )
}

# Desserte : une unique cellule de route, au centre d'un gabarit, en raster d'indices.
# Les rayons de conduite fanent alors dans tous les azimuts depuis ce point.
desserte_point <- function(gabarit, x, y) {
  d <- terra::rast(gabarit)
  v <- rep(NA_real_, terra::ncell(d))
  cel <- terra::cellFromXY(gabarit, cbind(x, y))
  v[cel] <- cel
  terra::values(d) <- v
  d
}

# Pretraitement sur un plan incline, foret pleine, desserte a fournir a part. On
# construit via preprocess() pour obtenir pente et exposition, puis on impose la
# desserte-point (preprocess rasterise une desserte vectorielle, moins commode ici).
pre_plan <- function(pente = 0.20, n = 41, res = 5, x_route = NULL, y_route = NULL) {
  mnt <- mnt_plan(pente = pente, n = n, res = res)
  # Desserte factice pour satisfaire preprocess ; remplacee juste apres.
  d0 <- sf::st_sf(
    classe = "route",
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(res, res), c(2 * res, res))), crs = 2154)
  )
  pre <- preprocess(mnt = mnt, desserte = d0, foret = foret_pleine(mnt))

  centre <- n * res / 2
  pre$desserte <- desserte_point(
    mnt,
    if (is.null(x_route)) centre else x_route,
    if (is.null(y_route)) centre else y_route
  )
  pre
}

# Zone conduisible : tout sauf la cellule de desserte (comme zone_pleine du skidder).
zone_conduite <- function(pre) {
  z <- terra::rast(pre$mnt)
  terra::values(z) <- 1
  z[which(!is.na(terra::values(pre$desserte)))] <- 0
  z
}
