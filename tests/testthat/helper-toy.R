# Accès au jeu de données jouet (Lot 0) et fixtures dérivées.
#
# Le MNT jouet est un plan incliné de 20 % vers l'est, en Lambert-93 (EPSG:2154),
# 50 x 50 cellules de 5 m. Il sert d'oracle analytique au Lot 1 (spec 001 §6).

toy_dir <- function() system.file("extdata", "toy", package = "foretaccess")

toy_file <- function(nom) file.path(toy_dir(), nom)

toy_mnt <- function() terra::rast(toy_file("mnt.tif"))

toy_desserte <- function() sf::st_read(toy_file("desserte.gpkg"), quiet = TRUE)

toy_foret <- function() sf::st_read(toy_file("foret.gpkg"), quiet = TRUE)

# Obstacles synthétiques : un carré de 50 m dans le coin sud-ouest de la forêt.
toy_obstacles <- function(xmin = 50, ymin = 50, cote = 50) {
  carre <- sf::st_polygon(list(rbind(
    c(xmin, ymin),
    c(xmin + cote, ymin),
    c(xmin + cote, ymin + cote),
    c(xmin, ymin + cote),
    c(xmin, ymin)
  )))
  sf::st_sf(id = 1L, geometry = sf::st_sfc(carre, crs = 2154))
}

# Raster de volume aligné sur la grille du MNT (valeur constante).
toy_volume <- function(valeur = 250) {
  v <- terra::rast(toy_mnt())
  terra::values(v) <- valeur
  v
}

# Prétraitement du jeu jouet, mémoïsé pour éviter de le recalculer par test.
toy_preprocess <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) {
      cache <<- preprocess(
        mnt = toy_mnt(),
        desserte = toy_desserte(),
        foret = toy_foret()
      )
    }
    cache
  }
})
