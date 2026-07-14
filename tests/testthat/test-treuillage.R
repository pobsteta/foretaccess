# Balayage radial du treuillage (spec 002 §4.3, CA-2.7 et CA-2.9).
# Reproduit skid_debusq_RF() de sylvaccess_cython3.pyx.

# MNT plat : toutes les cellules sont a la meme altitude.
mnt_plat <- function(n = 51, res = 5, alt = 100) {
  r <- terra::rast(
    nrows = n, ncols = n, xmin = 0, xmax = n * res, ymin = 0, ymax = n * res,
    crs = "EPSG:2154"
  )
  terra::values(r) <- alt
  r
}

# Desserte reduite a une seule cellule, au centre.
desserte_ponctuelle <- function(gabarit) {
  d <- terra::rast(gabarit)
  cel <- terra::cellFromRowCol(d, 26, 26)
  v <- rep(NA_real_, terra::ncell(d))
  v[cel] <- cel
  terra::values(d) <- v
  d
}

test_that("sur un terrain plat, la portee vaut Dmax(0) = 80,23 m", {
  mnt <- mnt_plat()
  des <- desserte_ponctuelle(mnt)
  tr <- treuiller(mnt, des, zone_pleine(mnt, des))

  d <- terra::values(tr$distance)
  # A plat, la distance 3D est la distance horizontale. La cellule a 80 m est
  # atteinte (80 <= 80,2349), celle a 85 m ne l'est pas.
  expect_equal(tr$distance[26, 26 - 16][[1]], 80) # 16 cellules x 5 m
  expect_true(is.na(tr$distance[26, 26 - 17][[1]])) # 85 m

  expect_equal(max(d, na.rm = TRUE), 80.234856, tolerance = 0.5)
  expect_lte(max(d, na.rm = TRUE), distance_treuillage_max(0))
})

test_that("la distance de treuillage est une distance 3D", {
  # Plan a 60 % : une cellule a 40 m a l'est est 24 m plus haut.
  mnt <- mnt_plan(0.60, n = 51)
  des <- desserte_ponctuelle(mnt)
  tr <- treuiller(mnt, des, zone_pleine(mnt, des))

  h <- 40
  attendu <- sqrt(h^2 + (0.60 * h)^2) # 46,65 m, et non 40
  expect_equal(tr$distance[26, 26 + 8][[1]], attendu, tolerance = 1e-6)
  expect_gt(attendu, h)
})

test_that("la portee amont est plus courte que la portee aval (CA-2.9)", {
  mnt <- mnt_plan(0.60, n = 51)
  des <- desserte_ponctuelle(mnt)
  tr <- treuiller(mnt, des, zone_pleine(mnt, des))

  # Amont (est, le terrain monte) : pente du rayon = +0,60 -> Dmax = 52,84 m.
  dmax_amont <- distance_treuillage_max(0.60)
  expect_equal(dmax_amont, 52.842, tolerance = 1e-3)

  # Aval (ouest) : pente = -0,60 <= -0,20 -> Dmax = 100 m (plafond aval).
  dmax_aval <- distance_treuillage_max(-0.60)
  expect_equal(dmax_aval, 100)

  # La derniere cellule atteinte a l'est est a 45 m horizontaux (52,48 m en 3D) ;
  # a 50 m horizontaux la distance 3D vaut 58,31 m > 52,84 m.
  facteur <- sqrt(1 + 0.60^2)
  expect_equal(tr$distance[26, 26 + 9][[1]], 45 * facteur, tolerance = 1e-6)
  expect_true(is.na(tr$distance[26, 26 + 10][[1]]))

  # A l'ouest, on va bien plus loin : 85 m horizontaux, 99,13 m en 3D.
  expect_equal(tr$distance[26, 26 - 17][[1]], 85 * facteur, tolerance = 1e-6)
  expect_true(is.na(tr$distance[26, 26 - 18][[1]]))
})

test_that("un relief intercale interrompt le rayon (contrainte de degagement, CA-2.7)", {
  mnt <- mnt_plat()
  des <- desserte_ponctuelle(mnt)

  # Une crete de 50 m de haut a 20 m a l'ouest : la corde du treuil, tendue a
  # 10 m au-dessus de la desserte, passerait sous le terrain.
  sans_crete <- treuiller(mnt, des, zone_pleine(mnt, des))
  expect_false(is.na(sans_crete$distance[26, 26 - 8][[1]])) # 40 m : atteint

  mnt[26, 26 - 4] <- 150 # crete a 20 m a l'ouest
  avec_crete <- treuiller(mnt, des, zone_pleine(mnt, des))

  # La crete elle-meme reste atteignable (rien ne la precede), mais tout ce qui
  # est derriere, sur ce rayon, ne l'est plus.
  expect_true(is.na(avec_crete$distance[26, 26 - 8][[1]]))
})

test_that("la hauteur de degagement maximale borne aussi le treuillage", {
  # Une fosse profonde : la corde passerait a plus de 30 m au-dessus du sol.
  mnt <- mnt_plat()
  des <- desserte_ponctuelle(mnt)
  mnt[26, 26 - 4] <- 50 # fosse de 50 m a 20 m a l'ouest

  tr <- treuiller(mnt, des, zone_pleine(mnt, des))
  # La fosse est a 60 m sous la corde (10 m d'attache + 50 m) : au-dela de 30 m.
  expect_true(is.na(tr$distance[26, 26 - 4][[1]]))
  expect_true(is.na(tr$distance[26, 26 - 8][[1]]))
})

test_that("la zone non treuillable interrompt le rayon", {
  mnt <- mnt_plat()
  des <- desserte_ponctuelle(mnt)
  zone <- zone_pleine(mnt, des)
  zone[26, 26 - 4] <- 0 # trou dans la zone a 20 m a l'ouest

  tr <- treuiller(mnt, des, zone)
  expect_true(is.na(tr$distance[26, 26 - 4][[1]]))
  expect_true(is.na(tr$distance[26, 26 - 8][[1]]))
})

test_that("l'allocation designe la cellule de desserte d'origine", {
  mnt <- mnt_plat()
  des <- desserte_ponctuelle(mnt)
  tr <- treuiller(mnt, des, zone_pleine(mnt, des))

  cel <- terra::cellFromRowCol(mnt, 26, 26)
  expect_equal(tr$allocation[26, 26][[1]], cel)
  expect_equal(tr$allocation[26, 20][[1]], cel)
  expect_equal(tr$distance[26, 26][[1]], 0)
})

test_that("une desserte vide leve une erreur ciblee", {
  mnt <- mnt_plat()
  vide <- terra::rast(mnt)
  terra::values(vide) <- NA_real_
  expect_error(treuiller(mnt, vide, zone_pleine(mnt)), regexp = "aucune cellule")
})

# `depart_cout` : le critere d'amelioration porte sur le total (skid_debusq_contour).

test_that("depart_cout fait arbitrer sur le total, pas sur la longueur de cable", {
  mnt <- mnt_plat()
  des <- terra::rast(mnt)
  a <- terra::cellFromRowCol(des, 26, 20) # a 30 m de la cible
  b <- terra::cellFromRowCol(des, 26, 30) # a 20 m de la cible : plus proche
  v <- rep(NA_real_, terra::ncell(des))
  v[c(a, b)] <- 1
  terra::values(des) <- v
  cible <- terra::cellFromRowCol(des, 26, 26)

  # Sans cout de depart : la source la plus proche gagne.
  tr <- treuiller(mnt, des, zone_pleine(mnt, des))
  expect_equal(tr$allocation[cible][[1]], b)
  expect_equal(tr$distance[cible][[1]], 20)

  # B porte 100 m de trainage : son total (120) perd contre celui de A (30),
  # alors meme que son cable est plus court.
  cout <- rep(0, terra::ncell(mnt))
  cout[b] <- 100
  tr2 <- treuiller(mnt, des, zone_pleine(mnt, des), depart_cout = cout)
  expect_equal(tr2$allocation[cible][[1]], a)
  expect_equal(tr2$distance[cible][[1]], 30)
})

test_that("depart_cout nul redonne exactement le balayage depuis la desserte", {
  mnt <- mnt_plat()
  des <- desserte_ponctuelle(mnt)
  ref <- treuiller(mnt, des, zone_pleine(mnt, des))
  bis <- treuiller(mnt, des, zone_pleine(mnt, des),
    depart_cout = rep(0, terra::ncell(mnt))
  )
  expect_equal(terra::values(bis$distance), terra::values(ref$distance))
  expect_equal(terra::values(bis$allocation), terra::values(ref$allocation))
})
