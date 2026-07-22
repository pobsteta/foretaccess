# Pont volume : `volume_depuis_p1()` projette un `sf` d'unites portant un volume
# en m3/ha (typiquement l'indicateur P1 de Nemeton) sur la grille du MNT, pour
# alimenter `preprocess(volume = )` puis le moteur cable.

# Deux parcelles cote a cote sur une grille 10x10 a 10 m, avec un volume/ha.
parcelles_p1 <- function(champ = "P1", v = c(200, 350)) {
  carre <- function(x0, x1) {
    sf::st_polygon(list(rbind(
      c(x0, 0), c(x1, 0), c(x1, 100), c(x0, 100), c(x0, 0)
    )))
  }
  d <- sf::st_sf(
    geometry = sf::st_sfc(carre(0, 50), carre(50, 100), crs = 2154)
  )
  d[[champ]] <- v
  d
}

mnt_grille <- function() {
  r <- terra::rast(
    nrows = 10, ncols = 10, xmin = 0, xmax = 100, ymin = 0, ymax = 100,
    crs = "EPSG:2154"
  )
  terra::values(r) <- 100
  names(r) <- "altitude"
  r
}

test_that("volume_depuis_p1 rend un raster aligne, nomme volume, en m3/ha", {
  r <- suppressMessages(volume_depuis_p1(parcelles_p1(), mnt_grille()))

  expect_s4_class(r, "SpatRaster")
  expect_equal(names(r), "volume")
  expect_equal(as.vector(terra::ext(r)), as.vector(terra::ext(mnt_grille())))
  expect_equal(terra::res(r), terra::res(mnt_grille()))

  # La valeur des cellules est celle de la parcelle qui les contient (m3/ha).
  vals <- terra::values(r)[, 1]
  expect_setequal(stats::na.omit(unique(vals)), c(200, 350))
  # Moitie ouest a 200, moitie est a 350.
  ouest <- terra::extract(r, cbind(25, 50))[, 1]
  est <- terra::extract(r, cbind(75, 50))[, 1]
  expect_equal(ouest, 200)
  expect_equal(est, 350)
})

test_that("la couche produite alimente preprocess() et donne du volume au cable", {
  mnt <- mnt_grille()
  vol <- suppressMessages(volume_depuis_p1(parcelles_p1(), mnt))
  desserte <- sf::st_sf(
    classe = "route",
    geometry = sf::st_sfc(
      sf::st_linestring(rbind(c(5, 50), c(15, 50))), crs = 2154
    )
  )
  foret <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(rbind(
    c(0, 0), c(100, 0), c(100, 100), c(0, 100), c(0, 0)
  ))), crs = 2154))

  pre <- preprocess(mnt = mnt, desserte = desserte, foret = foret, volume = vol)
  expect_false(is.null(pre$volume))
  expect_equal(names(pre$volume), "volume")
})

test_that("un champ absent est signale, avec les champs disponibles", {
  expect_error(
    volume_depuis_p1(parcelles_p1(champ = "P1"), mnt_grille(), champ = "volume"),
    "n'a pas de champ"
  )
})

test_that("un volume par defaut cherche bien la colonne P1", {
  # Sans `champ`, on lit P1 : le defaut colle a la sortie de Nemeton.
  r <- suppressMessages(volume_depuis_p1(parcelles_p1(champ = "P1"), mnt_grille()))
  expect_true(any(!is.na(terra::values(r))))
})

test_that("un champ non numerique ou tout-NA ou negatif est refuse", {
  txt <- parcelles_p1()
  txt$P1 <- c("a", "b")
  expect_error(volume_depuis_p1(txt, mnt_grille()), "numerique")

  na <- parcelles_p1(v = c(NA_real_, NA_real_))
  expect_error(volume_depuis_p1(na, mnt_grille()), "NA")

  neg <- parcelles_p1(v = c(-10, 200))
  expect_error(volume_depuis_p1(neg, mnt_grille()), "negativ")
})

test_that("le CRS doit correspondre a celui du MNT, sans reprojection implicite", {
  p1 <- parcelles_p1()
  sans_crs <- sf::st_set_crs(p1, NA)
  expect_error(volume_depuis_p1(sans_crs, mnt_grille()), "CRS")

  autre <- sf::st_transform(p1, 4326)
  expect_error(volume_depuis_p1(autre, mnt_grille()), "CRS")
})

test_that("une couche vide est refusee", {
  expect_error(
    volume_depuis_p1(parcelles_p1()[0, ], mnt_grille()),
    "vide"
  )
})

test_that("les cellules hors unite sont NA, pas zero (pas de bois != bois nul)", {
  # Une seule petite parcelle : le reste de la grille doit rester NA.
  petite <- sf::st_sf(
    P1 = 300,
    geometry = sf::st_sfc(sf::st_polygon(list(rbind(
      c(0, 0), c(20, 0), c(20, 20), c(0, 20), c(0, 0)
    ))), crs = 2154)
  )
  r <- suppressMessages(volume_depuis_p1(petite, mnt_grille()))
  vals <- terra::values(r)[, 1]
  expect_true(any(is.na(vals)))
  expect_false(any(vals == 0, na.rm = TRUE))
})
