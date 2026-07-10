# Tableau recapitulatif (spec 002 §4.6, CA-2.11).

test_that("le recapitulatif conserve la surface totale (CA-2.11)", {
  sk <- toy_skidder()
  g <- sk$grid

  surface_totale <- g$nrow * g$ncol * prod(g$res) / 10000
  expect_equal(sum(sk$recap$surface_ha), surface_totale)
  expect_equal(sum(sk$recap$cellules), g$nrow * g$ncol)
})

test_that("les bordures indeterminees forment une ligne explicite (CA-2.11)", {
  sk <- toy_skidder()
  r <- sk$recap

  expect_true("indetermine" %in% r$classe)
  # 50x50 moins l'interieur 48x48 : la couronne de bordure du calcul de pente.
  expect_equal(r$cellules[r$classe == "indetermine"], 50 * 50 - 48 * 48)
})

test_that("les volumes sont agreges quand le raster est fourni", {
  pre <- preprocess(
    mnt = toy_mnt(), desserte = toy_desserte(), foret = toy_foret(),
    volume = toy_volume(valeur = 10)
  )
  sk <- skidder(pre)

  expect_true("volume_m3" %in% names(sk$recap))
  # Volume constant a 10 : le total est 10 x nombre de cellules.
  expect_equal(sum(sk$recap$volume_m3), 10 * 50 * 50)
  # Et chaque classe porte 10 x son nombre de cellules.
  expect_equal(sk$recap$volume_m3, 10 * sk$recap$cellules)
})

test_that("sans volume, la colonne est absente", {
  expect_false("volume_m3" %in% names(toy_skidder()$recap))
})

test_that("recapituler exige un raster categoriel", {
  r <- terra::rast(toy_mnt())
  terra::values(r) <- 1
  expect_error(recapituler(r), regexp = "categoriel")
})

test_that("recapituler compte les NA a part, jamais dans une classe metier", {
  r <- terra::rast(toy_mnt())
  v <- rep(1, terra::ncell(r))
  v[1:100] <- NA
  terra::values(r) <- v
  levels(r) <- data.frame(value = 1, classe = "a")

  tab <- recapituler(r)
  expect_equal(tab$cellules[tab$classe == "a"], 50 * 50 - 100)
  expect_equal(tab$cellules[tab$classe == "indetermine"], 100)
  expect_equal(sum(tab$cellules), 50 * 50)
})
