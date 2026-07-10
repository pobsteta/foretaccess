# `distance_hors_desserte_max_m` n'est pas un plafond sur la distance de débardage :
# c'est la distance maximale parcourable **hors forêt et hors desserte**. Elle
# permet au skidder de couper par une prairie pour atteindre un massif isolé.
# Reproduit la construction de `Pente_ok_skidder` (Sylvaccess_1_skidder.py).

# Deux massifs séparés par une bande non forestière de 30 m, et une desserte
# verticale dans le massif ouest seulement.
foret_coupee <- function(largeur_bande = 30) {
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

desserte_ouest <- function() {
  sf::st_sf(
    classe = "route",
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(50, 0), c(50, 250))), crs = 2154)
  )
}

pre_coupee <- function(largeur_bande = 30) {
  preprocess(mnt = toy_mnt(), desserte = desserte_ouest(), foret = foret_coupee(largeur_bande))
}

test_that("terrain_roulable ignore la foret, contrairement a zone_roulage", {
  pre <- pre_coupee()

  terrain <- terra::values(terrain_roulable(pre))
  foret <- terra::values(pre$foret_mask)

  # Le jouet est a 20 % de pente : tout le terrain est roulable, foret ou non.
  expect_gt(sum(terrain == 1 & foret == 0), 0)
  # zone_roulage, elle, exige la foret.
  expect_equal(sum(terra::values(zone_roulage(pre)) == 1 & foret == 0), 0)
})

test_that("le saut hors foret connecte le massif isole (defaut 50 m)", {
  pre <- pre_coupee(largeur_bande = 30)
  z <- terra::values(zone_roulable_connectee(pre))

  # Massif est : x > 130. Une cellule bien a l'interieur.
  est <- terra::cellFromXY(pre$mnt, cbind(180, 125))
  expect_equal(z[est], 1)
})

test_that("un saut trop court laisse le massif isole", {
  pre <- pre_coupee(largeur_bande = 30)
  # La bande de 30 m coute 30 x sqrt(1 + 0,2^2) = 30,6 m : 10 m ne suffisent pas.
  cfg <- foretaccess_config(skidder = list(distance_hors_desserte_max_m = 10))
  z <- terra::values(zone_roulable_connectee(pre, cfg))

  est <- terra::cellFromXY(pre$mnt, cbind(180, 125))
  expect_equal(z[est], 0)

  # Le massif ouest, lui, reste connecte.
  ouest <- terra::cellFromXY(pre$mnt, cbind(70, 125))
  expect_equal(z[ouest], 1)
})

test_that("une bande trop large isole le massif meme au defaut", {
  # 60 m de non-foret : au-dela des 50 m autorises.
  pre <- pre_coupee(largeur_bande = 60)
  z <- terra::values(zone_roulable_connectee(pre))

  est <- terra::cellFromXY(pre$mnt, cbind(200, 125))
  expect_equal(z[est], 0)
})

test_that("le saut se repercute sur l'accessibilite du moteur", {
  pre <- pre_coupee(largeur_bande = 30)
  est <- terra::cellFromXY(pre$mnt, cbind(180, 125))

  large <- skidder(pre)
  etroit <- skidder(pre, foretaccess_config(skidder = list(distance_hors_desserte_max_m = 10)))

  # 1 = parcourable ; 3 = non_accessible.
  expect_equal(terra::values(large$accessibilite)[est], 1)
  expect_equal(terra::values(etroit$accessibilite)[est], 3)

  # Et la surface parcourable diminue quand le saut se restreint.
  surf <- function(sk) sk$recap$surface_ha[sk$recap$classe == "parcourable"]
  expect_gt(surf(large), surf(etroit))
})

test_that("zone_roulable_connectee exige une desserte", {
  pre <- pre_coupee()
  pre$desserte <- terra::rast(pre$mnt)
  terra::values(pre$desserte) <- NA_real_
  expect_error(zone_roulable_connectee(pre), regexp = "Aucune cellule de desserte")
})
