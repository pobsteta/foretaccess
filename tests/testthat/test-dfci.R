# Moteur camion DFCI (balayage radial, transcription de debusq_dfci) : zone de
# defendabilite, longueur de lance, pente pompier, sources CL_DFCI, tuilage
# (spec 006-dfci).

test_that("la zone de defendabilite est un disque radial borne autour du reseau DFCI", {
  pre <- pre_plan_dfci(pente = 0.05, n = 81)
  # Portee explicite : le jouet fait 405 m de cote, la portee reelle (440 m) le
  # couvrirait presque en entier et le test ne montrerait plus de bord.
  cfg <- foretaccess_config(dfci = list(distance_defense_max_m = 100))
  df <- camion_dfci(pre, cfg)

  codes <- as.numeric(terra::values(df$accessibilite))
  # Des cellules defendables (bandes 3..5) ET inaccessibles (1) coexistent.
  expect_gt(sum(codes %in% 3:5, na.rm = TRUE), 0)
  expect_gt(sum(codes == 1, na.rm = TRUE), 0)

  # La longueur de lance est bornee par la portee configuree.
  lance <- as.numeric(terra::values(df$longueur_lance))
  expect_lte(max(lance, na.rm = TRUE), cfg$dfci$distance_defense_max_m)
  # Une longueur de lance n'existe QUE sur les cellules defendables.
  expect_true(all(!is.na(lance) == (codes %in% 3:5)))
})

test_that("les bandes de defendabilite croissent avec la longueur de lance", {
  pre <- pre_plan_dfci(pente = 0.05, n = 121)
  df <- camion_dfci(pre, foretaccess_config(
    dfci = list(distance_defense_max_m = 440, classes_distance_m = c(0, 120, 280, 440))
  ))
  lance <- as.numeric(terra::values(df$longueur_lance))
  codes <- as.numeric(terra::values(df$accessibilite))
  # Chaque bande couvre bien son intervalle de lance.
  expect_true(all(lance[codes == 3] < 120, na.rm = TRUE))
  expect_true(all(lance[codes == 4] >= 120 & lance[codes == 4] < 280, na.rm = TRUE))
  expect_true(all(lance[codes == 5] >= 280 & lance[codes == 5] <= 440, na.rm = TRUE))
})

test_that("une longueur de lance plus grande etend la zone defendable", {
  pre <- pre_plan_dfci(pente = 0.05, n = 121)
  petite <- camion_dfci(pre, foretaccess_config(dfci = list(distance_defense_max_m = 50)))
  grande <- camion_dfci(pre, foretaccess_config(dfci = list(distance_defense_max_m = 200)))

  n_petite <- sum(terra::values(petite$accessibilite) %in% 3:5, na.rm = TRUE)
  n_grande <- sum(terra::values(grande$accessibilite) %in% 3:5, na.rm = TRUE)
  expect_gt(n_grande, n_petite)
})

test_that("le terrain au-dela de la pente pompier n'est pas defendable", {
  # Seuil explicite : c'est le MECANISME qu'on teste. Un plan raide (> seuil) est
  # infranchissable -- les rayons s'arretent, la zone defendable s'effondre.
  cfg <- foretaccess_config(dfci = list(pente_defense_max_pct = 40))
  doux  <- camion_dfci(pre_plan_dfci(pente = 0.05, n = 61), cfg)
  raide <- camion_dfci(pre_plan_dfci(pente = 0.60, n = 61), cfg)

  n_doux  <- sum(terra::values(doux$accessibilite) %in% 3:5, na.rm = TRUE)
  n_raide <- sum(terra::values(raide$accessibilite) %in% 3:5, na.rm = TRUE)
  expect_gt(n_doux, n_raide)
  # Sur le plan raide, la foret est non_defendable_pente (code 2), pas defendable.
  expect_gt(sum(terra::values(raide$accessibilite) == 2, na.rm = TRUE), 0)
})

test_that("les sources viennent du flag CL_DFCI, orthogonal aux classes", {
  # Une desserte piste seule, sans flag DFCI : aucune source.
  pre <- pre_plan_dfci(pente = 0.05, n = 41, classe = "piste")
  expect_error(camion_dfci(pre), regexp = "Aucune desserte-source DFCI")

  # Une route portant le flag CL_DFCI EST une source, alors que la classe route
  # n'est pas "dfci" : le flag prime (test au niveau preprocess).
  mnt <- mnt_plan(pente = 0.05, n = 41, res = 5)
  centre <- 41 * 5 / 2
  route <- sf::st_sf(
    classe = "route", dfci = 1L,
    geometry = sf::st_sfc(sf::st_linestring(rbind(
      c(centre - 20, centre), c(centre + 20, centre))), crs = 2154)
  )
  pre2 <- preprocess(mnt = mnt, desserte = route, foret = foret_pleine(mnt))
  expect_gt(sum(terra::values(pre2$dfci_source_mask) == 1, na.rm = TRUE), 0)
  df <- camion_dfci(pre2)
  expect_gt(sum(terra::values(df$accessibilite) %in% 3:5, na.rm = TRUE), 0)
})

test_that("le tableau recapitulatif conserve la surface", {
  df <- camion_dfci(toy_preprocess())
  expect_equal(sum(df$recap$cellules), terra::ncell(toy_preprocess()$mnt))
  expect_true("indetermine" %in% df$recap$classe)
  expect_true(all(c("inaccessible", "non_defendable_pente", "defendable_c1",
                    "defendable_c2", "defendable_c3", "hors_foret") %in% df$recap$classe))
})

test_that("une desserte-source absente leve une erreur ciblee", {
  pre <- toy_preprocess()
  pre$dfci_source_mask <- terra::rast(pre$mnt)
  terra::values(pre$dfci_source_mask) <- 0
  expect_error(camion_dfci(pre), regexp = "Aucune desserte-source DFCI")
})

test_that("le camion DFCI ecrit ses couches en COG relisibles", {
  withr::with_tempdir({
    df <- camion_dfci(toy_preprocess(), write_dir = "sortie")
    expect_named(df$fichiers, .couches_dfci(), ignore.order = TRUE)
    expect_true(all(file.exists(unlist(df$fichiers))))
    relu <- terra::rast(file.path("sortie", "longueur_lance.tif"))
    expect_equal(terra::values(relu), terra::values(df$longueur_lance),
      tolerance = 1e-5)
  })
})

test_that("print.foretaccess_dfci resume le moteur", {
  expect_message(print(camion_dfci(toy_preprocess())), regexp = "camion DFCI")
})

# --- Tuilage : portee bornee par lmax, donc certifiable par un halo suffisant ---

test_that("le camion DFCI tuile egale le mono-bloc sur les cellules certifiees", {
  # Le reseau DFCI est clairseme : une tuile dont le halo n'atteint pas la ligne
  # DFCI reste indeterminee. La garantie porte sur les cellules *certifiees*.
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
