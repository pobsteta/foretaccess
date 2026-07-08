# Helpers pour les tests d'intégration PostGIS.
#
# Garde-fous (inspirés de Nemeton) pour ne JAMAIS écrire dans une base de prod :
#   - FORETACCESS_DB_URL_TEST non défini            -> skip
#   - FORETACCESS_DB_URL_TEST == FORETACCESS_DB_URL -> skip (copier-coller de la prod)
# Les tests créent puis suppriment un schéma jetable dédié.

test_db_url <- function() Sys.getenv("FORETACCESS_DB_URL_TEST", unset = "")

skip_if_no_test_db <- function() {
  url <- test_db_url()
  if (!nzchar(url)) {
    testthat::skip("FORETACCESS_DB_URL_TEST non défini")
  }
  prod <- Sys.getenv("FORETACCESS_DB_URL", unset = "")
  if (nzchar(prod) && identical(url, prod)) {
    testthat::skip("FORETACCESS_DB_URL_TEST == FORETACCESS_DB_URL (prod)")
  }
  if (!requireNamespace("RPostgres", quietly = TRUE)) {
    testthat::skip("RPostgres non disponible")
  }
}

connect_test_db <- function() {
  DBI::dbConnect(RPostgres::Postgres(), dbname = test_db_url())
}

# Nom de schéma jetable, unique par processus de test.
throwaway_schema <- function() {
  paste0("fa_test_", Sys.getpid())
}

drop_schema <- function(conn, schema) {
  DBI::dbExecute(conn, DBI::SQL(sprintf(
    "DROP SCHEMA IF EXISTS %s CASCADE",
    DBI::dbQuoteIdentifier(conn, schema)
  )))
}
