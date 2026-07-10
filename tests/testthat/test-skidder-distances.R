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
