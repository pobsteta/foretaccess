# acquire_desserte_lidar() (specs 020/023, NDP 1). dessertR est une dependance
# OPTIONNELLE hors CRAN, absente en CI : les tests exercent le REPLI NDP 0
# (desserte inchangee + colonnes LiDAR a NA) et les garde-fous. Le chemin dessertR
# reel est valide par le banc Phase B (data-raw/phaseB_dessertr.R), hors CI.

desserte_lignes_test <- function() {
  sf::st_sf(
    classe = c("route", "piste"),
    geometry = sf::st_sfc(
      sf::st_linestring(rbind(c(0, 0), c(100, 0))),
      sf::st_linestring(rbind(c(0, 50), c(100, 80))),
      crs = 2154
    )
  )
}

mnt_test <- function() {
  r <- terra::rast(
    nrows = 20, ncols = 20, xmin = 0, xmax = 100, ymin = 0, ymax = 100,
    crs = "EPSG:2154"
  )
  terra::values(r) <- 100
  names(r) <- "altitude"
  r
}

test_that("sans dessertR : repli NDP 0 (desserte inchangee, colonnes NA)", {
  # Repli force par mock : deterministe, que dessertR soit installe ou non.
  testthat::local_mocked_bindings(.dessertr_dispo = function() FALSE)
  des <- desserte_lignes_test()
  expect_message(
    out <- acquire_desserte_lidar(des, las_source = "peu_importe", mnt = mnt_test()),
    "NDP 0"
  )
  expect_s3_class(out, "sf")
  # Geometrie et attributs d'origine preserves.
  expect_equal(nrow(out), nrow(des))
  expect_true(all(c("classe") %in% names(out)))
  expect_equal(sf::st_geometry(out), sf::st_geometry(des))
  # Colonnes du CONTRAT presentes, a NA.
  expect_true(all(c("largeur_carrossable_m", "largeur_plateforme_m", "pente_pct",
                    "etat_classe", "score_lidar") %in% names(out)))
  expect_true(all(is.na(out$largeur_carrossable_m)))
  expect_true(all(is.na(out$etat_classe)))
  # Colonnes BONUS (dessertR) egalement presentes, a NA, meme en NDP 0.
  expect_true(all(c("etat_dessertr", "devers", "fosses", "rayon_courbure_p05",
                    "apte_grumier", "motif_inaptitude") %in% names(out)))
  expect_true(all(is.na(out$apte_grumier)))
  expect_true(all(is.na(out$fosses)))
  expect_identical(attr(out, "ndp"), 0L)
  expect_identical(attr(out, "moteur"), "ndp0")
})

test_that(".moteur_lidar : dessertR ou NDP 0 (ALSroads retire, Phase C)", {
  # "auto" et "dessertr" convergent : un seul moteur depuis la v1.27.0.
  testthat::local_mocked_bindings(.dessertr_dispo = function() TRUE)
  expect_identical(foretaccess:::.moteur_lidar("auto"), "dessertr")
  expect_identical(foretaccess:::.moteur_lidar("dessertr"), "dessertr")
  # Sans dessertR : NDP 0 dans les deux cas.
  testthat::local_mocked_bindings(.dessertr_dispo = function() FALSE)
  expect_identical(foretaccess:::.moteur_lidar("auto"), "ndp0")
  expect_identical(foretaccess:::.moteur_lidar("dessertr"), "ndp0")
  # "alsroads" n'est plus une valeur acceptee (Phase C, ADR-009).
  expect_error(foretaccess:::.moteur_lidar("alsroads"), "arg")
})

test_that("la sortie NDP 0 est consommable par places_depot (largeur presente mais NA)", {
  # Le champ largeur_carrossable_m existe : places_depot pourra s'en servir des
  # que le LiDAR le renseignera (ici NA -> critere largeur indeterminable, comme
  # une BD TOPO sans largeur, cf. places_depot).
  testthat::local_mocked_bindings(.dessertr_dispo = function() FALSE)
  des <- desserte_lignes_test()
  out <- suppressMessages(acquire_desserte_lidar(des, "x", mnt_test()))
  expect_true("largeur_carrossable_m" %in% names(out))
  expect_type(out$largeur_carrossable_m, "double")
})

test_that("une desserte vide ou non lineaire est refusee (avant tout repli)", {
  expect_error(
    acquire_desserte_lidar(desserte_lignes_test()[0, ], "x", mnt_test()),
    "vide"
  )
  pts <- sf::st_sf(
    classe = "route",
    geometry = sf::st_sfc(sf::st_point(c(1, 1)), crs = 2154)
  )
  expect_error(acquire_desserte_lidar(pts, "x", mnt_test()), "couche de lignes")
})

test_that(".dessertr_dispo est FALSE quand le paquet manque", {
  # Documente l'invariant de CI : sans dessertR, on est en NDP 0.
  if (requireNamespace("dessertR", quietly = TRUE)) {
    skip("dessertR installe : NDP 1 disponible")
  }
  expect_false(foretaccess:::.dessertr_dispo())
})

test_that(".troncon_linestring ramene une MULTILINESTRING a une LINESTRING unique", {
  # measure_road ERREUR sur une MULTILINESTRING (BD TOPO troncon_de_route) : c'est
  # la cause du 0/N sur une desserte reelle. Ce helper la ramene a une LINESTRING.
  ls <- function(m) sf::st_linestring(m)
  # Parties CONTIGUES -> fusionnees en une seule LINESTRING.
  contigu <- sf::st_sf(
    classe = "piste",
    geometry = sf::st_sfc(sf::st_multilinestring(list(
      rbind(c(0, 0), c(10, 0)), rbind(c(10, 0), c(20, 0))
    )), crs = 2154)
  )
  r <- foretaccess:::.troncon_linestring(contigu)
  expect_equal(as.character(sf::st_geometry_type(r)), "LINESTRING")
  expect_equal(as.numeric(sf::st_length(r)), 20)

  # Parties DISJOINTES -> on garde la plus longue.
  disjoint <- sf::st_sf(
    classe = "piste",
    geometry = sf::st_sfc(sf::st_multilinestring(list(
      rbind(c(0, 0), c(5, 0)), rbind(c(0, 50), c(0, 90))
    )), crs = 2154)
  )
  r2 <- foretaccess:::.troncon_linestring(disjoint)
  expect_equal(as.character(sf::st_geometry_type(r2)), "LINESTRING")
  expect_equal(as.numeric(sf::st_length(r2)), 40) # la branche de 40 m

  # Une LINESTRING passe telle quelle ; un point -> NULL (inexploitable).
  lin <- sf::st_sf(classe = "route",
                   geometry = sf::st_sfc(ls(rbind(c(0, 0), c(30, 0))), crs = 2154))
  expect_equal(as.character(sf::st_geometry_type(
    foretaccess:::.troncon_linestring(lin))), "LINESTRING")
  pt <- sf::st_sf(classe = "route",
                  geometry = sf::st_sfc(sf::st_point(c(1, 1)), crs = 2154))
  expect_null(foretaccess:::.troncon_linestring(pt))
})

test_that(".troncons_couverts n'attaque QUE les troncons sous une dalle (anti-segfault)", {
  # Sur une desserte de projet (806 km) pour quelques dalles, mesurer les milliers
  # de troncons hors couverture est au mieux du gachis, au pire un crash du moteur.
  # Ce filtre les ecarte AVANT l'appel. Une dalle = carre [0,100] x [0,100].
  couv <- sf::st_sfc(sf::st_polygon(list(rbind(
    c(0, 0), c(100, 0), c(100, 100), c(0, 100), c(0, 0)
  ))), crs = 2154)
  geoms <- sf::st_sfc(
    sf::st_linestring(rbind(c(10, 10), c(90, 90))),   # dans la dalle
    sf::st_linestring(rbind(c(50, 50), c(150, 150))), # a cheval (touche)
    sf::st_linestring(rbind(c(200, 200), c(300, 300))), # HORS couverture
    crs = 2154
  )
  cvt <- foretaccess:::.troncons_couverts(geoms, couv)
  expect_equal(cvt, c(TRUE, TRUE, FALSE)) # seul le 3e est ecarte
  # Sans couverture connue (NULL) : on n'exclut rien (repli conservateur).
  expect_true(all(foretaccess:::.troncons_couverts(geoms, NULL)))
})

test_that("la pente en long d'une geometrie est calculee sur le MNT", {
  # Helper interne : sur un MNT plat, pente nulle ; verifie le calcul.
  g <- sf::st_geometry(sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(10, 10), c(90, 10))), crs = 2154
  )))
  p <- foretaccess:::.pente_en_long_geom(g[1], mnt_test())
  expect_equal(p, 0)
})

test_that(".avertir_mnt_grossier previent au-dela de 1,5 m, se tait en deca", {
  # Le rattrapage automatique (derivation d'un MNT 1 m depuis les points sol) est
  # parti avec ALSroads en Phase C : sans ce garde, un MNT a 5 m rend des largeurs
  # NA en SILENCE, indiscernables d'un "hors couverture" dans le bilan.
  expect_warning(foretaccess:::.avertir_mnt_grossier(5), "1 m ou plus")
  expect_true(suppressWarnings(foretaccess:::.avertir_mnt_grossier(5)))
  # Marge : le LiDAR HD (0,5 m) et RGE ALTI (1 m) passent, y compris apres une
  # reprojection qui rend res() legerement > 1.
  expect_silent(foretaccess:::.avertir_mnt_grossier(0.5))
  expect_silent(foretaccess:::.avertir_mnt_grossier(1))
  expect_silent(foretaccess:::.avertir_mnt_grossier(1.0000001))
  expect_false(foretaccess:::.avertir_mnt_grossier(1))
  # Resolution indeterminable : on ne crie pas dans le vide.
  expect_silent(foretaccess:::.avertir_mnt_grossier(NA_real_))
})
