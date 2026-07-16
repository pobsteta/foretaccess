# Lot 14 -- surface de cout de construction de desserte (spec 014).

# Fixture legere : un objet `foretaccess_preprocessing` reduit aux champs lus par
# `surface_cout_construction` (MNT, pente, masque d'obstacles complets). Permet de
# piloter la pente cellule par cellule, ce que le MNT jouet (pente ~constante) ne
# permet pas.
fake_pre <- function(slope_pct = 10, obstacle = NULL, nrow = 5, ncol = 5) {
  mnt <- terra::rast(
    nrows = nrow, ncols = ncol,
    xmin = 0, xmax = ncol * 5, ymin = 0, ymax = nrow * 5,
    crs = "EPSG:2154"
  )
  terra::values(mnt) <- 100
  names(mnt) <- "mnt"

  sp <- terra::rast(mnt)
  terra::values(sp) <- slope_pct  # recycle scalaire ou vecteur cellule a cellule
  names(sp) <- "slope_pct"

  obst <- terra::rast(mnt)
  terra::values(obst) <- if (is.null(obstacle)) 0 else obstacle
  names(obst) <- "obstacles_complets_mask"

  structure(
    list(mnt = mnt, slope_pct = sp, obstacles_complets_mask = obst),
    class = "foretaccess_preprocessing"
  )
}

# Matrice ligne x colonne (disposition raster) des valeurs d'une couche.
grille_mat <- function(r) terra::as.matrix(r, wide = TRUE)

test_that("CA-14.1 : cout de base seul, sans couche optionnelle", {
  pre <- fake_pre(slope_pct = 5)  # classe [0,15) -> surcout 0
  res <- surface_cout_construction(pre)

  expect_s3_class(res, "foretaccess_cout_construction")
  expect_named(res, c("cout", "franchissable", "config"))
  # base 20 + surcout pente 0 = 20 partout.
  expect_true(all(terra::values(res$cout) == 20, na.rm = TRUE))
  # Sans obstacle ni interdit, tout est franchissable.
  expect_true(all(terra::values(res$franchissable) > 0))
  expect_equal(sum(terra::values(res$cout) == 20), terra::ncell(pre$mnt))
})

test_that("CA-14.1 : la classe de pente ajoute son surcout", {
  pre <- fake_pre(slope_pct = 20)  # classe [15,35) -> surcout 25
  res <- surface_cout_construction(pre)
  expect_true(all(terra::values(res$cout) == 45, na.rm = TRUE))  # 20 + 25
})

test_that("CA-14.2 : pont (plan d'eau) et buse (cours d'eau) surcoutent", {
  pre <- fake_pre(slope_pct = 5)

  # Plan d'eau raster : une colonne d'eau -> +cout_pont_m (400).
  eau <- terra::rast(pre$mnt)
  terra::values(eau) <- 0
  eau[, 3] <- 1
  m_pont <- grille_mat(surface_cout_construction(pre, plan_eau = eau)$cout)
  expect_true(all(m_pont[, 3] == 420))  # 20 + 400
  expect_equal(m_pont[1, 1], 20)

  # Cours d'eau sf : une ligne traversant une rangee entiere -> +buse (<= 120).
  ligne <- sf::st_sf(
    id = 1L,
    geometry = sf::st_sfc(
      sf::st_linestring(rbind(c(0, 12.5), c(25, 12.5))), crs = 2154
    )
  )
  m_buse <- grille_mat(surface_cout_construction(pre, cours_eau = ligne)$cout)
  expect_true(max(m_buse, na.rm = TRUE) > 20)
  expect_true(max(m_buse, na.rm = TRUE) <= 20 + 120)
})

test_that("CA-14.3 : zone interdite -> non franchissable, cout NA", {
  pre <- fake_pre(slope_pct = 5)
  interdit <- terra::rast(pre$mnt)
  terra::values(interdit) <- 0
  interdit[1, 1] <- 1

  res <- surface_cout_construction(pre, interdit = interdit)
  fr <- grille_mat(res$franchissable)
  co <- grille_mat(res$cout)
  expect_false(fr[1, 1] > 0)
  expect_true(is.na(co[1, 1]))
  # Les autres restent franchissables et chiffrees.
  expect_true(all(fr[-1] > 0))
  expect_true(all(is.finite(co[-1])))
})

test_that("CA-14.3 : obstacle complet -> non franchissable", {
  obst <- rep(0, 25)
  obst[13] <- 1  # cellule centrale
  pre <- fake_pre(slope_pct = 5, obstacle = obst)
  res <- surface_cout_construction(pre)
  expect_false(terra::values(res$franchissable)[13] > 0)
  expect_true(is.na(terra::values(res$cout)[13]))
})

test_that("CA-14.3 : pente non constructible (Inf) -> non franchissable", {
  pre <- fake_pre(slope_pct = 70)  # classe [60, Inf) -> surcout Inf
  res <- surface_cout_construction(pre)
  expect_true(all(!terra::values(res$franchissable) > 0))
  expect_true(all(is.na(terra::values(res$cout))))
})

test_that("CA-14.4 : le cout croit avec la classe de pente (monotone)", {
  # Une cellule par classe : 5, 20, 45, 5, 20 % (Inf exclue car non chiffrable).
  pre <- fake_pre(slope_pct = c(5, 20, 45, 5, 20), nrow = 1, ncol = 5)
  v <- grille_mat(surface_cout_construction(pre)$cout)[1, ]
  expect_equal(v[1], 20)   # [0,15)  -> +0
  expect_equal(v[2], 45)   # [15,35) -> +25
  expect_equal(v[3], 110)  # [35,60) -> +90
  expect_true(v[1] <= v[2] && v[2] <= v[3])
})

test_that("CA-14.5 : les sorties sont alignees sur la grille du MNT", {
  pre <- fake_pre(slope_pct = 5)
  res <- surface_cout_construction(pre)
  expect_true(terra::compareGeom(res$cout, pre$mnt, stopOnError = FALSE))
  expect_true(terra::compareGeom(res$franchissable, pre$mnt, stopOnError = FALSE))
  expect_true(terra::ext(res$cout) == terra::ext(pre$mnt))
  expect_equal(terra::res(res$cout), terra::res(pre$mnt))
})

test_that("CA-14.6 : la configuration est validee", {
  pre <- fake_pre(slope_pct = 5)
  # Bareme de pente non couvrant (dernier max fini) -> erreur.
  cfg <- foretaccess_config()
  cfg$desserte$cout$bareme_pente <- data.frame(
    min = c(0, 15), max = c(15, 60), surcout = c(0, 25)
  )
  expect_error(surface_cout_construction(pre, cfg), "contigues|coherent")

  # Cout de base negatif -> erreur.
  cfg2 <- foretaccess_config()
  cfg2$desserte$cout$cout_base_m <- -5
  expect_error(surface_cout_construction(pre, cfg2))
})

test_that("surcout de sol : table classe -> surcout", {
  pre <- fake_pre(slope_pct = 5)
  sol <- terra::rast(pre$mnt)
  terra::values(sol) <- 1
  sol[, 4] <- 2  # classe 2 sur une colonne

  cfg <- foretaccess_config(desserte = list(cout = list(
    bareme_sol = list(`1` = 0, `2` = 50)
  )))
  m <- grille_mat(surface_cout_construction(pre, sol = sol, config = cfg)$cout)
  expect_equal(m[1, 1], 20)          # classe 1 -> +0
  expect_true(all(m[, 4] == 70))     # classe 2 -> +50
})

test_that("la methode print resume sans erreur", {
  pre <- fake_pre(slope_pct = 20)
  res <- surface_cout_construction(pre)
  expect_no_error(print(res))
  expect_invisible(print(res))
})
