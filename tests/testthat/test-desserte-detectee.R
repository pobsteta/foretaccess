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

# Bornes calibrees (spec 026). Le defaut de dessertR (`a = NULL`, `b = NULL`)
# fait deriver les bornes PAR QUANTILES DE L'EMPRISE : le meme terrain rend des
# detections differentes selon le decoupage (mesure du 2026-07-31 : 116 m sur
# 0,25 km2 analyses seuls, 0 m sur la meme fenetre dans 4 km2). Ces tests
# gardent la propriete qui rend `seuil` absolu : TOUTE borne est renseignee.
test_that("specs_desserte_calibrees porte des bornes numeriques completes", {
  sp <- specs_desserte_calibrees()
  expect_named(sp, c("geomorpho", "surface", "c_vessel"))
  tous <- c(sp$geomorpho, sp$surface)
  expect_gt(length(tous), 0)
  for (n in names(tous)) {
    s <- tous[[n]]
    # Le coeur du correctif : ni `a` ni `b` ne doit etre NULL, sinon
    # `dsr_appartenance()` retombe sur les quantiles.
    expect_true(is.numeric(s$a) && length(s$a) == 1L && is.finite(s$a), info = n)
    expect_true(is.numeric(s$b) && length(s$b) == 1L && is.finite(s$b), info = n)
    expect_true(s$a < s$b, info = paste(n, ": a doit etre < b"))
    expect_true(s$type %in% c("croissante", "decroissante"), info = n)
    expect_true(is.numeric(s$poids) && s$poids > 0, info = n)
  }
})

test_that("la calibration de reference reste absolue et sans canal indetermine", {
  sp <- specs_desserte_calibrees()
  # `rugosite` : dessertR le declare `decroissante` dans ses specs PAR DEFAUT,
  # la mesure donne sens +1 (AUC 0,767). `dsr_calibrer_specs()` le retrouve.
  expect_identical(sp$geomorpho$rugosite$type, "croissante")
  # `densite_sousetage` ECARTE, non parce qu'il serait aveugle -- il ne l'est
  # pas, AUC 0,565 -- mais parce que ses bornes sortent indeterminees (les deux
  # populations sont a zero en mediane). Le garder ferait retomber ce canal sur
  # la derivation par quantiles, donc sur la dependance a l'emprise.
  expect_false("densite_sousetage" %in% names(sp$surface))
  # Les meilleurs canaux mesures portent bien le poids le plus fort.
  expect_equal(sp$surface$taux_penetration$poids, 3)
  expect_equal(sp$surface$densite_sol$poids, 3)
})

test_that("detecter_desserte expose specs, calibrees par defaut", {
  expect_true("specs" %in% names(formals(detecter_desserte)))
  # Le DEFAUT doit etre les bornes calibrees : c'est lui qui rend `seuil`
  # absolu. Un defaut a NULL ramenerait l'ancrage par quantiles sans bruit.
  expect_identical(eval(formals(detecter_desserte)$specs),
    specs_desserte_calibrees())
})

test_that("l'attribut canal_surface est pose meme sur une couche vide", {
  # Sans lui, un resultat nul ne se distingue pas d'un resultat nul obtenu
  # SANS le canal de surface -- et `cli_warn` differe son message jusqu'a la
  # fin du script, donc l'avertissement n'aide pas pendant un banc long.
  testthat::local_mocked_bindings(.dessertr_dispo = function() FALSE)
  r <- terra::rast(terra::ext(0, 100, 0, 100), resolution = 1, crs = "EPSG:2154")
  terra::values(r) <- 1
  out <- suppressMessages(detecter_desserte(r))
  expect_false(is.null(attr(out, "canal_surface")))
  expect_false(attr(out, "canal_surface"))
})

test_that("la calibration porte un c de Frangi par echelle", {
  sp <- specs_desserte_calibrees()
  # Sans `c_vessel`, les bornes ne suffisent pas : `dsr_frangi()` prend
  # `c = 0,5 * max(norme de Hessien) du raster fourni`, EN AMONT des
  # appartenances. Un scalaire unique ne conviendrait pas non plus -- `c` varie
  # de 3,5x entre echelles. Relaye par `dsr_layers_dtm(c_vessel = )` (1.1.0).
  expect_true(is.numeric(sp$c_vessel))
  expect_length(sp$c_vessel, 3L)
  expect_true(all(sp$c_vessel > 0))
  expect_true(all(diff(unname(sp$c_vessel)) > 0))
})
