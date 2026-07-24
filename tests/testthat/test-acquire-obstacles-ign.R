# Obstacles conformes ACCESSFOR (BD TOPO + Patrinat, spec 022 volet B). Acquisition
# reseau mockee (local_mocked_bindings sur .fetch_wfs) : on verifie l'assemblage,
# le tampon des lignes, le filtrage du parc national sur la reserve integrale, et
# le cas vide -- sans reseau.

# Retour WFS simule, dispatche par typename.
obst_fetch <- function(aoi, typename) {
  seg <- function(m) sf::st_linestring(m)
  poly <- function(x0, y0, s = 100) sf::st_polygon(list(rbind(
    c(x0, y0), c(x0 + s, y0), c(x0 + s, y0 + s), c(x0, y0 + s), c(x0, y0)
  )))
  if (grepl("cours_d_eau", typename)) {
    return(sf::st_sf(nom = "ruisseau", geometry = sf::st_sfc(
      seg(rbind(c(700200, 6600200), c(700800, 6600800))), crs = 2154
    )))
  }
  if (grepl("batiment", typename)) {
    return(sf::st_sf(nature = "Indifferencie",
                     geometry = sf::st_sfc(poly(700300, 6600300), crs = 2154)))
  }
  if (grepl("troncon_de_route", typename)) {
    return(sf::st_sf(
      importance = c("2", "5"), # une principale (<=3), une locale
      geometry = sf::st_sfc(
        seg(rbind(c(700100, 6600500), c(700900, 6600500))),
        seg(rbind(c(700100, 6600700), c(700900, 6600700))),
        crs = 2154
      )
    ))
  }
  if (grepl("patrinat_apb", typename)) {
    return(sf::st_sf(nom_site = "biotope",
                     geometry = sf::st_sfc(poly(700500, 6600100, 80), crs = 2154)))
  }
  if (grepl("parc_national", typename)) {
    return(sf::st_sf(
      zone = c("Réserve intégrale", "Aire d'adhésion"),
      geometry = sf::st_sfc(poly(700100, 6600100, 60), poly(700000, 6600900, 60),
                            crs = 2154)
    ))
  }
  NULL # surface_hydro, voie_ferree, rnn, rnr, rb : rien sur l'emprise
}

test_that("acquire_obstacles_bdtopo assemble BD TOPO + Patrinat en polygones", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_wfs = obst_fetch)
    o <- acquire_obstacles_bdtopo(aoi_test(), cache_dir = "cache", tampon_m = 6)
    expect_s3_class(o, "sf")
    # Tout en (MULTI)POLYGON, y compris les lignes tamponnees (cours d'eau, route).
    expect_true(all(grepl("POLYGON", as.character(sf::st_geometry_type(o)))))
    # Couches attendues : cours d'eau, batiment, routes principales, apb, PN integrale.
    expect_true(any(grepl("cours_d_eau", o$obstacle)))
    expect_true(any(grepl("batiment", o$obstacle)))
    expect_true(any(grepl("routes_principales", o$obstacle)))
    expect_true(any(grepl("apb", o$obstacle)))
    expect_true("pn_reserve_integrale" %in% o$obstacle)
    # Cache ecrit.
    expect_true(file.exists(file.path("cache", "layers", "obstacles_bdtopo",
                                      "obstacles_bdtopo.gpkg")))
  })
})

test_that("le parc national n'entre QUE par sa reserve integrale (pas le parc entier)", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_wfs = obst_fetch)
    o <- acquire_obstacles_bdtopo(aoi_test(), cache_dir = "cache", zonages = TRUE)
    pn <- o[o$obstacle == "pn_reserve_integrale", ]
    expect_equal(nrow(pn), 1L)
    # L'aire d'adhesion (60x60 = 0,36 ha) NE doit PAS etre incluse : seule la
    # reserve integrale (60x60) l'est -> aire ~ 0,36 ha, pas 0,72.
    expect_lt(as.numeric(sf::st_area(pn)) / 1e4, 0.5)
  })
})

test_that("zonages = FALSE n'ajoute aucune exclusion reglementaire", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_wfs = obst_fetch)
    o <- acquire_obstacles_bdtopo(aoi_test(), cache_dir = "cache", zonages = FALSE)
    expect_false(any(grepl("apb|pn_reserve|rnn|rnr|patrinat", o$obstacle)))
    expect_true(any(grepl("cours_d_eau", o$obstacle))) # obstacles BD TOPO restent
  })
})

test_that("routes_importance_max filtre les grands axes ; NA les desactive", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_wfs = obst_fetch)
    # importance <= 3 : seule la route d'importance 2 devient obstacle.
    o3 <- acquire_obstacles_bdtopo(aoi_test(), cache_dir = "c3", routes_importance_max = 3L)
    expect_true("routes_principales" %in% o3$obstacle)
    o_na <- acquire_obstacles_bdtopo(aoi_test(), cache_dir = "cna", routes_importance_max = NA)
    expect_false("routes_principales" %in% o_na$obstacle)
  })
})

test_that("une emprise sans obstacle rend un sf a zero ligne (pas d'erreur)", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_wfs = function(aoi, typename) NULL)
    o <- acquire_obstacles_bdtopo(aoi_test(), cache_dir = "cache")
    expect_s3_class(o, "sf")
    expect_equal(nrow(o), 0L)
  })
})
