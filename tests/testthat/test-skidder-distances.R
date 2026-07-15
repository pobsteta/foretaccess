# Distances de debardage (spec 002 §4.5, CA-2.10) et grille (CA-2.12).

test_that("distance_debardage est la somme exacte des trois composantes (CA-2.10)", {
  sk <- toy_skidder()

  total <- as.numeric(terra::values(sk$distance_debardage))
  treuil <- as.numeric(terra::values(sk$distance_treuillage))
  foret <- as.numeric(terra::values(sk$distance_trainage_foret))
  piste <- as.numeric(terra::values(sk$distance_trainage_piste))

  ok <- !is.na(total)
  expect_equal(total[ok], (treuil + foret + piste)[ok], tolerance = 1e-9)
})

test_that("aucun NA parasite dans les composantes (CA-2.10)", {
  sk <- toy_skidder()

  for (nm in c("distance_treuillage", "distance_trainage_foret", "distance_trainage_piste")) {
    v <- terra::values(sk[[nm]])
    expect_false(anyNA(v), info = nm)
    expect_true(all(v >= 0), info = nm)
  }
})

test_that("les cellules de desserte sont a distance nulle", {
  sk <- toy_skidder()
  pre <- toy_preprocess()
  desserte <- which(!is.na(terra::values(pre$desserte)))

  expect_true(all(terra::values(sk$distance_treuillage)[desserte] == 0))
  expect_true(all(terra::values(sk$distance_trainage_foret)[desserte] == 0))
})

test_that("une cellule treuillee ne traine pas en foret (option 1)", {
  sk <- toy_skidder()
  treuil <- as.numeric(terra::values(sk$distance_treuillage))
  foret <- as.numeric(terra::values(sk$distance_trainage_foret))

  expect_true(all(foret[treuil > 0] == 0))
})

test_that("le trainage sur piste est reporte depuis la cellule de desserte allouee", {
  sk <- toy_skidder()
  piste <- as.numeric(terra::values(sk$distance_trainage_piste))

  # La piste nord-sud du jouet coupe la route est-ouest : la distance sur piste
  # croit en s'eloignant du croisement, sans jamais depasser la demi-longueur.
  expect_gt(max(piste), 0)
  expect_lte(max(piste), 250)
})

test_that("les bordures indeterminees se propagent dans distance_debardage", {
  sk <- toy_skidder()
  pre <- toy_preprocess()

  bord <- is.na(terra::values(pre$slope_pct))
  expect_true(all(is.na(terra::values(sk$distance_debardage)[bord])))
  expect_true(all(is.na(terra::values(sk$accessibilite)[bord])))
})

test_that("tous les rasters de sortie partagent la grille du MNT (CA-2.12)", {
  sk <- toy_skidder()
  mnt <- toy_mnt()

  couches <- c(
    "accessibilite", "distance_treuillage", "distance_trainage_foret",
    "distance_trainage_piste", "distance_debardage", "allocation"
  )
  for (nm in couches) {
    r <- sk[[nm]]
    expect_s4_class(r, "SpatRaster")
    expect_equal(dim(r)[1:2], dim(mnt)[1:2], info = nm)
    expect_equal(terra::res(r), terra::res(mnt), info = nm)
    expect_equal(as.vector(terra::ext(r)), as.vector(terra::ext(mnt)), info = nm)
    expect_true(sf::st_crs(terra::crs(r)) == sf::st_crs(terra::crs(mnt)), info = nm)
  }
})

test_that("les trajets de trainage sont reconstruits sur demande", {
  pre <- toy_preprocess()
  # Une cellule de foret ([25, 225]^2) loin de la desserte, hors portee du treuil.
  cel <- terra::cellFromRowCol(pre$mnt, 10, 10)
  sk <- skidder(pre, trajets_depuis = cel)

  expect_s3_class(sk$trajet, "sf")
  expect_equal(nrow(sk$trajet), 1L)
  expect_true(sf::st_crs(sk$trajet) == sf::st_crs(2154))
})

test_that("write_dir ecrit les rasters et le round-trip est fidele", {
  dir <- withr::local_tempdir()
  sk <- skidder(toy_preprocess(), write_dir = dir)

  expect_named(sk$fichiers, .couches_skidder(), ignore.order = TRUE)
  expect_true(all(file.exists(unlist(sk$fichiers))))

  relu <- terra::rast(file.path(dir, "distance_debardage.tif"))
  cmp <- compare_to_oracle(
    as.numeric(terra::values(relu)),
    as.numeric(terra::values(sk$distance_debardage)),
    tol_rel = 1e-6
  )
  expect_true(cmp$ok)
})

test_that("sans piste, le trainage sur piste est nul partout", {
  desserte <- toy_desserte()
  desserte$classe[desserte$classe == "piste"] <- "route"
  pre <- preprocess(mnt = toy_mnt(), desserte = desserte, foret = toy_foret())

  sk <- skidder(pre)
  expect_true(all(terra::values(sk$distance_trainage_piste) == 0))
})

test_that("la distance sur piste est ponderee par la pente, pas uniforme", {
  # Sylvaccess propage sur `Pond_pente`, comme le trainage en foret. Sur le jouet
  # (20 % partout), un pas orthogonal de piste coute 5 x sqrt(1 + 0,2^2) = 5,0990 m.
  sk <- toy_skidder()
  piste <- as.numeric(terra::values(sk$distance_trainage_piste))
  pas <- 5 * sqrt(1 + 0.2^2)

  positifs <- sort(unique(round(piste[piste > 0], 6)))
  expect_equal(positifs[1], pas, tolerance = 1e-6)
  expect_false(isTRUE(all.equal(positifs[1], 5)))
})

# --- Ponderation de la piste (Lot 12a, specs/012) ----------------------------

# Un jeu ou la ponderation MORD, que ColduPre ne peut pas exhiber (reseau trop
# dense : les deux dessertes y sont toujours a portee comparable). Geometrie :
#
#   colonne 1        : ROUTE (verticale, bord gauche)
#   colonne 21       : PISTE (verticale), reliee a la route par une seule cellule
#                      en bas -> elle est LONGUE a remonter
#   la cellule cible : en colonne 16, donc PLUS PRES de la piste que de la route
#
# Sans ponderation, la cible s'alloue a la piste (elle est plus proche a vol de
# cout). Avec l'arbitrage `d_foret_route <= d_foret_piste + 0,1 x d_piste`, la
# route l'emporte des que la piste a beaucoup de chemin a faire pour la rejoindre.
.pre_piste_longue <- function(n = 41L) {
  mnt <- terra::rast(
    nrows = n, ncols = n, xmin = 0, xmax = n * 5, ymin = 0, ymax = n * 5,
    crs = "EPSG:2154"
  )
  terra::values(mnt) <- 100 # plat : le cout ne depend que de la geometrie

  desserte <- terra::rast(mnt)
  v <- rep(NA_real_, terra::ncell(desserte))
  lig <- seq_len(n)
  v[(lig - 1L) * n + 1L] <- 1 # colonne 1  : route
  v[(lig - 1L) * n + 21L] <- 2 # colonne 21 : piste
  v[(n - 1L) * n + seq_len(21L)] <- 2 # derniere ligne : la piste rejoint la route
  terra::values(desserte) <- v
  levels(desserte) <- data.frame(id = c(1, 2), classe = c("route", "piste"))

  foret <- terra::rast(mnt)
  terra::values(foret) <- 1

  zero <- function() terra::setValues(terra::rast(mnt), 0)

  pre <- toy_preprocess()
  pre$mnt <- mnt
  pre$desserte <- desserte
  pre$desserte_sf <- NULL
  pre$foret_mask <- foret
  pre$slope_pct <- zero()
  pre$slope_max_local <- zero()
  pre$aspect_deg <- terra::setValues(terra::rast(mnt), NA_real_)
  pre$obstacles_complets_mask <- zero()
  pre$obstacles_partiels_mask <- zero()
  pre$reseau_public_mask <- zero()
  pre$exclusion_mask <- zero()
  pre$volume <- NULL
  pre$parcellaire <- NULL
  pre$distance_piste <- NULL
  pre
}

# Cible : ligne 1 (le plus loin possible du raccord piste -> route), colonne 13.
# Elle est PLUS PRES de la piste (8 cellules) que de la route (12 cellules) : sans
# ponderation, elle s'alloue a la piste. Mais cette piste doit redescendre ~294 m
# pour rejoindre la route, et `12 x 5 = 60 <= 8 x 5 + 0,1 x 294 = 69,4` : la route
# l'emporte des que l'arbitrage compte la piste.
.cible_piste_longue <- 13L

.skidder_piste_longue <- function(c_arb = 0.1) {
  cfg <- foretaccess_config(skidder = list(
    # Pas de treuillage : on isole le trainage.
    debardage_amont_max_m = 0, debardage_aval_max_m = 0,
    ponderation_piste_arbitrage = c_arb
  ))
  sk <- skidder(.pre_piste_longue(), cfg)
  list(
    foret = as.numeric(terra::values(sk$distance_trainage_foret))[.cible_piste_longue],
    piste = as.numeric(terra::values(sk$distance_trainage_piste))[.cible_piste_longue]
  )
}

test_that("l'arbitrage prefere la route quand la piste est longue a remonter", {
  d <- .skidder_piste_longue(c_arb = 0.1)

  # La route l'emporte : trainage en foret jusqu'a la colonne 1 (12 pas de 5 m), et
  # plus aucune piste a remonter.
  expect_equal(d$piste, 0)
  expect_equal(d$foret, 12 * 5, tolerance = 1e-6)
})

test_that("sans ponderation d'arbitrage, la meme cellule s'allouerait a la piste", {
  # Contre-epreuve : le coefficient a bien un effet. A 0, la route ne l'emporte que si
  # elle est plus proche EN FORET -- ce qu'elle n'est pas. La cellule bascule sur la
  # piste : moins de foret a traverser, mais 294 m de piste a remonter ensuite.
  d <- .skidder_piste_longue(c_arb = 0)

  expect_gt(d$piste, 250)
  expect_lt(d$foret, 12 * 5)
})
