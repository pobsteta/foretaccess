# Fixtures pour le camion DFCI (spec 006), en memoire.
#
# `.sources_dfci` lit le raster `pre$desserte` comme un raster CATEGORIEL (codes
# route=1, piste=2, dfci=3), pas comme le raster d'indices de `desserte_point`.
# On construit donc une desserte categorielle avec une cellule de la classe
# voulue, sur un plan incline (pente et exposition venant de preprocess()).

# Pretraitement sur plan incline avec une unique cellule de desserte de `classe`
# (defaut "dfci") au centre. Reutilise `pre_plan` (helper-porteur) pour la
# geometrie, puis remplace la desserte par un raster categoriel a une cellule.
pre_plan_dfci <- function(pente = 0.05, n = 61, res = 5, classe = "dfci") {
  pre <- pre_plan(pente = pente, n = n, res = res)
  classes <- c("route", "piste", "dfci")
  code <- match(classe, classes)

  d <- terra::rast(pre$mnt)
  v <- rep(NA_real_, terra::ncell(d))
  centre <- n * res / 2
  cel <- terra::cellFromXY(pre$mnt, cbind(centre, centre))
  v[cel] <- code
  terra::values(d) <- v
  levels(d) <- data.frame(value = seq_along(classes), classe = classes)
  names(d) <- "desserte"
  pre$desserte <- d
  pre
}
