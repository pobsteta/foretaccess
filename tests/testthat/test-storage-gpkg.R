make_layer <- function() {
  sf::st_sf(
    id = 1:3,
    nom = c("a", "b", "c"),
    geometry = sf::st_sfc(
      sf::st_point(c(0, 0)),
      sf::st_point(c(1, 1)),
      sf::st_point(c(2, 2)),
      crs = 2154
    )
  )
}

test_that("round-trip d'une couche en GeoPackage", {
  path <- withr::local_tempfile(fileext = ".gpkg")
  sb <- storage_gpkg(path)
  layer <- make_layer()

  sb_write_layer(sb, "essai", layer)
  expect_true("essai" %in% sb_list_layers(sb))

  back <- sb_read_layer(sb, "essai")
  expect_equal(nrow(back), 3)
  expect_setequal(back$nom, c("a", "b", "c"))
  expect_equal(sf::st_crs(back)$epsg, 2154L)
})

test_that("l'écriture est idempotente (pas de duplication)", {
  path <- withr::local_tempfile(fileext = ".gpkg")
  sb <- storage_gpkg(path)
  layer <- make_layer()

  sb_write_layer(sb, "essai", layer)
  sb_write_layer(sb, "essai", layer) # ré-écriture

  back <- sb_read_layer(sb, "essai")
  expect_equal(nrow(back), 3)
  expect_length(sb_list_layers(sb), 1)
})

test_that("lister les couches d'un fichier absent renvoie un vecteur vide", {
  sb <- storage_gpkg(withr::local_tempfile(fileext = ".gpkg"))
  expect_length(sb_list_layers(sb), 0)
})
