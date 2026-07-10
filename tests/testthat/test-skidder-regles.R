# Regles du moteur skidder (spec 002 §4.5, CA-2.8, CA-2.9, CA-2.13).

test_that("sur le jouet a 20 %, tout ce qui est atteint est parcourable (CA-2.8)", {
  sk <- toy_skidder()
  classes <- terra::levels(sk$accessibilite)[[1]]

  expect_equal(classes$classe, c("parcourable", "accessible", "non_accessible", "hors_foret"))

  r <- sk$recap
  # La pente vaut 20 % partout, sous le seuil skidder de 30 % : aucune cellule
  # n'est seulement « accessible » (treuillee sans etre parcourable), et aucune
  # cellule de foret n'est inaccessible.
  expect_equal(r$cellules[r$classe == "accessible"], 0)
  expect_equal(r$cellules[r$classe == "non_accessible"], 0)
  expect_gt(r$cellules[r$classe == "parcourable"], 0)
})

test_that("le treuillage s'applique meme sous le seuil de pente skidder", {
  # Contre-intuitif mais conforme au .pyx : `Zone_OK` borne le treuillage par la
  # pente d'ABATTAGE (100 %), pas par la pente skidder (30 %). Une cellule proche
  # de la desserte est donc treuillee, quelle que soit sa pente.
  sk <- toy_skidder()
  dt <- terra::values(sk$distance_treuillage)

  expect_gt(sum(dt > 0, na.rm = TRUE), 0)
  expect_lte(max(dt, na.rm = TRUE), 100) # plafond aval
})

test_that("sur un MNT a 60 %, la portee amont est plus courte que l'aval (CA-2.9)", {
  sk <- skidder(toy_preprocess_pente_forte())
  dt <- terra::values(sk$distance_treuillage)

  expect_gt(sum(dt > 0, na.rm = TRUE), 0)
  # Plafond aval a 60 % de pente : 100 m. Aucune distance ne peut le depasser.
  expect_lte(max(dt, na.rm = TRUE), 100)
})

test_that("au-dela du seuil de pente skidder, les cellules ne sont plus parcourables", {
  # Pente skidder abaissee a 10 % : le jouet (20 %) n'est plus roulable, mais
  # reste treuillable, donc « accessible » et non « non_accessible ».
  pre <- toy_preprocess()
  cfg <- foretaccess_config(skidder = list(pente_skidder_max_pct = 10))
  sk <- skidder(pre, cfg)

  # Les cellules de desserte restent parcourables par construction : on regarde
  # donc la foret hors desserte.
  hors_desserte <- is.na(terra::values(pre$desserte))
  codes <- terra::values(sk$accessibilite)[hors_desserte]

  expect_equal(sum(codes == 1, na.rm = TRUE), 0)
  expect_gt(sum(codes == 2, na.rm = TRUE), 0)
})

# Le carre d'obstacles par defaut ([50,100]^2) est traverse par la piste DFCI
# diagonale du jouet, qui va de (0,0) a (250,250) : ses cellules seraient alors
# aussi des cellules de desserte. On le decale au nord-ouest.
obstacles_hors_desserte <- function() toy_obstacles(xmin = 50, ymin = 150)

test_that("les obstacles complets rendent leurs cellules non accessibles (CA-2.13)", {
  pre <- preprocess(
    mnt = toy_mnt(), desserte = toy_desserte(), foret = toy_foret(),
    obstacles_complets = obstacles_hors_desserte()
  )
  sk <- skidder(pre)

  complets <- which(terra::values(pre$obstacles_complets_mask) == 1)
  codes <- terra::values(sk$accessibilite)[complets]
  # 3 = non_accessible. Ils sont hors zone treuillable et hors zone de roulage.
  expect_true(all(codes == 3, na.rm = TRUE))
})

test_that("les obstacles partiels bloquent le roulage mais pas le treuillage (CA-2.13)", {
  pre <- preprocess(
    mnt = toy_mnt(), desserte = toy_desserte(), foret = toy_foret(),
    obstacles_partiels = obstacles_hors_desserte()
  )
  sk <- skidder(pre)

  partiels <- which(terra::values(pre$obstacles_partiels_mask) == 1)
  codes <- terra::values(sk$accessibilite)[partiels]
  dt <- terra::values(sk$distance_treuillage)[partiels]

  # Non parcourables (1), mais accessibles au treuil (2) -- pour celles qui sont
  # dans la portee du treuil ; les plus eloignees restent non accessibles (3).
  expect_false(any(codes == 1, na.rm = TRUE))
  expect_gt(sum(codes == 2, na.rm = TRUE), 0)
  expect_true(all(dt[codes == 2] > 0, na.rm = TRUE))
})

test_that("l'option de modelisation 2 leve une erreur explicite", {
  cfg <- foretaccess_config(skidder = list(option_modelisation = 2L))
  expect_error(skidder(toy_preprocess(), cfg), regexp = "option de modelisation 1")
})

test_that("une desserte absente leve une erreur ciblee", {
  pre <- toy_preprocess()
  pre$desserte <- terra::rast(pre$mnt)
  terra::values(pre$desserte) <- NA_real_
  expect_error(skidder(pre), regexp = "Aucune cellule de desserte")
})

test_that("print.foretaccess_skidder resume le moteur", {
  expect_message(print(toy_skidder()), regexp = "Moteur skidder")
})
