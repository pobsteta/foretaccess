# Desserte detectee sur le MNT (spec 026). dessertR est absent en CI : les tests
# exercent le REPLI, le balayage de seuils, et le recoupement automatique aux
# objets BD TOPO connus -- la partie testable sans nuage de points.

test_that("sans dessertR : couche vide et message, jamais d'echec", {
  testthat::local_mocked_bindings(.dessertr_dispo = function() FALSE)
  r <- terra::rast(terra::ext(0, 100, 0, 100), resolution = 1, crs = "EPSG:2154")
  terra::values(r) <- seq_len(terra::ncell(r))
  out <- suppressMessages(detecter_desserte(r))
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 0L)
  expect_true(all(c("source", "p_desserte") %in% names(out)))
})

test_that("le balayage couvre la plage prescrite et rend une ligne par seuil", {
  # La spec 026 ne pose PAS un seuil : elle mesure ou la detection decroche.
  testthat::local_mocked_bindings(.dessertr_dispo = function() FALSE)
  r <- terra::rast(terra::ext(0, 100, 0, 100), resolution = 1, crs = "EPSG:2154")
  terra::values(r) <- 1
  tab <- suppressMessages(detecter_desserte_balayage(r))
  expect_equal(nrow(tab), 5L)
  expect_equal(tab$seuil, seq(0.4, 0.8, by = 0.1))
  expect_true(all(tab$km == 0))
})

test_that("le recoupement aux objets connus quantifie des faux positifs", {
  seg <- function(a, b) sf::st_linestring(rbind(a, b))
  # Un « detecte » superpose a un cours d'eau connu : faux positif evident.
  # Un autre a l'ecart : candidat a instruire.
  detecte <- sf::st_sf(source = "detectee", p_desserte = c(0.7, 0.7),
    geometry = sf::st_sfc(seg(c(0, 0), c(100, 0)), seg(c(0, 500), c(100, 500)),
      crs = 2154))
  connus <- sf::st_sf(type = "cours_d_eau",
    geometry = sf::st_sfc(seg(c(0, 2), c(100, 2)), crs = 2154))

  testthat::local_mocked_bindings(
    detecter_desserte = function(...) detecte, .package = "foretaccess")
  tab <- detecter_desserte_balayage(NULL, objets_connus = connus,
    seuils = 0.6, tol_recoupement = 10)
  expect_equal(nrow(tab), 1L)
  expect_equal(tab$km, 0.2, tolerance = 1e-6)
  # La moitie du lineaire recoupe un objet connu.
  expect_equal(tab$km_recoupe, 0.1, tolerance = 1e-6)
  expect_equal(tab$pct_recoupe, 50, tolerance = 1e-6)
})

test_that("sans objets connus, le recoupement est NA -- pas zero", {
  # Zero dirait « aucun faux positif », ce qu'on n'a pas mesure. NA dit
  # « non mesure », qui est la verite.
  detecte <- sf::st_sf(source = "detectee", p_desserte = 0.7,
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(0, 0), c(100, 0))), crs = 2154))
  testthat::local_mocked_bindings(
    detecter_desserte = function(...) detecte, .package = "foretaccess")
  tab <- detecter_desserte_balayage(NULL, seuils = 0.6)
  expect_true(is.na(tab$km_recoupe))
  expect_true(is.na(tab$pct_recoupe))
})

test_that("le cout de reouverture est SOURCE et vaut 0,65 du cout de creation", {
  co <- foretaccess_config()$desserte$cout
  # Milieu de deux baremes regionaux repris de plafonds fixes par l'Etat :
  # mise au gabarit / creation d'une route empierree = 45/65 (Puy-de-Dome) et
  # 40/65 (Auvergne-Rhone-Alpes). Cf. spec 026 sec.7.3.
  expect_equal(co$fraction_reouverture, 0.65)
  expect_equal(co$cout_base_m * co$fraction_reouverture, 13)
  # Le bareme donne « route en terrain naturel : 20 000 EUR/km » : notre
  # cout_base_m, pose anterieurement, s'en trouve confirme.
  expect_equal(co$cout_base_m, 20)
})
