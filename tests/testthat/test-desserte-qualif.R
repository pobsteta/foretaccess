# qualifier_desserte() (spec 021, etape 1). ALSroads/lidR optionnels, absents en
# CI : les tests exercent le repli NDP 0 (desserte declaree renvoyee telle quelle,
# conforme au contrat preprocess). Le chemin NDP 1 (relocalisation + largeur) est
# valide hors CI (Phase B, cf. acquire_desserte_lidar).

desserte_declaree_test <- function() {
  sf::st_sf(
    classe = c("route", "piste"),
    largeur = c(NA_real_, NA_real_), # BD TOPO : largeur souvent vide
    geometry = sf::st_sfc(
      sf::st_linestring(rbind(c(0, 0), c(100, 0))),
      sf::st_linestring(rbind(c(0, 50), c(100, 80))),
      crs = 2154
    )
  )
}

mnt_qualif_test <- function() {
  r <- terra::rast(
    nrows = 20, ncols = 20, xmin = 0, xmax = 100, ymin = 0, ymax = 100,
    crs = "EPSG:2154"
  )
  terra::values(r) <- 100
  names(r) <- "altitude"
  r
}

test_that("sans lidR/ALSroads : NDP 0, desserte declaree renvoyee telle quelle", {
  testthat::local_mocked_bindings(
    .alsroads_dispo = function() FALSE,
    .env = asNamespace("foretaccess")
  )
  des <- desserte_declaree_test()
  expect_message(
    out <- qualifier_desserte(des, las_source = "peu_importe", mnt = mnt_qualif_test()),
    "inoperante|NDP 0"
  )
  expect_s3_class(out, "sf")
  # Contrat preprocess preserve : classe, largeur, geometrie inchangee.
  expect_true(all(c("classe", "largeur") %in% names(out)))
  expect_equal(nrow(out), nrow(des))
  expect_equal(sf::st_geometry(out), sf::st_geometry(des))
  # Sans LiDAR, la largeur n'est pas renseignee (reste NA).
  expect_true(all(is.na(out$largeur)))
  expect_identical(attr(out, "ndp"), 0L)
  expect_true(attr(out, "qualifiee"))
})

test_that("une desserte vide ou non lineaire est refusee (delegue au socle LiDAR)", {
  expect_error(
    qualifier_desserte(desserte_declaree_test()[0, ], "x", mnt_qualif_test()),
    "vide"
  )
  pts <- sf::st_sf(
    classe = "route", largeur = NA_real_,
    geometry = sf::st_sfc(sf::st_point(c(1, 1)), crs = 2154)
  )
  expect_error(qualifier_desserte(pts, "x", mnt_qualif_test()), "couche de lignes")
})

test_that("la sortie qualifiee est consommable par preprocess (classe presente)", {
  testthat::local_mocked_bindings(
    .alsroads_dispo = function() FALSE,
    .env = asNamespace("foretaccess")
  )
  out <- suppressMessages(
    qualifier_desserte(desserte_declaree_test(), "x", mnt_qualif_test())
  )
  # preprocess() apparie desserte$classe a .classes_desserte() : la colonne doit
  # exister et etre du bon type (caractere).
  expect_type(as.character(out$classe), "character")
  expect_true("largeur" %in% names(out))
})
