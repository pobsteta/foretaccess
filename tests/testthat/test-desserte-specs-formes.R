# `detecter_desserte(specs =)` acceptait UNE forme, et dessertR conseille d'en
# produire une AUTRE quand ses bornes saturent. Deux contrats pour un meme mot :
# la voie recommandee par le paquet enveloppe etait fermee a qui arrive par
# foretaccess. Brief nemetonshiny du 2026-08-12 (B).

calib_plate <- function() {
  list(
    rugosite   = list(type = "croissante", a = 0.04, b = 0.17, poids = 2),
    pente      = list(type = "decroissante", a = 4.5, b = 20.3, poids = 2),
    vesselness = list(type = "croissante", a = 0.0006, b = 0.07, poids = 2)
  )
}

test_that("la forme PLATE de dsr_calibrer_specs() est reconnue", {
  expect_true(foretaccess:::.specs_est_plate(calib_plate()))
  # La forme imbriquee ne doit PAS passer pour plate : ses elements sont des
  # groupes, pas des regles d'appartenance.
  expect_false(foretaccess:::.specs_est_plate(specs_desserte_calibrees()))
})

test_that("specs_depuis_calibration() promeut la calibration en geomorpho", {
  out <- specs_depuis_calibration(calib_plate())
  expect_named(out, c("geomorpho", "surface", "c_vessel"))
  # `$specs` de dessertR est « directement utilisable » par `dsr_conductivite()`,
  # que `detecter_desserte()` alimente avec `specs$geomorpho` : c'est le meme
  # objet, d'ou la promotion telle quelle.
  expect_identical(out$geomorpho, calib_plate())
  # Ce qu'une calibration ne produit PAS garde les bornes figees.
  expect_identical(out$surface, specs_desserte_calibrees()$surface)
  expect_identical(out$c_vessel, specs_desserte_calibrees()$c_vessel)
})

test_that("specs_depuis_calibration() accepte le resultat COMPLET de la calibration", {
  # dessertR rend une liste de quatre elements dont `$specs` : accepter les deux
  # evite a l'appelant de savoir lequel extraire.
  complet <- list(specs = calib_plate(), diagnostic = data.frame(canal = "rugosite"))
  expect_identical(specs_depuis_calibration(complet)$geomorpho, calib_plate())
})

test_that("on peut renoncer aux bornes figees explicitement", {
  out <- specs_depuis_calibration(calib_plate(), surface = NULL, c_vessel = NULL)
  expect_null(out$surface)
  expect_null(out$c_vessel)
})

test_that("une entree qui n'est ni plate ni imbriquee est REJETEE", {
  expect_error(specs_depuis_calibration(list(a = 1, b = 2)), "PLATE")
  expect_error(specs_depuis_calibration(list()), "forme attendue")
  expect_error(foretaccess:::.specs_normaliser(list(truc = 1, machin = 2)),
               "aucune des formes")
})

test_that(".specs_normaliser() laisse passer les formes deja bonnes", {
  expect_null(foretaccess:::.specs_normaliser(NULL))
  fige <- specs_desserte_calibrees()
  expect_identical(foretaccess:::.specs_normaliser(fige), fige)
  # La forme plate est promue -- avec un message, pour que l'appelant sache que
  # `surface` et `c_vessel` ne viennent pas de sa calibration.
  expect_message(out <- foretaccess:::.specs_normaliser(calib_plate()), "Calibration")
  expect_identical(out$geomorpho, calib_plate())
})

test_that("specs = auto sans reference echoue en le DISANT", {
  # Sans desserte connue, la calibration n'a rien a apprendre : mieux vaut le
  # dire que retomber en silence sur des bornes figees qui saturent.
  mnt <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 4,
                     crs = "EPSG:2154")
  terra::values(mnt) <- 1
  # `detecter_desserte()` rend une couche vide AVANT la garde quand dessertR
  # manque : on force la disponibilite pour que la garde soit reellement
  # atteinte. Sans ce mock, le test dependait de l'environnement -- il passait
  # seul et se sautait dans la suite complete.
  testthat::local_mocked_bindings(.dessertr_dispo = function() TRUE)
  expect_error(detecter_desserte(mnt, reference = NULL, specs = "auto"),
               "reference")
})
