# Moteur porteur : grappin, classement, distances, tuilage (spec 003 §4.3-§4.6).

test_that("le grappin etend l'accessibilite au-dela de la zone conduite (CA-3.5)", {
  # Plan a 20 % : le devers (> seuil 15 %) bloque la conduite en travers, ne laissant
  # rouler que le sens de la pente. Le grappin recupere alors la frange de terrain
  # recoltable en bordure de la zone conduite -- les cellules code 2.
  pre <- pre_plan(pente = 0.20, n = 61)
  po <- porteur(pre, foretaccess_config())

  codes <- terra::values(po$accessibilite)
  # Il existe des cellules parcourables (l'engin roule) et des cellules seulement
  # accessibles (le grappin atteint sans que l'engin roule).
  expect_gt(sum(codes == 1, na.rm = TRUE), 0)
  expect_gt(sum(codes == 2, na.rm = TRUE), 0)

  # Les cellules du grappin portent une distance de grappin non nulle, bornee.
  d_grap <- terra::values(po$distance_grappin)
  grappe <- codes == 2
  expect_true(all(d_grap[grappe] > 0, na.rm = TRUE))
  expect_lte(max(d_grap, na.rm = TRUE), foretaccess_config()$porteur$portee_grue_m)
})

test_that("le grappin ne classe pas ses cellules comme parcourables", {
  pre <- pre_plan(pente = 0.10, n = 61)
  po <- porteur(pre)

  codes <- as.numeric(terra::values(po$accessibilite))
  d_grap <- as.numeric(terra::values(po$distance_grappin))
  # Une cellule atteinte par le grappin (distance grappin > 0) n'est jamais parcourable.
  expect_equal(sum(codes == 1 & d_grap > 0, na.rm = TRUE), 0)
})

test_that("la distance de debardage additionne conduite, grappin et piste", {
  po <- porteur(toy_preprocess())
  d <- terra::values(po$distance_debardage)
  somme <- terra::values(po$distance_conduite) +
    terra::values(po$distance_grappin) +
    terra::values(po$distance_trainage_piste)

  fini <- !is.na(d)
  expect_equal(d[fini], somme[fini])
})

test_that("les obstacles complets excluent la conduite du porteur (CA-3.7)", {
  pre <- preprocess(
    mnt = toy_mnt(), desserte = toy_desserte(), foret = toy_foret(),
    obstacles_complets = toy_obstacles(xmin = 50, ymin = 150)
  )
  po <- porteur(pre)
  complets <- which(terra::values(pre$obstacles_complets_mask) == 1)
  codes <- terra::values(po$accessibilite)[complets]
  # Hors zone conduite et hors zone recoltable : non accessibles.
  expect_true(all(codes == 3, na.rm = TRUE))
})

test_that("le tableau recapitulatif conserve la surface (CA-3.8)", {
  po <- porteur(toy_preprocess())
  expect_equal(sum(po$recap$cellules), terra::ncell(toy_preprocess()$mnt))
  expect_true("indetermine" %in% po$recap$classe)
})

test_that("une desserte absente leve une erreur ciblee", {
  pre <- toy_preprocess()
  pre$desserte <- terra::rast(pre$mnt)
  terra::values(pre$desserte) <- NA_real_
  expect_error(porteur(pre), regexp = "Aucune cellule de desserte")
})

test_that("porteur ecrit ses couches en COG relisibles", {
  withr::with_tempdir({
    po <- porteur(toy_preprocess(), write_dir = "sortie")
    expect_named(po$fichiers, .couches_porteur(), ignore.order = TRUE)
    expect_true(all(file.exists(unlist(po$fichiers))))
    relu <- terra::rast(file.path("sortie", "distance_conduite.tif"))
    expect_equal(terra::values(relu), terra::values(po$distance_conduite))
  })
})

test_that("print.foretaccess_porteur resume le moteur", {
  expect_message(print(porteur(toy_preprocess())), regexp = "Moteur porteur")
})

# --- Tuilage (CA-3.9) -------------------------------------------------------

test_that("le porteur tuile a l'identique du mono-bloc (CA-3.9)", {
  pre <- toy_preprocess()
  ref <- porteur(pre)
  cfg <- foretaccess_config(general = list(
    tuile_m = 100, halo_initial_m = 350, halo_max_m = 1000
  ))
  mo <- traiter_par_tuiles(pre, cfg, moteur = porteur,
    couches = .couches_porteur(), quiet = TRUE)

  for (nm in .couches_porteur()) {
    expect_equal(
      as.numeric(terra::values(mo[[nm]])),
      as.numeric(terra::values(ref[[nm]])),
      info = nm
    )
  }
})

test_that("le halo suffisant du porteur couvre conduite plus grappin", {
  # Un halo trop court pour la portee de conduite laisse des cellules indeterminees ;
  # un halo qui la couvre certifie tout.
  pre <- toy_preprocess()
  res <- terra::res(pre$mnt)[1]
  po <- foretaccess_config()$porteur
  suffisant <- po$distance_pente_forte_max_m + po$portee_grue_m + 1.5 * res

  large <- foretaccess_config(general = list(
    tuile_m = 100, halo_initial_m = suffisant, halo_max_m = suffisant
  ))
  mo <- traiter_par_tuiles(pre, large, moteur = porteur,
    couches = .couches_porteur(), quiet = TRUE)
  expect_true(all(terra::values(mo$certifie) == 1))
})
