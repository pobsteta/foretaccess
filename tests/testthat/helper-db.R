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

# Décompose une URL postgresql://user:pass@host:port/dbname en composants.
# RPostgres ne re-parse PAS une URL passée via `dbname` : il faut l'éclater.
parse_pg_url <- function(url) {
  rx <- "^postgres(?:ql)?://(?:([^:@/]+)(?::([^@/]+))?@)?([^:/?]+)(?::([0-9]+))?/([^?]+)"
  m <- regmatches(url, regexec(rx, url))[[1]]
  if (length(m) == 0L) {
    stop("URL PostgreSQL invalide : ", url)
  }
  list(
    user     = m[2],
    password = m[3],
    host     = m[4],
    port     = if (nzchar(m[5])) as.integer(m[5]) else 5432L,
    dbname   = m[6]
  )
}

connect_test_db <- function() {
  p <- parse_pg_url(test_db_url())
  args <- list(RPostgres::Postgres(), dbname = p$dbname, host = p$host, port = p$port)
  if (nzchar(p$user)) args$user <- p$user
  if (nzchar(p$password)) args$password <- p$password
  do.call(DBI::dbConnect, args)
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
