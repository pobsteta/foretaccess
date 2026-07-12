test_that("round-trip d'une couche en PostGIS (schéma jetable)", {
  skip_if_no_test_db()

  conn <- connect_test_db()
  schema <- throwaway_schema()
  withr::defer({
    drop_schema(conn, schema)
    DBI::dbDisconnect(conn)
  })

  sb <- storage_postgis(conn, schema = schema)   # ensure_schema = TRUE crée le schéma
  layer <- sf::st_sf(
    id = 1:2,
    geometry = sf::st_sfc(sf::st_point(c(0, 0)), sf::st_point(c(1, 1)), crs = 2154)
  )

  sb_write_layer(sb, "essai", layer)
  expect_true("essai" %in% sb_list_layers(sb))

  back <- sb_read_layer(sb, "essai")
  expect_equal(nrow(back), 2)

  # idempotence
  sb_write_layer(sb, "essai", layer)
  expect_equal(nrow(sb_read_layer(sb, "essai")), 2)
  expect_length(sb_list_layers(sb), 1)
})

test_that("l'ecriture PostGIS cree un index spatial GiST (US-8.1)", {
  skip_if_no_test_db()

  conn <- connect_test_db()
  schema <- throwaway_schema()
  withr::defer({
    drop_schema(conn, schema)
    DBI::dbDisconnect(conn)
  })

  sb <- storage_postgis(conn, schema = schema)
  layer <- sf::st_sf(
    id = 1:2,
    geometry = sf::st_sfc(sf::st_point(c(0, 0)), sf::st_point(c(1, 1)), crs = 2154)
  )
  sb_write_layer(sb, "indexee", layer)

  # Un index GiST existe sur la table (jointure pg_index / pg_am).
  idx <- DBI::dbGetQuery(conn, paste(
    "SELECT i.relname AS idx, am.amname AS methode",
    "FROM pg_class t",
    "JOIN pg_namespace n ON n.oid = t.relnamespace",
    "JOIN pg_index ix ON ix.indrelid = t.oid",
    "JOIN pg_class i ON i.oid = ix.indexrelid",
    "JOIN pg_am am ON am.oid = i.relam",
    "WHERE n.nspname = $1 AND t.relname = $2 AND am.amname = 'gist'"
  ), params = list(schema, "indexee"))
  expect_gte(nrow(idx), 1)

  # Idempotence : ré-écrire ne duplique pas l'index (CREATE INDEX IF NOT EXISTS).
  sb_write_layer(sb, "indexee", layer)
  idx2 <- DBI::dbGetQuery(conn, paste(
    "SELECT count(*) AS n FROM pg_class t",
    "JOIN pg_namespace n ON n.oid = t.relnamespace",
    "JOIN pg_index ix ON ix.indrelid = t.oid",
    "JOIN pg_class i ON i.oid = ix.indexrelid",
    "JOIN pg_am am ON am.oid = i.relam",
    "WHERE n.nspname = $1 AND t.relname = $2 AND am.amname = 'gist'"
  ), params = list(schema, "indexee"))
  expect_equal(idx2$n, 1)
})
