# Agregation zonale des surfaces/volumes par zone (spec 008, US-8.2).

# Deux zones couvrant l'emprise : moitie ouest / moitie est.
zones_moities <- function(gabarit, ids = c("ouest", "est")) {
  e <- terra::ext(gabarit)
  xm <- (e[1] + e[2]) / 2
  crs <- terra::crs(gabarit)
  za <- sf::st_as_sf(terra::as.polygons(terra::ext(e[1], xm, e[3], e[4]), crs = crs))
  zb <- sf::st_as_sf(terra::as.polygons(terra::ext(xm, e[2], e[3], e[4]), crs = crs))
  z <- rbind(za, zb)
  z$nom <- ids
  z[, "nom"]
}

test_that("l'agregation zonale conserve la surface totale (CA US-8.2)", {
  pre <- toy_preprocess()
  sk <- skidder(pre)
  zones <- zones_moities(pre$mnt)

  agg <- agreger_zones(sk$accessibilite, zones, id = "nom")
  expect_s3_class(agg, "foretaccess_agregation")
  expect_s3_class(agg, "sf")
  expect_equal(nrow(agg), 2)

  # La somme des surfaces zonales egale la surface de l'emprise (les deux moities
  # couvrent tout, sans recouvrement).
  aire_totale <- terra::ncell(pre$mnt) * prod(terra::res(pre$mnt)) / 10000
  expect_equal(sum(agg$surface_totale_ha), aire_totale, tolerance = 1e-6)
})

test_that("les surfaces zonales par classe egalent le recap global (partition)", {
  pre <- toy_preprocess()
  sk <- skidder(pre)
  zones <- zones_moities(pre$mnt)
  agg <- agreger_zones(sk$accessibilite, zones, id = "nom")

  rec <- recapituler(sk$accessibilite)
  # Pour chaque classe, la somme des colonnes zonales egale la surface globale.
  for (i in seq_len(nrow(rec))) {
    lab <- gsub("[^a-z0-9]+", "_", tolower(rec$classe[i]))
    col <- paste0("surface_", lab, "_ha")
    expect_true(col %in% names(agg), info = col)
    expect_equal(sum(agg[[col]]), rec$surface_ha[i], tolerance = 1e-6, info = col)
  }
})

test_that("le volume est agrege par zone quand il est fourni", {
  pre <- preprocess(
    mnt = toy_mnt(), desserte = toy_desserte(), foret = toy_foret(),
    volume = toy_volume(250)
  )
  sk <- skidder(pre)
  zones <- zones_moities(pre$mnt)
  agg <- agreger_zones(sk$accessibilite, zones, volume = pre$volume, id = "nom")

  vcols <- grep("^volume_.*_m3$", names(agg), value = TRUE)
  expect_gt(length(vcols), 0)
  # Le volume total agrege egale le volume global (le raster de volume est constant).
  vol_global <- sum(as.numeric(terra::values(pre$volume)), na.rm = TRUE)
  vol_agrege <- sum(vapply(vcols, function(c) sum(agg[[c]]), numeric(1)))
  expect_equal(vol_agrege, vol_global, tolerance = 1e-6)
})

test_that("un identifiant de zone est ajoute par defaut", {
  pre <- toy_preprocess()
  sk <- skidder(pre)
  zones <- zones_moities(pre$mnt)
  zones$nom <- NULL # retire l'identifiant fourni

  agg <- agreger_zones(sk$accessibilite, zones)
  expect_true("zone_id" %in% names(agg))
  expect_equal(agg$zone_id, 1:2)
})

test_that("l'agregation fonctionne sur la sortie DFCI", {
  pre <- toy_preprocess()
  df <- camion_dfci(pre)
  zones <- zones_moities(pre$mnt)
  agg <- agreger_zones(df$accessibilite, zones, id = "nom")
  expect_true("surface_defendable_ha" %in% names(agg))
  expect_true("surface_hors_foret_ha" %in% names(agg))
})

test_that("agreger_zones exige un raster categoriel et un sf avec CRS", {
  pre <- toy_preprocess()
  sk <- skidder(pre)
  zones <- zones_moities(pre$mnt)

  # Raster non categoriel.
  expect_error(agreger_zones(pre$mnt, zones, id = "nom"), regexp = "categoriel")
  # Zones sans CRS.
  z2 <- sf::st_set_crs(zones, NA)
  expect_error(agreger_zones(sk$accessibilite, z2, id = "nom"), regexp = "CRS")
})

test_that("une zone disjointe du raster a des surfaces nulles", {
  pre <- toy_preprocess()
  sk <- skidder(pre)
  e <- terra::ext(pre$mnt)
  # Une zone loin a l'est de l'emprise + une zone couvrant tout.
  loin <- sf::st_as_sf(terra::as.polygons(
    terra::ext(e[2] + 1000, e[2] + 2000, e[3], e[4]), crs = terra::crs(pre$mnt)))
  loin$nom <- "loin"
  tout <- sf::st_as_sf(terra::as.polygons(e, crs = terra::crs(pre$mnt)))
  tout$nom <- "tout"
  zones <- rbind(loin[, "nom"], tout[, "nom"])

  agg <- agreger_zones(sk$accessibilite, zones, id = "nom")
  expect_equal(agg$surface_totale_ha[agg$nom == "loin"], 0)
  expect_gt(agg$surface_totale_ha[agg$nom == "tout"], 0)
})

test_that("print.foretaccess_agregation resume l'agregation", {
  pre <- toy_preprocess()
  sk <- skidder(pre)
  agg <- agreger_zones(sk$accessibilite, zones_moities(pre$mnt), id = "nom")
  expect_message(print(agg), regexp = "Agregation zonale")
})
