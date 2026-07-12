# Test d'integration reseau (opt-in) : appels reels IGN / OSM sur une micro-AOI.
# Ne tourne PAS en CI par defaut (garde FORETACCESS_RUN_ONLINE_TESTS=TRUE +
# skip_if_offline). Spec 010 §6.

test_that("acquire_inputs telecharge de vraies couches sur une micro-AOI (CA-A.1)", {
  skip_if_no_online()

  # Micro-AOI (~500 m) sur une zone forestiere connue (Vercors).
  centre <- sf::st_sfc(sf::st_point(c(5.45, 45.05)), crs = 4326)
  centre <- sf::st_transform(centre, 2154)
  aoi <- sf::st_buffer(sf::st_sf(geometry = centre), 250)

  cache <- withr::local_tempdir()
  inp <- acquire_inputs(aoi, cache_dir = cache, res_m = 5)

  expect_s3_class(inp, "foretaccess_inputs")
  expect_true(file.exists(inp$mnt))
  expect_s3_class(inp$desserte, "sf")
  expect_true("classe" %in% names(inp$desserte))
  expect_equal(sf::st_crs(inp$desserte), sf::st_crs(2154))

  # Idempotence : 2e appel sert le cache (CA-A.6).
  inp2 <- acquire_inputs(aoi, cache_dir = cache, res_m = 5)
  expect_equal(inp2$mnt, inp$mnt)

  # Enchainement vers preprocess (CA-A.4).
  pre <- preprocess(inp$mnt, inp$desserte, inp$foret)
  expect_s3_class(pre, "foretaccess_preprocessing")
})
