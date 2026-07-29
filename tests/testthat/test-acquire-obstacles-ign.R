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
  # Hydrographie : ACCESSFOR lit `troncon_hydrographique` et ne garde que le
  # regime PERMANENT (annexe p.51). L'intermittent doit etre ecarte.
  if (grepl("troncon_hydrographique", typename)) {
    return(sf::st_sf(
      nom = c("ruisseau", "ravin sec"),
      persistance = c("Permanent", "Intermittent"),
      geometry = sf::st_sfc(
        seg(rbind(c(700200, 6600200), c(700800, 6600800))),
        seg(rbind(c(700200, 6600400), c(700800, 6600900))),
        crs = 2154
      )
    ))
  }
  if (grepl("batiment", typename)) {
    return(sf::st_sf(nature = "Indifferencie",
                     geometry = sf::st_sfc(poly(700300, 6600300), crs = 2154)))
  }
  if (grepl("troncon_de_route", typename)) {
    # ACCESSFOR selectionne sur `cpx_classement_administratif`, pas sur
    # `importance` -- d'ou une departementale d'importance 4 (retenue) et une
    # voie communale d'importance 5 (ecartee).
    return(sf::st_sf(
      cpx_classement_administratif = c("Departementale", NA),
      importance = c("4", "5"),
      position_par_rapport_au_sol = c(0L, 0L),
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
  # surface_hydro, voie_ferree, piste d'aerodrome, cimetiere, reservoir,
  # terrain de sport, rnn, rnr, rb : rien sur l'emprise.
  NULL
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

test_that("routes principales : classement ACCESSFOR par defaut, desactivable", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_wfs = obst_fetch)
    # Defaut : filtre sur cpx_classement_administratif (annexe p.52). La
    # departementale est retenue MALGRE son importance 4, que l'ancien filtre
    # `importance <= 3` ecartait.
    o <- acquire_obstacles_bdtopo(aoi_test(), cache_dir = "cdef")
    expect_true("routes_principales" %in% o$obstacle)

    # Desactivation complete : il faut neutraliser les DEUX criteres, le
    # classement etant desormais le principal.
    o_off <- acquire_obstacles_bdtopo(aoi_test(), cache_dir = "coff",
      classements_routes = NULL, routes_importance_max = NA_integer_)
    expect_false("routes_principales" %in% o_off$obstacle)

    # Repli `importance` : seulement quand la colonne de classement manque.
    sans_classement <- function(aoi, typename) {
      x <- obst_fetch(aoi, typename)
      if (!is.null(x) && "cpx_classement_administratif" %in% names(x)) {
        x$cpx_classement_administratif <- NULL
      }
      x
    }
    testthat::local_mocked_bindings(.fetch_wfs = sans_classement)
    o_imp <- acquire_obstacles_bdtopo(aoi_test(), cache_dir = "cimp",
      routes_importance_max = 3L)
    expect_false("routes_principales" %in% o_imp$obstacle) # importance 4 et 5
    o_imp5 <- acquire_obstacles_bdtopo(aoi_test(), cache_dir = "cimp5",
      routes_importance_max = 4L)
    expect_true("routes_principales" %in% o_imp5$obstacle)
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

test_that("conformite ACCESSFOR : les 8 couches BD TOPO de l'annexe sont couvertes", {
  # Annexe p.51-52 : TRANSPORT (route, voie ferree, piste d'aerodrome),
  # HYDROGRAPHIE (troncon + surface), BATI (batiment, cimetiere, reservoir,
  # terrain de sport). Cimetiere/reservoir/terrain de sport/piste d'aerodrome
  # manquaient jusqu'a la v1.27.1.
  couches <- foretaccess:::.OBSTACLES_BDTOPO
  expect_true(all(c("piste_d_aerodrome", "cimetiere", "reservoir",
    "terrain_de_sport") %in% names(couches)))
  expect_identical(unname(couches[["cours_d_eau"]]),
    "BDTOPO_V3:troncon_hydrographique")
})

test_that(".filtre_obstacle applique les filtres attributaires de l'annexe", {
  geom <- sf::st_sfc(sf::st_point(c(0, 0)), sf::st_point(c(1, 1)), crs = 2154)

  # Hydrographie : PERSISTANC = « Permanent » seulement. Un cours d'eau
  # intermittent, sec une partie de l'annee, n'est pas un obstacle.
  hydro <- sf::st_sf(persistance = c("Permanent", "Intermittent"), geometry = geom)
  expect_equal(nrow(foretaccess:::.filtre_obstacle(hydro, "cours_d_eau")), 1L)
  expect_equal(foretaccess:::.filtre_obstacle(hydro, "cours_d_eau")$persistance,
    "Permanent")

  # Voie ferree : NATURE != « sans objet ».
  vf <- sf::st_sf(nature = c("Voie ferree principale", "Sans objet"), geometry = geom)
  expect_equal(nrow(foretaccess:::.filtre_obstacle(vf, "voie_ferree")), 1L)

  # Position au sol : un TUNNEL (POS_SOL < 0) n'est pas un obstacle de surface.
  tun <- sf::st_sf(position_par_rapport_au_sol = c(0L, -1L), geometry = geom)
  expect_equal(nrow(foretaccess:::.filtre_obstacle(tun, "routes_principales")), 1L)

  # Couche sans les colonnes attendues : on ne filtre rien plutot que d'echouer.
  nu <- sf::st_sf(x = 1:2, geometry = geom)
  expect_equal(nrow(foretaccess:::.filtre_obstacle(nu, "cours_d_eau")), 2L)
})

test_that(".filtre_routes_principales suit le classement administratif ACCESSFOR", {
  geom <- sf::st_sfc(sf::st_point(c(0, 0)), sf::st_point(c(1, 1)),
    sf::st_point(c(2, 2)), crs = 2154)
  # Le classement et l'importance ne coincident PAS : sur l'AOI oracle,
  # importance <= 3 retenait 0 troncon la ou le classement en retient 11.
  rt <- sf::st_sf(
    cpx_classement_administratif = c("Departementale", NA, "Nationale"),
    importance = c(4L, 5L, 4L), geometry = geom)
  sel <- foretaccess:::.filtre_routes_principales(rt,
    foretaccess:::.CLASSEMENTS_ROUTES_ACCESSFOR, NA_integer_)
  expect_equal(nrow(sel), 2L)

  # Repli sur `importance` seulement si la colonne de classement manque.
  rt2 <- sf::st_sf(importance = c(2L, 5L, 4L), geometry = geom)
  expect_equal(nrow(foretaccess:::.filtre_routes_principales(rt2, NULL, 3L)), 1L)
})

test_that(".exclure_landes retire LA4/LA6 du masque foret (ACCESSFOR annexe p.50)", {
  geom <- sf::st_sfc(sf::st_point(c(0, 0)), sf::st_point(c(1, 1)),
    sf::st_point(c(2, 2)), crs = 2154)
  f <- sf::st_sf(code_tfv = c("FF1-00", "LA4", "LA6"), geometry = geom)
  expect_equal(nrow(suppressMessages(foretaccess:::.exclure_landes(f))), 1L)
  expect_equal(nrow(foretaccess:::.exclure_landes(f, exclure = FALSE)), 3L)
  # Sans colonne code_tfv, aucun filtrage possible : on renvoie tel quel.
  g <- sf::st_sf(x = 1:3, geometry = geom)
  expect_equal(nrow(foretaccess:::.exclure_landes(g)), 3L)
})

test_that("acquire_foret filtre les landes AUSSI a la relecture du cache", {
  # Un cache ecrit avant la v1.27.1 contient les landes et son nom ne porte pas
  # la trace du filtre : ne filtrer qu'a l'ecriture laisserait la correction
  # inoperante sur tout cache existant.
  withr::with_tempdir({
    d <- file.path("cache", "layers", "foret")
    dir.create(d, recursive = TRUE)
    geom <- sf::st_sfc(sf::st_point(c(0, 0)), sf::st_point(c(1, 1)), crs = 2154)
    sf::st_write(sf::st_sf(code_tfv = c("FF1-00", "LA4"), geometry = geom),
      file.path(d, "foret.gpkg"), quiet = TRUE)

    f <- suppressMessages(acquire_foret(aoi_test(), cache_dir = "cache"))
    expect_equal(nrow(f), 1L)
    expect_false("LA4" %in% f$code_tfv)
    # Opt-out : l'ancien comportement reste joignable.
    expect_equal(nrow(acquire_foret(aoi_test(), cache_dir = "cache",
      exclure_landes = FALSE)), 2L)
  })
})
