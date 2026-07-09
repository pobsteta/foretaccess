#' Backend de stockage PostGIS
#'
#' Implémentation de l'interface [storage] au-dessus d'une base PostGIS. Suivant
#' l'ADR-002, le modèle cible est une **base dédiée** avec **un schéma par
#' run/massif** ; le schéma est un paramètre explicite du backend.
#'
#' @param conn Connexion `DBI` active (p. ex. `DBI::dbConnect(RPostgres::Postgres(), ...)`).
#'   Le cycle de vie de la connexion est géré par l'appelant.
#' @param schema Nom du schéma PostgreSQL cible (défaut `"public"`).
#' @param ensure_schema Créer le schéma s'il n'existe pas (défaut `TRUE`).
#' @return Un objet de classe `foretaccess_storage_postgis`.
#' @seealso [storage_gpkg()], [storage]
#' @export
storage_postgis <- function(conn, schema = "public", ensure_schema = TRUE) {
  checkmate::assert_class(conn, "DBIConnection")
  checkmate::assert_string(schema, min.chars = 1)
  backend <- structure(
    list(conn = conn, schema = schema),
    class = c("foretaccess_storage_postgis", "foretaccess_storage")
  )
  if (isTRUE(ensure_schema)) {
    sb_ensure_schema(backend)
  }
  backend
}

#' Crée le schéma PostgreSQL du backend s'il n'existe pas
#' @param backend Objet `foretaccess_storage_postgis`.
#' @return `backend` de façon invisible.
#' @export
sb_ensure_schema <- function(backend) {
  UseMethod("sb_ensure_schema")
}

#' @export
sb_ensure_schema.foretaccess_storage_postgis <- function(backend) {
  DBI::dbExecute(
    backend$conn,
    DBI::SQL(sprintf(
      "CREATE SCHEMA IF NOT EXISTS %s",
      DBI::dbQuoteIdentifier(backend$conn, backend$schema)
    ))
  )
  invisible(backend)
}

#' @export
sb_write_layer.foretaccess_storage_postgis <- function(backend, layer, data, ...) {
  .assert_write_args(layer, data)
  # Id(schema, table) cible le schéma ; delete_layer = TRUE -> idempotent.
  sf::st_write(
    obj = data, dsn = backend$conn,
    layer = DBI::Id(schema = backend$schema, table = layer),
    delete_layer = TRUE, quiet = TRUE, ...
  )
  invisible(backend)
}

#' @export
sb_read_layer.foretaccess_storage_postgis <- function(backend, layer, ...) {
  sf::st_read(
    dsn = backend$conn,
    layer = DBI::Id(schema = backend$schema, table = layer),
    quiet = TRUE, ...
  )
}

#' @export
sb_list_layers.foretaccess_storage_postgis <- function(backend, ...) {
  res <- DBI::dbGetQuery(
    backend$conn,
    "SELECT table_name FROM information_schema.tables WHERE table_schema = $1",
    params = list(backend$schema)
  )
  as.character(res$table_name)
}
