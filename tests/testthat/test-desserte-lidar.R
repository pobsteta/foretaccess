# acquire_desserte_lidar() (spec 020, NDP 1). ALSroads/lidR sont des dependances
# OPTIONNELLES hors CRAN, absentes en CI : les tests exercent le REPLI NDP 0
# (desserte inchangee + colonnes LiDAR a NA) et les garde-fous. Le chemin ALSroads
# reel (calibre Quebec) est valide en Phase B sur donnee francaise, hors CI.

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

test_that("sans lidR/ALSroads : repli NDP 0 (desserte inchangee, colonnes NA)", {
  # Repli force par mock : deterministe, que lidR/ALSroads soient installes ou non.
  testthat::local_mocked_bindings(.alsroads_dispo = function() FALSE)
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
  # Colonnes LiDAR presentes, a NA (noms verifies sur la sortie reelle d'ALSroads).
  expect_true(all(c("largeur_carrossable_m", "largeur_plateforme_m", "pente_pct",
                    "etat_classe", "score_lidar") %in% names(out)))
  expect_true(all(is.na(out$largeur_carrossable_m)))
  expect_true(all(is.na(out$etat_classe)))
  expect_identical(attr(out, "ndp"), 0L)
})

test_that("la sortie NDP 0 est consommable par places_depot (largeur presente mais NA)", {
  # Le champ largeur_carrossable_m existe : places_depot pourra s'en servir des
  # que le LiDAR le renseignera (ici NA -> critere largeur indeterminable, comme
  # une BD TOPO sans largeur, cf. places_depot).
  testthat::local_mocked_bindings(.alsroads_dispo = function() FALSE)
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

test_that(".alsroads_dispo est FALSE quand les paquets manquent", {
  # Documente l'invariant de CI : sans lidR+ALSroads, on est en NDP 0.
  if (requireNamespace("lidR", quietly = TRUE) &&
      requireNamespace("ALSroads", quietly = TRUE)) {
    skip("lidR + ALSroads installes : NDP 1 disponible")
  }
  expect_false(foretaccess:::.alsroads_dispo())
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

test_that("la pente en long d'une geometrie est calculee sur le MNT", {
  # Helper interne : sur un MNT plat, pente nulle ; verifie le calcul.
  g <- sf::st_geometry(sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(10, 10), c(90, 10))), crs = 2154
  )))
  p <- foretaccess:::.pente_en_long_geom(g[1], mnt_test())
  expect_equal(p, 0)
})
