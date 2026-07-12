# Moteur camion DFCI (beta) : zone defendable, portee, pente, sources, tuilage
# (spec 006-dfci).

test_that("la zone defendable est un tampon borne autour de la desserte DFCI (CA-6.1)", {
  pre <- pre_plan_dfci(pente = 0.05, n = 61)
  cfg <- foretaccess_config()
  df <- camion_dfci(pre, cfg)

  codes <- as.numeric(terra::values(df$accessibilite))
  # Il existe des cellules defendables (code 1) et non defendables (code 2).
  expect_gt(sum(codes == 1, na.rm = TRUE), 0)
  expect_gt(sum(codes == 2, na.rm = TRUE), 0)

  # La distance de defense est bornee par la portee configuree.
  d <- as.numeric(terra::values(df$distance_defense))
  expect_lte(max(d, na.rm = TRUE), cfg$dfci$distance_defense_max_m)
  # Les cellules defendables portent une distance <= portee ; hors portee = non defendable.
  expect_true(all(d[codes == 1] <= cfg$dfci$distance_defense_max_m, na.rm = TRUE))
})

test_that("une portee plus grande etend la zone defendable", {
  pre <- pre_plan_dfci(pente = 0.05, n = 81)
  petite <- camion_dfci(pre, foretaccess_config(dfci = list(distance_defense_max_m = 50)))
  grande <- camion_dfci(pre, foretaccess_config(dfci = list(distance_defense_max_m = 150)))

  n_petite <- sum(terra::values(petite$accessibilite) == 1, na.rm = TRUE)
  n_grande <- sum(terra::values(grande$accessibilite) == 1, na.rm = TRUE)
  expect_gt(n_grande, n_petite)
})

test_that("le terrain au-dela de la pente d'intervention n'est pas defendable", {
  # Plan doux : large zone defendable. Plan raide (> 40 %) : le terrain est
  # infranchissable, la zone defendable s'effondre.
  doux  <- camion_dfci(pre_plan_dfci(pente = 0.05, n = 61))
  raide <- camion_dfci(pre_plan_dfci(pente = 0.60, n = 61))

  n_doux  <- sum(terra::values(doux$accessibilite) == 1, na.rm = TRUE)
  n_raide <- sum(terra::values(raide$accessibilite) == 1, na.rm = TRUE)
  expect_gt(n_doux, n_raide)
})

test_that("classes_source selectionne les dessertes servant de base", {
  # Une desserte de piste seule : ignoree par defaut (source = dfci), utilisee si
  # on l'ajoute a classes_source.
  pre <- pre_plan_dfci(pente = 0.05, n = 41, classe = "piste")
  expect_error(camion_dfci(pre), regexp = "Aucune desserte-source DFCI")

  cfg <- foretaccess_config(dfci = list(classes_source = c("dfci", "piste")))
  df <- camion_dfci(pre, cfg)
  expect_gt(sum(terra::values(df$accessibilite) == 1, na.rm = TRUE), 0)
})

test_that("le tableau recapitulatif conserve la surface", {
  df <- camion_dfci(toy_preprocess())
  expect_equal(sum(df$recap$cellules), terra::ncell(toy_preprocess()$mnt))
  expect_true("indetermine" %in% df$recap$classe)
  expect_true(all(c("defendable", "non_defendable", "hors_foret") %in% df$recap$classe))
})

test_that("une desserte-source absente leve une erreur ciblee", {
  pre <- toy_preprocess()
  pre$desserte <- terra::rast(pre$mnt)
  terra::values(pre$desserte) <- NA_real_
  expect_error(camion_dfci(pre), regexp = "Aucune desserte-source DFCI")
})

test_that("le camion DFCI ecrit ses couches en COG relisibles", {
  withr::with_tempdir({
    df <- camion_dfci(toy_preprocess(), write_dir = "sortie")
    expect_named(df$fichiers, .couches_dfci(), ignore.order = TRUE)
    expect_true(all(file.exists(unlist(df$fichiers))))
    relu <- terra::rast(file.path("sortie", "distance_defense.tif"))
    expect_equal(terra::values(relu), terra::values(df$distance_defense),
      tolerance = 1e-5)
  })
})

test_that("print.foretaccess_dfci resume le moteur", {
  expect_message(print(camion_dfci(toy_preprocess())), regexp = "camion DFCI")
})

# --- Tuilage : bornee, donc certifiable par un halo suffisant ---------------

test_that("le camion DFCI tuile egale le mono-bloc sur les cellules certifiees", {
  # Le reseau DFCI est clairseme (une seule ligne sur le jouet) : une tuile dont
  # le halo n'atteint pas cette ligne reste indeterminee. La garantie du tuilage
  # porte donc sur les cellules *certifiees* -- elles doivent egaler le mono-bloc.
  pre <- toy_preprocess()
  ref <- camion_dfci(pre)
  cfg <- foretaccess_config(general = list(
    tuile_m = 100, halo_initial_m = 250, halo_max_m = 600
  ))
  mo <- traiter_par_tuiles(pre, cfg, moteur = camion_dfci,
    couches = .couches_dfci(), quiet = TRUE)

  cert <- terra::values(mo$certifie) == 1
  expect_gt(sum(cert, na.rm = TRUE), 0)
  for (nm in .couches_dfci()) {
    vm <- as.numeric(terra::values(mo[[nm]]))[cert]
    vr <- as.numeric(terra::values(ref[[nm]]))[cert]
    expect_equal(vm, vr, info = nm)
  }
})

test_that("un halo trop court laisse le camion DFCI indetermine", {
  pre <- toy_preprocess()
  cfg <- foretaccess_config(general = list(
    tuile_m = 50, halo_initial_m = 10, halo_max_m = 10
  ))
  suppressWarnings(
    mo <- traiter_par_tuiles(pre, cfg, moteur = camion_dfci,
      couches = .couches_dfci(), quiet = TRUE)
  )
  expect_gt(sum(terra::values(mo$certifie) == 0), 0)
  expect_gt(mo$indetermine_ha, 0)
})
