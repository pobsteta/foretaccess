#' Sources de données géographiques par pays (config-driven)
#'
#' Couche d'abstraction pour les sources de données (ADR-002, patron **nemeton**) :
#' les endpoints de service et les identifiants de couche ne sont **jamais codés en
#' dur**. Ils sont déclarés dans un fichier JSON par pays
#' (`inst/datasources/FR.json`). Ajouter un pays ne demande qu'un fichier JSON,
#' pas de modification de code.
#'
#' Le résolveur alimente le Lot d'acquisition ([acquire_inputs()]) : celui-ci
#' demande une couche par sa **clé logique** (`dem`, `roads`, `bdforet_v2`,
#' `cadastre`) et obtient l'URL de service + l'identifiant de couche résolus.
#'
#' @name datasources
#' @keywords internal
NULL

# Cache des configurations chargees, par pays.
.datasource_cache <- new.env(parent = emptyenv())

#' Charge la configuration des sources d'un pays
#'
#' Lit et met en cache le JSON de configuration d'un pays.
#'
#' @param country Code pays ISO 3166-1 alpha-2 (défaut `"FR"`).
#' @return Une liste (la configuration du pays).
#' @export
#' @examples
#' cfg <- get_country_config("FR")
#' cfg$crs_national
get_country_config <- function(country = "FR") {
  country <- toupper(country)
  cle <- paste0("config_", country)
  if (exists(cle, envir = .datasource_cache)) {
    return(get(cle, envir = .datasource_cache))
  }

  fichier <- system.file("datasources", paste0(country, ".json"), package = "foretaccess")
  if (!nzchar(fichier) || !file.exists(fichier)) {
    cli::cli_abort(c(
      "Aucune configuration de sources pour le pays {.val {country}}.",
      "i" = "Pays disponibles : {.val {list_countries()}}."
    ))
  }

  config <- jsonlite::read_json(fichier, simplifyVector = FALSE)
  assign(cle, config, envir = .datasource_cache)
  config
}

#' Résout une source de données par sa clé
#'
#' Renvoie la configuration d'une couche déclarée dans le JSON du pays.
#'
#' @param source_key Clé de la source (p. ex. `"dem"`, `"roads"`).
#' @param country Code pays ISO. Défaut `"FR"`.
#' @return Une liste (config de la source), ou `NULL` si absente.
#' @export
#' @examples
#' get_data_source("dem", "FR")$layer
get_data_source <- function(source_key, country = "FR") {
  config <- get_country_config(country)
  config$layers[[source_key]]
}

#' Résout l'URL de service d'une couche
#'
#' Combine la couche et le service qu'elle référence pour renvoyer l'URL complète
#' du service, sa version, et l'identifiant de couche (`layer` pour un WMS,
#' `typename` pour un WFS).
#'
#' @param layer_key Clé de la couche (p. ex. `"dem"`, `"roads"`).
#' @param country Code pays ISO. Défaut `"FR"`.
#' @return Une liste (`url`, `version`, et `layer`/`typename`), ou `NULL`.
#' @export
#' @examples
#' info <- get_layer_service("dem", "FR")
#' info$url
#' info$layer
get_layer_service <- function(layer_key, country = "FR") {
  config <- get_country_config(country)
  couche <- config$layers[[layer_key]]
  if (is.null(couche)) {
    return(NULL)
  }
  if (!is.null(couche$service)) {
    service <- config$services[[couche$service]]
    if (!is.null(service)) {
      return(c(couche, list(url = service$url, version = service$version)))
    }
  }
  couche
}

#' CRS national d'un pays
#'
#' @param country Code pays ISO. Défaut `"FR"`.
#' @return Un entier (code EPSG ; 2154 pour la France).
#' @export
#' @examples
#' get_national_crs("FR")
get_national_crs <- function(country = "FR") {
  as.integer(get_country_config(country)$crs_national %||% 2154L)
}

#' Liste les pays configurés
#'
#' @return Un vecteur de codes pays ISO.
#' @export
#' @examples
#' list_countries()
list_countries <- function() {
  dir <- system.file("datasources", package = "foretaccess")
  if (!nzchar(dir)) {
    return(character(0))
  }
  fichiers <- list.files(dir, pattern = "\\.json$")
  sub("\\.json$", "", fichiers)
}

# Vide le cache des configurations (pour les tests).
.clear_datasource_cache <- function() {
  rm(list = ls(envir = .datasource_cache), envir = .datasource_cache)
  invisible(NULL)
}
