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

test_that("comparer_desserte_osm rend la geometrie hors corridor", {
  seg <- function(x0, y0, x1, y1) sf::st_linestring(rbind(c(x0, y0), c(x1, y1)))
  bdt <- sf::st_sf(classe = "piste",
    geometry = sf::st_sfc(seg(0, 0, 100, 0), crs = 2154))
  osm <- sf::st_sf(source = "osm", highway = c("track", "track"),
    tracktype = c(NA, "grade3"),
    geometry = sf::st_sfc(seg(0, 5, 100, 5), seg(0, 500, 100, 500), crs = 2154))

  cmp <- comparer_desserte_osm(bdt, osm, corridor_m = 15)
  hc <- cmp$osm_hors_corridor
  expect_s3_class(hc, "sf")
  expect_equal(nrow(hc), 1L)
  # Le troncon lointain, entier : 100 m -- exactement l'osm_hors_km de la table.
  expect_equal(hc$hors_m, 100, tolerance = 1e-6)
  expect_equal(sum(as.numeric(sf::st_length(hc))), 100, tolerance = 1e-6)
  expect_equal(unname(cmp$resume[["osm_hors_km"]]),
               sum(hc$hors_m) / 1000, tolerance = 1e-6)
  # Attributs d'origine conserves, colonnes de travail exclues.
  expect_equal(hc$highway, "track")
  expect_equal(hc$source, "osm")
  expect_equal(hc$tracktype, "grade3")
  expect_false("long_m" %in% names(hc))
  expect_equal(sf::st_crs(hc), sf::st_crs(2154))
  # La piste BD TOPO est couverte par l'OSM voisin : couche vide, pas NULL.
  expect_s3_class(cmp$bdtopo_hors_corridor, "sf")
  expect_equal(nrow(cmp$bdtopo_hors_corridor), 0L)
  expect_equal(sf::st_crs(cmp$bdtopo_hors_corridor), sf::st_crs(2154))
})

test_that("un troncon qui traverse le corridor est CLIPPE, type homogene", {
  # Sans clip, on afficherait comme « absent de la BD TOPO » un lineaire qui y
  # est. Et sans le cast, la couche porterait LINESTRING *et* MULTILINESTRING.
  seg <- function(x0, y0, x1, y1) sf::st_linestring(rbind(c(x0, y0), c(x1, y1)))
  bdt <- sf::st_sf(classe = "piste",
    geometry = sf::st_sfc(seg(0, 0, 100, 0), crs = 2154))
  osm <- sf::st_sf(source = "osm", highway = c("track", "track"),
    geometry = sf::st_sfc(
      seg(50, -100, 50, 100),   # perpendiculaire : coupe en deux par le corridor
      seg(0, 500, 100, 500),    # lointain : reste entier
      crs = 2154))

  cmp <- comparer_desserte_osm(bdt, osm, corridor_m = 15)
  hc <- cmp$osm_hors_corridor
  expect_equal(nrow(hc), 2L)
  # 200 m d'origine moins les 2 x 15 m du corridor.
  traverse <- hc[hc$hors_m > 150, ]
  expect_equal(traverse$hors_m, 170, tolerance = 1e-6)
  expect_lt(as.numeric(sf::st_length(traverse)), 200)
  # Un seul type de geometrie sur toute la couche.
  expect_equal(unique(as.character(sf::st_geometry_type(hc))), "MULTILINESTRING")
})

test_that("le print annonce les couches ET garde la reserve mot pour mot", {
  # L'aval (nemetonshiny) doit porter CE texte a l'ecran, pas une reformulation :
  # un lineaire hors corridor est un gisement a instruire, pas une preuve.
  seg <- function(x0, y0, x1, y1) sf::st_linestring(rbind(c(x0, y0), c(x1, y1)))
  bdt <- sf::st_sf(classe = "piste",
    geometry = sf::st_sfc(seg(0, 0, 100, 0), crs = 2154))
  osm <- sf::st_sf(source = "osm", highway = "track",
    geometry = sf::st_sfc(seg(0, 500, 100, 500), crs = 2154))

  cmp <- comparer_desserte_osm(bdt, osm)
  # `cli` ecrit hors du flux standard : capture imbriquee, sortie ET messages.
  msg <- utils::capture.output(
    std <- utils::capture.output(print(cmp)), type = "message")
  sortie <- paste(c(std, msg), collapse = "\n")
  expect_match(sortie, "osm_hors_corridor", fixed = TRUE)
  expect_match(sortie, "bdtopo_hors_corridor", fixed = TRUE)
  expect_match(sortie, "n'est PAS une desserte manquante prouvee", fixed = TRUE)
  expect_match(sortie, "CA-28.5", fixed = TRUE)
})

test_that("comparer_desserte_osm tient sur des couches vides", {
  vide_l <- sf::st_sf(classe = character(0),
    geometry = sf::st_sfc(crs = sf::st_crs(2154)))
  vide_o <- sf::st_sf(source = character(0), highway = character(0),
    geometry = sf::st_sfc(crs = sf::st_crs(2154)))
  cmp <- comparer_desserte_osm(vide_l, vide_o)
  expect_equal(unname(cmp$resume[["osm_km"]]), 0)
  expect_true(is.na(cmp$resume[["osm_couvert_pct"]]))
  # Couches vides rendues comme `sf` a 0 ligne, jamais NULL : l'aval les ecrit
  # en GeoPackage sans cas particulier.
  for (couche in list(cmp$osm_hors_corridor, cmp$bdtopo_hors_corridor)) {
    expect_s3_class(couche, "sf")
    expect_equal(nrow(couche), 0L)
    expect_equal(sf::st_crs(couche), sf::st_crs(2154))
    expect_true("hors_m" %in% names(couche))
  }
})
