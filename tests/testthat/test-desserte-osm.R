# Desserte OSM comme source COMPLEMENTAIRE (spec 028). Overpass n'est pas
# joignable en CI : les tests mockent .fetch_osm et exercent le filtrage, la
# comparaison au corridor, et la regle « erreur relayee, jamais couche vide ».

osm_fixture <- function() {
  seg <- function(x0, y0, x1, y1) sf::st_linestring(rbind(c(x0, y0), c(x1, y1)))
  sf::st_sf(
    highway = c("track", "path", "tertiary", "service", "footway"),
    tracktype = c("grade3", NA, NA, NA, NA),
    geometry = sf::st_sfc(
      seg(0, 0, 100, 0),      # track,   dans le corridor BD TOPO
      seg(0, 500, 100, 500),  # path,    hors corridor -- doit etre EXCLU du type
      seg(0, 600, 100, 600),  # tertiary, hors corridor -- exclu aussi
      seg(0, 700, 100, 700),  # service, hors corridor -- retenu
      seg(0, 800, 100, 800),  # footway, exclu
      crs = 2154)
  )
}

test_that("acquire_desserte_osm ne retient que les types de desserte", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(
      .fetch_osm = function(...) list(osm_lines = osm_fixture()))
    aoi <- sf::st_as_sfc(sf::st_bbox(
      c(xmin = -50, ymin = -50, xmax = 200, ymax = 900), crs = 2154))
    d <- acquire_desserte_osm(aoi, cache_dir = "cache")
    expect_setequal(d$highway, c("track", "service"))
    expect_true(all(d$source == "osm"))
    # `path` est exclu par defaut : 14,09 km hors corridor sur l'AOI oracle,
    # mais majoritairement de la randonnee.
    expect_false("path" %in% d$highway)
    expect_false("tertiary" %in% d$highway)
    # Les attributs utiles suivent quand ils existent.
    expect_true("tracktype" %in% names(d))
  })
})

test_that("Overpass injoignable LEVE, ne rend jamais une couche vide", {
  # Un appelant confondrait sinon « le serveur refuse » et « il n'y a rien ici ».
  # C'est la confusion qui a masque l'absence de DFCI une journee entiere.
  withr::with_tempdir({
    testthat::local_mocked_bindings(
      .fetch_osm = function(...) stop("HTTP 504 Gateway Timeout"))
    aoi <- sf::st_as_sfc(sf::st_bbox(
      c(xmin = 0, ymin = 0, xmax = 100, ymax = 100), crs = 2154))
    expect_error(acquire_desserte_osm(aoi, cache_dir = "cache"), "504")
  })
})

test_that("une emprise sans ligne OSM rend une couche vide, pas une erreur", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_osm = function(...) list(osm_lines = NULL))
    aoi <- sf::st_as_sfc(sf::st_bbox(
      c(xmin = 0, ymin = 0, xmax = 100, ymax = 100), crs = 2154))
    d <- acquire_desserte_osm(aoi, cache_dir = "cache")
    expect_s3_class(d, "sf")
    expect_equal(nrow(d), 0L)
  })
})

test_that("comparer_desserte_osm mesure de part et d'autre du corridor", {
  seg <- function(x0, y0, x1, y1) sf::st_linestring(rbind(c(x0, y0), c(x1, y1)))
  # BD TOPO : une piste a y = 0. OSM : la meme voie (decalee de 5 m, donc DANS
  # le corridor de 15 m) plus un track a 500 m, hors corridor.
  bdt <- sf::st_sf(classe = "piste",
    geometry = sf::st_sfc(seg(0, 0, 100, 0), crs = 2154))
  osm <- sf::st_sf(source = "osm", highway = c("track", "track"),
    geometry = sf::st_sfc(seg(0, 5, 100, 5), seg(0, 500, 100, 500), crs = 2154))

  cmp <- comparer_desserte_osm(bdt, osm, corridor_m = 15)
  expect_s3_class(cmp, "foretaccess_osm_compare")
  expect_equal(unname(cmp$resume[["osm_km"]]), 0.2, tolerance = 1e-6)
  # Seul le troncon lointain sort du corridor.
  expect_equal(unname(cmp$resume[["osm_hors_km"]]), 0.1, tolerance = 1e-6)
  expect_equal(unname(cmp$resume[["osm_couvert_pct"]]), 50, tolerance = 1e-6)
  # Sens inverse : la piste BD TOPO est couverte par l'OSM voisin.
  expect_equal(unname(cmp$resume[["bdtopo_hors_km"]]), 0, tolerance = 1e-6)
})

test_that("comparer_desserte_osm tient sur des couches vides", {
  vide_l <- sf::st_sf(classe = character(0),
    geometry = sf::st_sfc(crs = sf::st_crs(2154)))
  vide_o <- sf::st_sf(source = character(0), highway = character(0),
    geometry = sf::st_sfc(crs = sf::st_crs(2154)))
  cmp <- comparer_desserte_osm(vide_l, vide_o)
  expect_equal(unname(cmp$resume[["osm_km"]]), 0)
  expect_true(is.na(cmp$resume[["osm_couvert_pct"]]))
})
