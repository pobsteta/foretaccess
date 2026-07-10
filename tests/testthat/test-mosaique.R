# Traitement par tuiles (spec 007 §4.4, §4.5). Le mono-bloc du Lot 2 est l'oracle :
# c'est le seul lot dont l'oracle est le projet lui-meme.

cfg_tuiles <- function(...) {
  foretaccess_config(general = utils::modifyList(
    list(tuile_m = 100, halo_initial_m = 200, halo_max_m = 2000), list(...)
  ))
}

test_that("le resultat tuile est identique au mono-bloc (CA-7.1)", {
  pre <- toy_preprocess()
  ref <- skidder(pre)
  mo <- traiter_par_tuiles(pre, cfg_tuiles(), quiet = TRUE)

  # Le jouet a 196 cellules de bordure a pente `NA` : le mono-bloc les compte deja
  # `indetermine`. Le tuilage n'en ajoute aucune.
  expect_equal(mo$indetermine_ha, ref$recap$surface_ha[ref$recap$classe == "indetermine"])
  expect_true(all(terra::values(mo$certifie) == 1))

  for (nm in .couches_skidder()) {
    expect_equal(
      as.numeric(terra::values(mo[[nm]])),
      as.numeric(terra::values(ref[[nm]])),
      info = nm
    )
  }
  # Y compris la table de categories.
  expect_equal(terra::levels(mo$accessibilite)[[1]], terra::levels(ref$accessibilite)[[1]])
})

test_that("les surfaces par classe sont conservees (CA-7.4)", {
  pre <- toy_preprocess()
  ref <- skidder(pre)
  mo <- traiter_par_tuiles(pre, cfg_tuiles(), quiet = TRUE)

  r <- merge(ref$recap[, c("classe", "cellules")], mo$recap[, c("classe", "cellules")],
    by = "classe", suffixes = c("_ref", "_mo")
  )
  expect_equal(r$cellules_ref, r$cellules_mo)
  expect_equal(sum(mo$recap$cellules), terra::ncell(pre$mnt))
})

test_that("l'allocation vit dans la grille globale, pas dans celle de la tuile (CA-7.7)", {
  pre <- toy_preprocess()
  mo <- traiter_par_tuiles(pre, cfg_tuiles(), quiet = TRUE)

  a <- as.numeric(terra::values(mo$allocation))
  a <- a[!is.na(a)]
  desserte_cel <- which(!is.na(terra::values(pre$desserte)))

  # Toute allocation designe une cellule de desserte de la grille globale.
  expect_true(all(a %in% desserte_cel))
  # Et plusieurs tuiles pointent vers la meme desserte, sans collision d'identifiants.
  expect_gt(length(unique(a)), 1)
})

test_that("une tuille unique couvrant l'emprise n'a aucun cote ouvert", {
  pre <- toy_preprocess()
  mo <- traiter_par_tuiles(pre, cfg_tuiles(tuile_m = 1000), quiet = TRUE)

  expect_equal(nrow(mo$tuiles), 1)
  expect_equal(sum(mo$tuiles$non_certifie), 0)
  expect_equal(as.numeric(terra::values(mo$accessibilite)),
    as.numeric(terra::values(skidder(pre)$accessibilite)))
})

test_that("le halo double jusqu'a certifier, sans atteindre le plafond (CA-7.5)", {
  pre <- toy_preprocess()
  # Halo initial trop court pour couvrir la portee du treuil (100 m + 1,5 x 5 m).
  mo <- traiter_par_tuiles(pre, cfg_tuiles(halo_initial_m = 25), quiet = TRUE)

  expect_true(all(mo$tuiles$non_certifie == 0))
  expect_gt(max(mo$tuiles$halo_m), 25)
  expect_lt(max(mo$tuiles$halo_m), 2000)
})

test_that("au plafond, les cellules restantes sont indetermine et non non_accessible (CA-7.6)", {
  pre <- toy_preprocess()
  # Halo nul et plafonne : aucune tuile interieure ne peut se certifier.
  cfg <- cfg_tuiles(tuile_m = 50, halo_initial_m = 0, halo_max_m = 0)

  expect_warning(
    mo <- traiter_par_tuiles(pre, cfg, quiet = TRUE),
    regexp = "non certifiee"
  )
  expect_gt(mo$indetermine_ha, 0)
  expect_gt(sum(mo$tuiles$non_certifie), 0)

  # Le doute se declare : il ne grossit pas la classe `non_accessible`.
  ref <- skidder(pre)
  na_ref <- ref$recap$cellules[ref$recap$classe == "non_accessible"]
  na_mo <- mo$recap$cellules[mo$recap$classe == "non_accessible"]
  expect_lte(na_mo, na_ref)
})

# Le jouet fait 250 m : des 110 m de halo -- le minimum pour couvrir la portee du
# treuil -- les fenetres couvrent presque toute l'emprise et tout se certifie. Pour que
# le certificat ait quelque chose a refuser, il faut une emprise plus large qu'un halo,
# et une desserte assez rare pour que le trainage soit long.
grand_jouet <- function(n = 120, res = 5) {
  mnt <- terra::rast(
    nrows = n, ncols = n, xmin = 0, xmax = n * res,
    ymin = 0, ymax = n * res, crs = "EPSG:2154"
  )
  terra::values(mnt) <- rep(seq_len(n) * res * 0.2, each = n)

  cote <- n * res
  foret <- sf::st_sf(id = 1, geometry = sf::st_sfc(sf::st_polygon(list(rbind(
    c(0, 0), c(cote, 0), c(cote, cote), c(0, cote), c(0, 0)
  ))), crs = 2154))
  desserte <- sf::st_sf(
    classe = "route",
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(50, 0), c(50, cote))), crs = 2154)
  )
  preprocess(mnt = mnt, desserte = desserte, foret = foret)
}

test_that("aucun faux positif a l'echelle du moteur : ce qui est certifie est exact", {
  pre <- grand_jouet()
  ref <- skidder(pre)
  cfg <- cfg_tuiles(tuile_m = 200, halo_initial_m = 110, halo_max_m = 110)

  suppressWarnings(mo <- traiter_par_tuiles(pre, cfg, quiet = TRUE))

  certifie <- terra::values(mo$certifie) == 1
  expect_gt(sum(!certifie), 0)
  expect_gt(sum(certifie), 0)

  for (nm in .couches_skidder()) {
    expect_equal(
      as.numeric(terra::values(mo[[nm]]))[certifie],
      as.numeric(terra::values(ref[[nm]]))[certifie],
      info = nm
    )
  }
})

test_that("une tuile sans foret ni desserte est traitee sans appeler le moteur (CA-7.9)", {
  # La foret du jouet occupe [25, 225]^2 ; la tuile [0, 25]^2 en est exempte, et la
  # piste DFCI diagonale n'y passe qu'a l'origine exacte. On l'exclut en decalant.
  foret <- toy_foret()
  desserte <- sf::st_sf(
    classe = "route",
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(200, 100), c(200, 200))), crs = 2154)
  )
  pre <- preprocess(mnt = toy_mnt(), desserte = desserte, foret = foret)

  appels <- 0
  moteur_compte <- function(pre, config, bord) {
    appels <<- appels + 1
    skidder(pre, config, bord = bord)
  }
  cfg <- cfg_tuiles(tuile_m = 50, halo_initial_m = 0, halo_max_m = 0)
  suppressWarnings(mo <- traiter_par_tuiles(pre, cfg, moteur = moteur_compte, quiet = TRUE))

  # 25 tuiles, mais seules celles qui voient une desserte appellent le moteur.
  expect_equal(nrow(mo$tuiles), 25)
  expect_lt(appels, 25)
  expect_gt(appels, 0)
})

test_that("une tuile sans desserte laisse la foret indeterminee, jamais inaccessible", {
  desserte <- sf::st_sf(
    classe = "route",
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(30, 30), c(40, 40))), crs = 2154)
  )
  pre <- preprocess(mnt = toy_mnt(), desserte = desserte, foret = toy_foret())
  cfg <- cfg_tuiles(tuile_m = 50, halo_initial_m = 0, halo_max_m = 0)

  suppressWarnings(mo <- traiter_par_tuiles(pre, cfg, quiet = TRUE))

  # Coin nord-est : forestier, hors de toute desserte connue de sa tuile.
  loin <- terra::cellFromXY(pre$mnt, cbind(200, 200))
  expect_true(is.na(terra::values(mo$accessibilite)[loin]))
})

test_that("les rasters sont ecrits en COG relisibles, categories preservees (CA-7.8)", {
  withr::with_tempdir({
    pre <- toy_preprocess()
    mo <- traiter_par_tuiles(pre, cfg_tuiles(), write_dir = "sortie", quiet = TRUE)

    expect_named(mo$fichiers, .couches_skidder(), ignore.order = TRUE)
    expect_true(all(file.exists(unlist(mo$fichiers))))

    relu <- terra::rast(file.path("sortie", "accessibilite.tif"))
    expect_equal(terra::levels(relu)[[1]][[2]], terra::levels(mo$accessibilite)[[1]][[2]])
  })
})

test_that("le resultat ne depend pas du nombre de workers (CA-7.2)", {
  # Les demons chargent le package : ils ont besoin qu'il soit *installe*, pas
  # seulement charge par `pkgload`. En developpement local, ce test se saute.
  skip_if_not_installed("mirai")
  skip_if(pkgload::is_dev_package("foretaccess"), "package charge par pkgload")

  pre <- toy_preprocess()
  seq1 <- traiter_par_tuiles(pre, cfg_tuiles(), quiet = TRUE)
  par4 <- traiter_par_tuiles(pre, cfg_tuiles(workers = 4L), quiet = TRUE)

  for (nm in .couches_skidder()) {
    expect_equal(
      as.numeric(terra::values(par4[[nm]])),
      as.numeric(terra::values(seq1[[nm]])),
      info = nm
    )
  }
  expect_equal(par4$tuiles, seq1$tuiles)
})

test_that("la distance sur piste est precalculee globalement, donc exacte", {
  pre <- toy_preprocess()
  ref <- skidder(pre)

  enrichi <- .precalculer_piste(pre, foretaccess_config())
  expect_s4_class(enrichi$distance_piste, "SpatRaster")

  # Le moteur la reprend telle quelle : meme resultat qu'en la recalculant lui-meme.
  reutilise <- skidder(enrichi)
  expect_equal(
    terra::values(reutilise$distance_trainage_piste),
    terra::values(ref$distance_trainage_piste)
  )

  # Et le precalcul est idempotent.
  expect_identical(.precalculer_piste(enrichi, foretaccess_config()), enrichi)
})

test_that("l'emballage d'une tuile traverse la frontiere de processus", {
  # Les `SpatRaster` portent des pointeurs C++ : seul l'aller-retour wrap/unwrap les
  # rend serialisables. C'est ce qui permet a une tuile d'atteindre un demon.
  pre <- toy_preprocess()
  t <- .fenetre_calcul(decouper_emprise(pre$mnt, 100, 0)$tuiles[1, ], 50, 5, 50, 50)
  pre_t <- .preparer_tuile(pre, t)

  emballe <- .emballer_pre(pre_t)
  expect_s4_class(emballe$mnt, "PackedSpatRaster")
  expect_length(unserialize(serialize(emballe, NULL)), length(emballe))

  rendu <- .deballer_pre(emballe)
  expect_s4_class(rendu$mnt, "SpatRaster")
  expect_equal(terra::values(rendu$mnt), terra::values(pre_t$mnt))
})

test_that("print.foretaccess_mosaique resume la mosaique", {
  mo <- traiter_par_tuiles(toy_preprocess(), cfg_tuiles(), quiet = TRUE)
  expect_message(print(mo), regexp = "Mosaique ForetAccess")
})

test_that("un halo_max inferieur au halo initial est refuse", {
  expect_error(
    foretaccess_config(general = list(halo_initial_m = 500, halo_max_m = 100)),
    regexp = "tuilage incoherente"
  )
})
