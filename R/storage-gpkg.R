#' Backend de stockage GeoPackage
#'
#' Implémentation de l'interface [storage] au-dessus d'un fichier GeoPackage
#' (via \pkg{sf}).
#'
#' @param path Chemin du fichier `.gpkg` (créé à la première écriture).
#' @return Un objet de classe `foretaccess_storage_gpkg`.
#' @seealso [storage_postgis()], [storage]
#' @export
#' @examples
#' \dontrun{
#' sb <- storage_gpkg(tempfile(fileext = ".gpkg"))
#' sb_write_layer(sb, "essai", sf::st_sf(id = 1, geometry = sf::st_sfc(sf::st_point(c(0, 0)))))
#' sb_list_layers(sb)
#' }
storage_gpkg <- function(path) {
  checkmate::assert_string(path, min.chars = 1)
  structure(
    list(path = path),
    class = c("foretaccess_storage_gpkg", "foretaccess_storage")
  )
}

#' @export
sb_write_layer.foretaccess_storage_gpkg <- function(backend, layer, data, ...) {
  .assert_write_args(layer, data)
  # delete_layer = TRUE -> écriture idempotente (remplace la couche existante).
  sf::st_write(
    obj = data, dsn = backend$path, layer = layer,
    delete_layer = TRUE, quiet = TRUE, ...
  )
  invisible(backend)
}

#' @export
sb_read_layer.foretaccess_storage_gpkg <- function(backend, layer, ...) {
  checkmate::assert_file_exists(backend$path, access = "r")
  sf::st_read(dsn = backend$path, layer = layer, quiet = TRUE, ...)
}

#' @export
sb_list_layers.foretaccess_storage_gpkg <- function(backend, ...) {
  if (!file.exists(backend$path)) {
    return(character(0))
  }
  sf::st_layers(backend$path)$name
}
