# Grilles synthetiques pour tester le service least-cost (spec 002 §4.1).
# Cout uniforme a 1 : le cout cumule doit valoir la distance euclidienne.

grille_test <- function(n = 21, res = 1) {
  terra::rast(
    nrows = n, ncols = n, xmin = 0, xmax = n * res, ymin = 0, ymax = n * res,
    crs = "EPSG:2154"
  )
}

cout_uniforme <- function(n = 21, valeur = 1) {
  r <- grille_test(n)
  terra::values(r) <- valeur
  r
}

source_centrale <- function(n = 21, id = 1) {
  s <- terra::rast(grille_test(n))
  s[(n + 1) / 2, (n + 1) / 2] <- id
  s
}
