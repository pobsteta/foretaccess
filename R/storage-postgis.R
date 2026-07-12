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

#' Écrit une couche en PostGIS (idempotent, index spatial)
#'
#' Écrase la couche si elle existe (`delete_layer = TRUE`) puis crée un **index
#' spatial GiST** sur sa colonne de géométrie (US-8.1). L'index accélère les
#' requêtes zonales et les jointures spatiales.
#'
#' @param backend Objet `foretaccess_storage_postgis`.
#' @param layer Nom de la couche.
#' @param data Objet `sf`.
#' @param spatial_index Créer l'index spatial GiST après l'écriture (défaut `TRUE`).
#' @param ... Passé à [sf::st_write()].
#' @return `backend` de façon invisible.
#' @export
sb_write_layer.foretaccess_storage_postgis <- function(backend, layer, data, ...,
                                                       spatial_index = TRUE) {
  .assert_write_args(layer, data)
  # Id(schema, table) cible le schéma ; delete_layer = TRUE -> idempotent.
  sf::st_write(
    obj = data, dsn = backend$conn,
    layer = DBI::Id(schema = backend$schema, table = layer),
    delete_layer = TRUE, quiet = TRUE, ...
  )
  if (isTRUE(spatial_index)) .creer_index_spatial(backend, layer)
  invisible(backend)
}

# Crée un index GiST sur la (les) colonne(s) de géométrie de la table, si
# absent. La vue PostGIS `geometry_columns` donne le nom de la colonne ; le nom
# de l'index est stable (idempotence : CREATE INDEX IF NOT EXISTS).
.creer_index_spatial <- function(backend, layer) {
  conn <- backend$conn
  geomcols <- DBI::dbGetQuery(
    conn,
    paste(
      "SELECT f_geometry_column FROM geometry_columns",
      "WHERE f_table_schema = $1 AND f_table_name = $2"
    ),
    params = list(backend$schema, layer)
  )$f_geometry_column
  if (!length(geomcols)) {
    return(invisible(backend))
  }
  gc <- geomcols[1]
  idx <- paste0(layer, "_", gc, "_gist")
  DBI::dbExecute(conn, DBI::SQL(sprintf(
    "CREATE INDEX IF NOT EXISTS %s ON %s.%s USING GIST (%s)",
    DBI::dbQuoteIdentifier(conn, idx),
    DBI::dbQuoteIdentifier(conn, backend$schema),
    DBI::dbQuoteIdentifier(conn, layer),
    DBI::dbQuoteIdentifier(conn, gc)
  )))
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
