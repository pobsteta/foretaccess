# Acquisition IGN (mockee, hors-ligne) : mapping classe, reproj/clip, cache
# (spec 010 §4, CA-A.2/A.6).

test_that("le mapping de classe derive la classe depuis la nature BD TOPO", {
  d <- roads_fixture()
  cl <- .mapper_classe_desserte(d) # defaut accessfor depuis la v1.28.0
  # Table publiee (annexe p.51) : « Route a 1 chaussee » est du RESEAU PUBLIC,
  # pas de la route forestiere -- c'est l'ecart majeur de la spec 024. Le defaut
  # anterieur ("clsvac") en faisait une `route`.
  expect_equal(cl, c("reseau_public", "piste"))
  expect_equal(.mapper_classe_desserte(d, "clsvac"), c("route", "piste"))
})

# Jeu couvrant les cas discriminants entre les deux classifications.
roads_clsvac_fixture <- function() {
  seg <- function(o) sf::st_linestring(rbind(c(700200 + o, 6600200), c(700800 + o, 6600800)))
  sf::st_sf(
    nature = c("Chemin", "Sentier", "Route empierrée", "Route à 1 chaussée",
               "Type autoroutier"),
    importance = c(5L, 6L, 5L, 4L, 2L),
    geometry = sf::st_sfc(seg(0), seg(10), seg(20), seg(30), seg(40), crs = 2154)
  )
}

test_that("classification CL_SVAC : la route empierree devient route (terminus), pas piste", {
  cl <- .mapper_classe_desserte(roads_clsvac_fixture(), "clsvac")
  # Chemin/Sentier -> piste ; Route empierree + Route a 1 chaussee -> route ;
  # Type autoroutier (importance 2) -> reseau public (barriere).
  expect_equal(cl, c("piste", "piste", "route", "route", "reseau_public"))
})

test_that("classification heuristique : retro-compat bit-pour-bit (empierree -> piste)", {
  cl <- .mapper_classe_desserte(roads_clsvac_fixture(), "heuristique")
  # L'ancien mapping range la Route empierree en PISTE (le bug corrige par clsvac).
  expect_equal(cl, c("piste", "piste", "piste", "route", "route"))
})

test_that("acquire_desserte reprojette, decoupe et pose le champ classe", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_wfs = function(aoi, typename) roads_fixture())
    d <- acquire_desserte(aoi_test(), cache_dir = "cache")

    expect_s3_class(d, "sf")
    expect_true("classe" %in% names(d))
    # `hors_desserte` (CL_SVAC = 0) est RETIRE de la sortie : la couche
    # Sylvaccess d'ACCESSFOR ne contient que les classes 1/2/3.
    expect_true(all(d$classe %in% .classes_desserte()))
    expect_false("hors_desserte" %in% d$classe)
    expect_equal(sf::st_crs(d), sf::st_crs(2154))
    # Cache ecrit.
    expect_true(file.exists(file.path("cache", "layers", "desserte", "desserte.gpkg")))
  })
})

test_that("acquire_mnt ecrit un raster en cache et est idempotent (CA-A.6)", {
  withr::with_tempdir({
    appels <- 0L
    testthat::local_mocked_bindings(.fetch_wms_raster = function(aoi, layer, res, crs, filename) {
      appels <<- appels + 1L
      mnt_fixture_writer(aoi, layer, res, crs, filename)
    })
    p1 <- acquire_mnt(aoi_test(), res_m = 50, cache_dir = "cache")
    expect_true(file.exists(p1))
    expect_equal(appels, 1L)

    # 2e appel : servi du cache, aucun nouvel appel reseau.
    p2 <- acquire_mnt(aoi_test(), res_m = 50, cache_dir = "cache")
    expect_equal(p2, p1)
    expect_equal(appels, 1L)

    # overwrite force un nouvel appel.
    acquire_mnt(aoi_test(), res_m = 50, cache_dir = "cache", overwrite = TRUE)
    expect_equal(appels, 2L)
  })
})

test_that("acquire_mnt bascule sur une couche de repli si la principale est vide", {
  withr::with_tempdir({
    principale <- "IGNF_LIDAR-HD_MNT_ELEVATION.ELEVATIONGRIDCOVERAGE.LAMB93"
    couches <- character(0)
    testthat::local_mocked_bindings(.fetch_wms_raster = function(aoi, layer, res, crs, filename) {
      couches <<- c(couches, layer)
      r <- terra::rast(terra::ext(terra::vect(aoi)), resolution = res, crs = paste0("EPSG:", crs))
      # La couche principale (LIDAR HD) n'a pas de donnee ici -> tout NA.
      terra::values(r) <- if (identical(layer, principale)) NA_real_ else seq_len(terra::ncell(r))
      terra::writeRaster(r, filename, overwrite = TRUE)
      r
    })
    p <- acquire_mnt(aoi_test(), res_m = 50, cache_dir = "cache")
    expect_true(file.exists(p))
    # La principale a ete tentee puis abandonnee au profit du 1er repli.
    expect_equal(couches[1], principale)
    expect_gte(length(couches), 2L)
    # Le MNT rendu est celui du repli (valeurs finies).
    expect_true(any(is.finite(terra::values(terra::rast(p), mat = FALSE))))
  })
})

test_that("acquire_mnt telecharge le LIDAR HD fin puis l'agrege a res_m", {
  withr::with_tempdir({
    res_vues <- numeric(0)
    testthat::local_mocked_bindings(.fetch_wms_raster = function(aoi, layer, res, crs, filename) {
      res_vues <<- c(res_vues, res)
      mnt_fixture_writer(aoi, layer, res, crs, filename)
    })
    p <- acquire_mnt(aoi_test(), res_m = 5, res_lidar_m = 1, cache_dir = "cache")

    # La couche primaire est telechargee a la resolution FINE (1 m), pas 5 m.
    expect_equal(res_vues[1], 1)
    # Produit fin intermediaire conserve, a ~1 m.
    p_fin <- file.path("cache", "layers", "mnt", "lidar_mnt_aoi_buffer.tif")
    expect_true(file.exists(p_fin))
    expect_equal(terra::res(terra::rast(p_fin)), c(1, 1))
    # Base de calcul agregee a res_m = 5 m.
    expect_true(file.exists(p))
    expect_equal(terra::res(terra::rast(p)), c(5, 5))
  })
})

test_that("acquire_mnt : res_lidar_m >= res_m telecharge en direct (pas d'agregation)", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_wms_raster = mnt_fixture_writer)
    p <- acquire_mnt(aoi_test(), res_m = 5, res_lidar_m = 5, cache_dir = "cache")
    expect_true(file.exists(p))
    expect_equal(terra::res(terra::rast(p)), c(5, 5))
    # Pas de produit fin ecrit quand l'agregation est desactivee.
    expect_false(file.exists(file.path("cache", "layers", "mnt", "lidar_mnt_aoi_buffer.tif")))
  })
})

test_that("acquire_foret et acquire_cadastre renvoient des polygones decoupes", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_wfs = function(aoi, typename) polys_fixture())
    f <- acquire_foret(aoi_test(), cache_dir = "cache")
    p <- acquire_cadastre(aoi_test(), cache_dir = "cache")
    expect_s3_class(f, "sf")
    expect_s3_class(p, "sf")
    expect_gt(nrow(f), 0)
    expect_equal(sf::st_crs(f), sf::st_crs(2154))
  })
})

test_that("une dependance absente leve un message d'installation cible (CA-A.5)", {
  expect_error(.require_pkg("paquet.qui.n.existe.pas"), regexp = "install.packages")
})

test_that("classification accessfor : table publiee de l'annexe p.51", {
  # `nature` SEUL decide -- `importance` n'entre pas dans la table publiee.
  # Les importances ci-dessous sont celles observees sur l'AOI oracle : elles
  # feraient diverger `clsvac`, qui pilote reseau_public sur importance <= 3.
  x <- data.frame(
    nature = c("Route à 2 chaussées", "Route à 1 chaussée",
               "Route empierrée", "Chemin", "Sentier", "Rond-point"),
    importance = c(4L, 5L, 5L, 5L, 6L, 5L)
  )
  cl <- foretaccess:::.mapper_classe_desserte(x, "accessfor")
  expect_identical(cl, c("reseau_public", "reseau_public", "route", "piste",
                         "hors_desserte", "hors_desserte"))

  # `clsvac` sur les MEMES donnees : aucun reseau_public (importance 4-6), et le
  # sentier devient une piste. C'est l'ecart de 42 % de la spec 024.
  expect_identical(foretaccess:::.mapper_classe_desserte(x, "clsvac"),
    c("route", "route", "route", "piste", "piste", "route"))
})

test_that("accessfor : appariement sur la modalite ENTIERE, pas par mots-cles", {
  # « Route a 1 chaussee » ne doit pas etre attrapee par un motif « route » large,
  # ni « Chemin rural » confondu avec « Chemin ».
  x <- data.frame(nature = c("Route à 1 chaussée", "Chemin", "Escalier"))
  cl <- foretaccess:::.mapper_classe_desserte(x, "accessfor")
  expect_identical(cl, c("reseau_public", "piste", "hors_desserte"))
})

test_that("accessfor : la route forestiere nommee passe en route (couche liee)", {
  x <- data.frame(
    nature = c("Chemin", "Chemin", "Sentier"),
    liens_vers_route_nommee = c("ROUTNOMM01", NA, "ROUTNOMM01")
  )
  # Sans la couche liee : classement par `nature` seul.
  expect_identical(foretaccess:::.mapper_classe_desserte(x, "accessfor"),
    c("piste", "piste", "hors_desserte"))
  # Avec : le troncon lie a une route forestiere nommee devient `route`, et le
  # reclassement l'emporte meme sur un `nature` qui l'excluait.
  expect_identical(
    foretaccess:::.mapper_classe_desserte(x, "accessfor", "ROUTNOMM01"),
    c("route", "piste", "route"))
})

test_that("accessfor : retro-compat, clsvac et heuristique sont intactes", {
  x <- data.frame(nature = c("Chemin", "Sentier", "Route empierrée",
                             "Route à 1 chaussée"),
                  importance = c(5L, 6L, 5L, 2L))
  expect_identical(foretaccess:::.mapper_classe_desserte(x, "heuristique"),
    c("piste", "piste", "piste", "route"))
  expect_identical(foretaccess:::.mapper_classe_desserte(x, "clsvac"),
    c("piste", "piste", "route", "reseau_public"))
})

test_that("acquire_desserte retire les troncons hors desserte, sauf demande", {
  fixture <- function(aoi, typename) {
    if (grepl("route_numerotee", typename)) return(NULL) # pas de couche liee
    seg <- function(o) sf::st_linestring(rbind(
      c(700200 + o, 6600200), c(700800 + o, 6600800)))
    sf::st_sf(
      nature = c("Chemin", "Sentier", "Route empierrée"),
      geometry = sf::st_sfc(seg(0), seg(10), seg(20), crs = 2154)
    )
  }
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_wfs = fixture)
    d <- suppressMessages(acquire_desserte(aoi_test(), cache_dir = "c1"))
    expect_equal(nrow(d), 2L) # le Sentier est parti
    expect_setequal(d$classe, c("piste", "route"))

    # Inspection : on peut les garder pour voir ce qui a ete ecarte.
    dg <- acquire_desserte(aoi_test(), cache_dir = "c2",
      garder_hors_desserte = TRUE)
    expect_equal(nrow(dg), 3L)
    expect_true("hors_desserte" %in% dg$classe)
  })
})

test_that(".cleabs_routes_forestieres : couche absente ou vide -> vecteur vide", {
  testthat::local_mocked_bindings(.fetch_wfs = function(...) NULL)
  expect_identical(foretaccess:::.cleabs_routes_forestieres(aoi_test()), character(0))

  testthat::local_mocked_bindings(.fetch_wfs = function(...) sf::st_sf(
    cleabs = c("R1", "R2", "R3"),
    type_de_route = c("Route forestière nommée", "Départementale", NA),
    geometry = sf::st_sfc(sf::st_point(c(0, 0)), sf::st_point(c(1, 1)),
      sf::st_point(c(2, 2)), crs = 2154)))
  expect_identical(foretaccess:::.cleabs_routes_forestieres(aoi_test()), "R1")
})
