# Saut hors foret du porteur (spec 003 §4, `Pente_ok_forwarder`) : le porteur peut couper
# par un terrain recoltable non forestier, borne a `distance_hors_desserte_max_m`, pour
# rejoindre un massif isole. Et la zone de conduite est bornee par max(...), pas min(...).

test_that("la zone de conduite borne la pente par le max des trois seuils, pas le min", {
  # Plan a 20 %, sens de la pente (montee, seuil 30 %). Avec min(15,30,25)=15 %, ces
  # cellules seraient exclues a tort ; avec max(...)=30 %, elles sont dans la zone.
  pre <- pre_plan(pente = 0.20, n = 41)
  z <- terra::values(.zone_conduite(pre, foretaccess_config()))

  # A 20 % de pente uniforme, toute la foret est dans la zone (20 < 30), rien ne l'est
  # sous une borne a 15 %.
  expect_gt(sum(z == 1), 0.9 * terra::ncell(pre$mnt))
})

test_that("au-dela du max des seuils, la cellule sort de la zone", {
  # Plan a 45 % : au-dessus de max(15,30,40)=40 %. Aucune cellule conduisible.
  pre <- pre_plan(pente = 0.45, n = 41)
  z <- terra::values(.zone_conduite(pre, foretaccess_config()))
  expect_equal(sum(z == 1), 0)
})

# Deux massifs a plat separes par une bande non forestiere ; desserte dans le massif ouest.
foret_deux_massifs <- function(largeur_bande = 30) {
  bord <- 100
  rect <- function(x1, x2) {
    sf::st_polygon(list(rbind(
      c(x1, 25), c(x2, 25), c(x2, 225), c(x1, 225), c(x1, 25)
    )))
  }
  sf::st_sf(
    id = 1:2,
    geometry = sf::st_sfc(rect(25, bord), rect(bord + largeur_bande, 225), crs = 2154)
  )
}

pre_deux_massifs <- function(largeur_bande = 30) {
  mnt <- terra::rast(nrows = 50, ncols = 50, xmin = 0, xmax = 250, ymin = 0, ymax = 250,
    crs = "EPSG:2154")
  terra::values(mnt) <- 100 # plat : pas de contrainte de pente ni de devers
  desserte <- sf::st_sf(classe = "route",
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(50, 0), c(50, 250))), crs = 2154))
  preprocess(mnt = mnt, desserte = desserte, foret = foret_deux_massifs(largeur_bande))
}

test_that("le saut inclut la bande non forestiere dans la zone (defaut 200 m)", {
  # Les deux massifs sont forestiers, donc toujours dans la zone : ce que le saut change,
  # c'est l'inclusion de la bande *non forestiere* qui les separe -- elle seule permet au
  # balayage de traverser.
  pre <- pre_deux_massifs(largeur_bande = 30)
  z <- terra::values(.zone_conduite(pre, foretaccess_config()))

  # Le centre de la bande (x = 115), a 15 m de chaque lisiere, est dans la zone au defaut.
  bande <- terra::cellFromXY(pre$mnt, cbind(115, 125))
  expect_equal(z[bande], 1)
})

test_that("un saut plafonne laisse un trou au centre d'une bande trop large", {
  pre <- pre_deux_massifs(largeur_bande = 30)
  cfg <- foretaccess_config(porteur = list(distance_hors_desserte_max_m = 10))
  z <- terra::values(.zone_conduite(pre, cfg))

  # Bande de 30 m, saut de 10 m depuis chaque lisiere : le centre (15 m des deux) reste
  # hors zone -- le balayage ne peut plus traverser.
  bande <- terra::cellFromXY(pre$mnt, cbind(115, 125))
  expect_equal(z[bande], 0)
})

test_that("le saut se repercute sur l'accessibilite du porteur", {
  large <- porteur(pre_deux_massifs(largeur_bande = 30))
  etroit <- porteur(pre_deux_massifs(largeur_bande = 30),
    foretaccess_config(porteur = list(distance_hors_desserte_max_m = 10)))

  est <- terra::cellFromXY(large$accessibilite, cbind(180, 125))
  # 1 = parcourable, 3 = non_accessible.
  expect_equal(terra::values(large$accessibilite)[est], 1)
  expect_equal(terra::values(etroit$accessibilite)[est], 3)
})

test_that("le saut hors foret est neutre quand il n'y a pas de foret", {
  pre <- pre_plan(pente = 0.10, n = 21)
  pre$foret_mask <- terra::rast(pre$mnt)
  terra::values(pre$foret_mask) <- 0
  z <- terra::values(.zone_conduite(pre, foretaccess_config()))
  # Sans foret, aucun contour, aucun saut : zone vide.
  expect_equal(sum(z == 1), 0)
})
