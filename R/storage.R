#' Interface de stockage vectoriel (StorageBackend)
#'
#' ForêtAccess écrit ses sorties vectorielles derrière une interface commune, avec
#' deux implémentations interchangeables : **GeoPackage** ([storage_gpkg()]) et
#' **PostGIS** ([storage_postgis()]). Conformément à l'ADR-002, **aucun backend
#' n'est le défaut** : il est choisi explicitement à chaque usage. Les rasters ne
#' passent pas par cette interface (GeoTIFF/COG sur disque).
#'
#' Contrat commun (méthodes S3) :
#' - [sb_write_layer()] : écrit une couche (idempotent : remplace si elle existe) ;
#' - [sb_read_layer()] : relit une couche ;
#' - [sb_list_layers()] : liste les couches disponibles.
#'
#' @name storage
NULL

#' Écrit une couche vectorielle
#' @param backend Objet de stockage ([storage_gpkg()] ou [storage_postgis()]).
#' @param layer Nom de la couche (chaîne).
#' @param data Objet `sf`.
#' @param ... Arguments spécifiques au backend.
#' @return `backend` de façon invisible.
#' @export
sb_write_layer <- function(backend, layer, data, ...) {
  UseMethod("sb_write_layer")
}

#' Relit une couche vectorielle
#' @inheritParams sb_write_layer
#' @return Un objet `sf`.
#' @export
sb_read_layer <- function(backend, layer, ...) {
  UseMethod("sb_read_layer")
}

#' Liste les couches disponibles
#' @inheritParams sb_write_layer
#' @return Un vecteur de caractères (noms de couches).
#' @export
sb_list_layers <- function(backend, ...) {
  UseMethod("sb_list_layers")
}

# Validation commune des arguments d'écriture.
.assert_write_args <- function(layer, data) {
  checkmate::assert_string(layer, min.chars = 1)
  checkmate::assert_class(data, "sf")
}
