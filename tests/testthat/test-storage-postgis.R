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
