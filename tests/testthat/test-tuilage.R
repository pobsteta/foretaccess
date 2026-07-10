# Decoupage en tuiles avec halo (spec 007 §4.1, §4.5).

gabarit_test <- function(nr = 10, nc = 10, res = 10) {
  terra::rast(
    nrows = nr, ncols = nc, xmin = 0, xmax = nc * res,
    ymin = 0, ymax = nr * res, crs = "EPSG:2154"
  )
}

test_that("les fenetres d'ecriture pavent l'emprise, sans trou ni recouvrement", {
  tu <- decouper_emprise(gabarit_test(10, 10), tuile_m = 30)
  t <- tu$tuiles

  # 10 cellules pour des tuiles de 3 : 4 x 4 tuiles, la derniere tronquee.
  expect_equal(nrow(t), 16)
  expect_equal(sum((t$l2 - t$l1 + 1) * (t$c2 - t$c1 + 1)), 100)

  # Aucune cellule n'appartient a deux tuiles.
  cellules <- unlist(lapply(seq_len(nrow(t)), function(i) {
    l <- t$l1[i]:t$l2[i]
    c <- t$c1[i]:t$c2[i]
    as.vector(outer(l, c, function(a, b) (a - 1) * 10 + b))
  }))
  expect_equal(sort(cellules), 1:100)
})

test_that("le halo elargit la fenetre de calcul et se rabote sur l'emprise", {
  tu <- decouper_emprise(gabarit_test(10, 10), tuile_m = 50, halo_m = 20)
  t <- tu$tuiles

  expect_equal(tu$tuile_cel, 5)
  expect_equal(tu$halo_cel, 2)

  # Tuile en haut a gauche : le halo est rabote en haut et a gauche.
  hg <- t[t$l1 == 1 & t$c1 == 1, ]
  expect_equal(c(hg$hl1, hg$hc1), c(1, 1))
  expect_equal(c(hg$hl2, hg$hc2), c(7, 7))

  # Tuile en bas a droite : rabote en bas et a droite.
  bd <- t[t$l1 == 6 & t$c1 == 6, ]
  expect_equal(c(bd$hl1, bd$hc1), c(4, 4))
  expect_equal(c(bd$hl2, bd$hc2), c(10, 10))
})

test_that("les cotes ouverts sont ceux qui ne butent pas sur l'emprise", {
  tu <- decouper_emprise(gabarit_test(10, 10), tuile_m = 50, halo_m = 20)
  t <- tu$tuiles

  hg <- t[t$l1 == 1 & t$c1 == 1, ]
  expect_equal(.cotes_ouverts(hg), c("bas", "droite"))

  bd <- t[t$l1 == 6 & t$c1 == 6, ]
  expect_equal(.cotes_ouverts(bd), c("haut", "gauche"))
})

test_that("une tuile plus grande que l'emprise donne une tuile unique, fermee", {
  tu <- decouper_emprise(gabarit_test(10, 10), tuile_m = 1000, halo_m = 500)
  expect_equal(nrow(tu$tuiles), 1)
  expect_equal(.cotes_ouverts(tu$tuiles), character(0))
  expect_equal(.surcout_halo(tu), 1)
})

test_that("sans halo, la fenetre de calcul est la fenetre d'ecriture", {
  tu <- decouper_emprise(gabarit_test(10, 10), tuile_m = 50)
  t <- tu$tuiles
  expect_equal(t$hl1, t$l1)
  expect_equal(t$hc2, t$c2)
  expect_equal(.surcout_halo(tu), 1)
})

test_that("fenetre_tuile rend l'emprise geographique attendue", {
  g <- gabarit_test(10, 10, res = 10)
  tu <- decouper_emprise(g, tuile_m = 50, halo_m = 20)
  hg <- tu$tuiles[tu$tuiles$l1 == 1 & tu$tuiles$c1 == 1, ]

  e <- as.vector(fenetre_tuile(tu, hg$id, "tuile"))
  expect_equal(unname(e), c(0, 50, 50, 100))

  # Le halo descend de 2 cellules (20 m) vers le bas et vers la droite.
  h <- as.vector(fenetre_tuile(tu, hg$id, "halo"))
  expect_equal(unname(h), c(0, 70, 30, 100))

  # Et elle recadre bien le raster.
  expect_equal(terra::ncol(terra::crop(g, fenetre_tuile(tu, hg$id))), 7)
})

test_that("le surcout du halo se mesure", {
  # Tuiles de 2 cellules, halo de 2 : la fenetre interieure fait 6x6 pour 2x2 ecrits.
  tu <- decouper_emprise(gabarit_test(10, 10), tuile_m = 20, halo_m = 20)
  expect_gt(.surcout_halo(tu), 5)
  expect_message(print(tu), regexp = "surcout surfacique")
})

test_that("les entrees invalides levent une erreur ciblee", {
  g <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 8, ymin = 0, ymax = 4)
  terra::crs(g) <- "EPSG:2154"
  expect_error(decouper_emprise(g, tuile_m = 10), regexp = "cellules carrees")

  tu <- decouper_emprise(gabarit_test(4, 4), tuile_m = 20)
  expect_error(fenetre_tuile(tu, 99), regexp = "Tuile 99 inconnue")
})
