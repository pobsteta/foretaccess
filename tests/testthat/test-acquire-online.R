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

# --- Mesure nominale d'`acquire_desserte_osm()` (CA-8.7 du brief OSM) --------
#
# Le brief exige que les `@section Performance` soient RE-MESUREES, pas
# recopiees. Le pire cas est calculable (`timeout x serveurs x (1 + reprises)`)
# et ecrit dans la doc ; le NOMINAL, lui, ne s'obtient qu'en appelant Overpass
# pour de vrai. C'est ici sa place, et nulle part ailleurs : un test unitaire ne
# doit pas taper le reseau, et une mesure faite a la main une fois vieillit.
#
# Le chiffre est ECRIT dans le resume du job (`GITHUB_STEP_SUMMARY`) pour etre
# lisible sans fouiller les logs, et REMESURE chaque semaine sans que personne
# n'ait a y penser.

test_that("acquire_desserte_osm : mesure nominale, une requete reelle", {
  skip_if_no_online()

  centre <- sf::st_transform(
    sf::st_sfc(sf::st_point(c(5.45, 45.05)), crs = 4326), 2154)
  aoi <- sf::st_buffer(sf::st_sf(geometry = centre), 250)
  cache <- withr::local_tempdir()

  t <- Sys.time()
  d <- acquire_desserte_osm(aoi, cache_dir = cache)
  secondes <- round(as.numeric(difftime(Sys.time(), t, units = "secs")), 1)

  # Le CONTRAT est teste ; la duree est MESUREE, jamais assertee. Un seuil de
  # duree sur un service tiers gratuit ne mesurerait que son humeur du jour, et
  # ferait echouer la CI pour une raison etrangere au paquet.
  expect_s3_class(d, "sf")
  expect_true(all(c("source", "highway") %in% names(d)))

  ligne <- sprintf(
    "**acquire_desserte_osm()** : %s s a froid, %d troncon%s, AOI de 250 m (%s)",
    format(secondes), nrow(d), if (nrow(d) > 1) "s" else "",
    format(Sys.Date()))
  cat("\nMESURE :", ligne, "\n")
  resume <- Sys.getenv("GITHUB_STEP_SUMMARY")
  if (nzchar(resume)) {
    cat(ligne, "\n", file = resume, append = TRUE)
  }

  # Le second appel doit servir le CACHE : s'il retape le reseau, la mesure
  # ci-dessus ne vaut rien comme reference et le cache ne sert a rien.
  t2 <- Sys.time()
  d2 <- acquire_desserte_osm(aoi, cache_dir = cache)
  s2 <- as.numeric(difftime(Sys.time(), t2, units = "secs"))
  expect_equal(nrow(d2), nrow(d))
  cat("MESURE : second appel (cache) :", round(s2, 2), "s\n")
})
