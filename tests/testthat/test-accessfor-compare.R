# comparer_accessfor() : matrice de confusion classes_debardage() vs ACCESSFOR,
# sur donnees synthetiques (hors reseau). Le livrable chiffre sur Chastel-Nouvel
# vit dans data-raw/accessfor_compare.R (WFS + acquisition, hors CI).

# Grille cl 10x10 a 5 m en Lambert-93, avec les niveaux exacts de classes_debardage().
cl_synth <- function(vals) {
  r <- terra::rast(
    nrows = 10, ncols = 10, xmin = 0, xmax = 50, ymin = 0, ymax = 50,
    crs = "EPSG:2154"
  )
  terra::values(r) <- vals
  co <- accessfor_correspondance()
  levels(r) <- data.frame(value = co$fa_value, classe = co$fa_classe)
  names(r) <- "classe_debardage"
  r
}

# Polygone ACCESSFOR couvrant une bande de colonnes [x0,x1), portant `class`.
af_poly <- function(x0, x1, class) {
  sf::st_sf(
    class = as.integer(class),
    geometry = sf::st_sfc(sf::st_polygon(list(rbind(
      c(x0, 0), c(x1, 0), c(x1, 50), c(x0, 50), c(x0, 0)
    ))), crs = 2154)
  )
}

test_that("accord parfait quand nos classes = ACCESSFOR traduit", {
  # Moitie ouest : bande 1 (0-250) = ACCESSFOR class 3 ; moitie est : inaccessible
  # (notre 7) = ACCESSFOR class 1.
  m <- matrix(NA_integer_, 10, 10)
  m[, 1:5] <- 1L # notre bande 1
  m[, 6:10] <- 7L # inaccessible
  cl <- cl_synth(as.integer(t(m)))

  af <- rbind(af_poly(0, 25, 3), af_poly(25, 50, 1))
  cmp <- comparer_accessfor(cl, af)

  expect_s3_class(cmp, "foretaccess_accessfor_compare")
  expect_equal(cmp$accord_global, 1)
  expect_equal(cmp$accord_agrege, 1)
  # Toute la surface est comparee (pas de hors_foret, ACCESSFOR partout).
  expect_equal(cmp$surface_ha$commun, 100 * (5 * 5) / 10000)
})

test_that("un desaccord de bande baisse l'accord global mais pas l'agrege", {
  # Ouest : nous bande 1 (0-250), ACCESSFOR classe 4 (250-500) -> desaccord de
  # bande, mais les deux restent ACCESSIBLE. Est : accord inaccessible.
  m <- matrix(NA_integer_, 10, 10)
  m[, 1:5] <- 1L
  m[, 6:10] <- 7L
  cl <- cl_synth(as.integer(t(m)))

  af <- rbind(af_poly(0, 25, 4), af_poly(25, 50, 1))
  cmp <- comparer_accessfor(cl, af)

  expect_lt(cmp$accord_global, 1) # bande 1 vs bande 2 : hors diagonale
  expect_equal(cmp$accord_agrege, 1) # accessible des deux cotes
})

test_that("un flip accessible <-> inaccessible fait chuter l'accord agrege", {
  m <- matrix(1L, 10, 10) # nous : tout accessible bande 1
  cl <- cl_synth(as.integer(t(m)))
  af <- af_poly(0, 50, 1) # ACCESSFOR : tout inaccessible
  cmp <- comparer_accessfor(cl, af)
  expect_equal(cmp$accord_agrege, 0)
})

test_that("la comparaison ne porte que sur l'intersection des masques", {
  # Ouest : nous hors_foret (9), ACCESSFOR present -> exclu (accessfor_seul).
  # Est : nous foret bande 1, ACCESSFOR absent -> exclu (notre_seul).
  m <- matrix(NA_integer_, 10, 10)
  m[, 1:5] <- 9L # hors_foret
  m[, 6:10] <- 1L # bande 1
  cl <- cl_synth(as.integer(t(m)))

  af <- af_poly(0, 25, 3) # ACCESSFOR seulement a l'ouest
  cmp <- comparer_accessfor(cl, af)

  cell_ha <- (5 * 5) / 10000
  expect_equal(cmp$surface_ha$commun, 0) # aucune cellule commune
  expect_equal(cmp$surface_ha$accessfor_seul, 50 * cell_ha) # ouest : IGN foret, nous non
  expect_equal(cmp$surface_ha$notre_seul, 50 * cell_ha) # est : nous foret, IGN non
})

test_that("class=2 ACCESSFOR tombe sur notre inexploitable", {
  m <- matrix(8L, 10, 10) # nous : inexploitable partout
  cl <- cl_synth(as.integer(t(m)))
  af <- af_poly(0, 50, 2) # ACCESSFOR : zone non exploitable (pente)
  cmp <- comparer_accessfor(cl, af)
  expect_equal(cmp$accord_global, 1)
})

test_that("le CRS d'ACCESSFOR doit egaler celui de cl (ADR-004)", {
  cl <- cl_synth(rep(1L, 100))
  af <- sf::st_transform(af_poly(0, 50, 3), 4326)
  expect_error(comparer_accessfor(cl, af), "CRS")
})

test_that("un champ de classe absent est signale", {
  cl <- cl_synth(rep(1L, 100))
  af <- af_poly(0, 50, 3)
  names(af)[1] <- "code"
  expect_error(comparer_accessfor(cl, af), "champ")
})

test_that("le print rend un resume concis (pas le dump de l'objet)", {
  cl <- cl_synth(rep(1L, 100))
  cmp <- comparer_accessfor(cl, af_poly(0, 50, 3))
  expect_message(print(cmp), "accord global")
  expect_message(print(cmp), "accord agrege")
})
