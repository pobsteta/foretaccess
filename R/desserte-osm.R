# Desserte OpenStreetMap comme source COMPLEMENTAIRE (spec 028).
#
# La BD TOPO reste la reference autoritaire. OSM n'ajoute que des CANDIDATS, qui
# doivent passer la qualification LiDAR avant tout usage -- meme regle que pour
# la desserte detectee (spec 026), sans exception.
#
# Mesure du 2026-07-30 sur l'AOI Chastel-Nouvel :
#   OSM 73,35 km contre 44,64 km pour la BD TOPO, mais 55,7 % du lineaire OSM
#   tombe DEJA dans le corridor BD TOPO. Le gisement est concentre dans 13,52 km
#   de `track` hors corridor ; les 14,09 km de `path` sont surtout de la
#   randonnee, sans valeur pour le debardage.
#   Sens inverse : OSM couvre la quasi-totalite des routes et du reseau public
#   (10 m d'ecart cumule sur 88 troncons), l'ecart portant sur 5,40 km de PISTES.
#
# La complementarite est donc asymetrique et entierement concentree sur les
# pistes.

# Types `highway` retenus par defaut. `path` est EXCLU : 14,09 km hors corridor
# sur l'AOI, mais majoritairement de la randonnee. `tertiary` aussi : une
# departementale absente de la BD TOPO est plus probablement un decalage de
# saisie qu'une decouverte.
.TYPES_HIGHWAY_DESSERTE <- c("track", "unclassified", "service")

#' Acquiert la desserte candidate depuis OpenStreetMap (spec 028)
#'
#' Source **complémentaire** de la BD TOPO, jamais substitutive. Les tronçons
#' rendus sont des **candidats** : ils doivent passer [qualifier_desserte()]
#' avant d'entrer dans une conception de réseau.
#'
#' @details
#' `path` et `tertiary` sont exclus par défaut. Sur l'AOI oracle, `path`
#' représente 14,09 km hors corridor BD TOPO mais relève surtout de la randonnée,
#' et une `tertiary` absente de la BD TOPO est plus probablement un décalage de
#' saisie qu'une découverte.
#'
#' **Overpass injoignable lève une erreur**, jamais une couche vide : un appelant
#' confondrait sinon « le serveur refuse » et « il n'y a rien ici ». C'est la
#' confusion qui a masqué l'absence de DFCI pendant une journée entière.
#'
#' @section Performance:
#' Une requete Overpass par emprise, sans pavage : le cout suit la densite de
#' voirie, pas la surface. **5,9 s a froid** sur une AOI de 31 ha (mesure
#' nemetonshiny, 2026-08-12).
#'
#' **Le pire cas est desormais BORNE** (ADR-010). Auparavant, une instance bridee
#' faisait boucler `osmdata` en backoff de 60 s sans plafond -- 16 reprises
#' consecutives mesurees, soit 16 minutes de pure attente, et plus de 10 minutes
#' pour une requete ordinaire un jour de bride. Le transport passe maintenant par
#' [osm_overpass()], dont la duree ne peut pas depasser
#' `timeout * length(serveurs) * (1 + max_reprises)`, soit **18 minutes au pire
#' absolu** avec les defauts (90 s x 4 instances x 3 essais) et quelques secondes
#' en nominal. Sur `429`, un `Retry-After` n'est honore que s'il est court
#' (< 10 s) ; au-dela on change d'instance plutot que d'attendre.
#'
#' Cela reste long pour une interface : un bouton qui appelle cette fonction doit
#' etre **asynchrone et annulable**. Ce qui change, c'est qu'il termine.
#' @inheritParams acquire_desserte
#' @param types Valeurs de `highway` retenues. Défaut : `track`,
#'   `unclassified`, `service`.
#' @return Un `sf` de lignes avec `source = "osm"`, `highway`, et les attributs
#'   `tracktype`, `surface`, `access` quand ils sont présents dans le flux.
#' @seealso [comparer_desserte_osm()], [acquire_desserte()] (la référence),
#'   `specs/028`.
#' @export
acquire_desserte_osm <- function(aoi, crs = 2154, cache_dir = tempdir(),
                                 overwrite = FALSE,
                                 types = .TYPES_HIGHWAY_DESSERTE,
                                 politique_cache = "reacquerir") {
  chemin <- .chemin_cache(cache_dir, "desserte_osm", "gpkg")
  prov <- list(crs = crs, types = paste(sort(types), collapse = ","))
  if (file.exists(chemin) && !overwrite &&
      cache_utilisable(chemin, "desserte_osm", "osm", prov, politique_cache)) {
    return(sf::st_read(chemin, quiet = TRUE))
  }
  aoi_sf <- sf::st_as_sf(sf::st_geometry(sf::st_as_sf(aoi)))
  bbox_wgs <- sf::st_bbox(sf::st_transform(aoi_sf, 4326))

  # Une seule requete, filtrage local : Overpass limite le debit des qu'on
  # multiplie les appels, et filtrer en local coute moins cher qu'un aller-retour.
  od <- .fetch_osm(bbox_wgs, key = "highway")
  lignes <- od$osm_lines
  vide <- sf::st_sf(source = character(0), highway = character(0),
    geometry = sf::st_sfc(crs = sf::st_crs(crs)))
  if (is.null(lignes) || nrow(lignes) == 0) {
    sf::st_write(vide, chemin, delete_dsn = TRUE, quiet = TRUE)
    .provenance_ecrire(chemin, "desserte_osm", "osm", prov)
    return(vide)
  }
  lignes <- sf::st_transform(lignes, crs)
  garder <- as.character(lignes$highway) %in% types
  garder[is.na(garder)] <- FALSE
  lignes <- lignes[garder, , drop = FALSE]
  lignes <- .reprojeter_clip(lignes, aoi_sf, crs)

  cols <- c("highway", intersect(c("tracktype", "surface", "access", "barrier"),
    names(lignes)))
  out <- if (nrow(lignes) == 0) {
    vide
  } else {
    d <- lignes[, cols, drop = FALSE]
    d$source <- "osm"
    d[, c("source", cols), drop = FALSE]
  }
  sf::st_write(out, chemin, delete_dsn = TRUE, quiet = TRUE)
  .provenance_ecrire(chemin, "desserte_osm", "osm", prov)
  out
}

#' Compare une desserte OSM à la BD TOPO (spec 028)
#'
#' Mesure le linéaire de part et d'autre d'un **corridor** autour de la
#' référence, par type OSM et par classe BD TOPO. C'est un **diagnostic**, pas un
#' résultat : un linéaire hors corridor n'est pas une desserte manquante prouvée.
#'
#' @details
#' Un tronçon OSM hors corridor peut être un décalage de saisie sur une voie déjà
#' présente, une trace erronée, ou un chemin non carrossable. Le chiffre à en
#' retenir est un **gisement à instruire**, et le CA-28.5 exige de le confronter
#' d'abord aux objets BD TOPO connus, puis à une annotation.
#'
#' Les **géométries** hors corridor sont rendues telles quelles, clippées : un
#' tronçon à moitié dans le corridor n'est renvoyé que pour sa moitié hors
#' corridor, sans quoi on présenterait comme « absent de la BD TOPO » un linéaire
#' qui y figure. Elles ne coûtent rien de plus : la différence géométrique est
#' déjà calculée pour mesurer le linéaire.
#'
#' @section Performance:
#' Recoupement geometrique de deux couches, tempere par l'index spatial de `sf`.
#' **104 s** pour 3 122 x 544 troncons (mesure nemetonshiny, 2026-08-12).
#' Purement local : aucun acces reseau, aucune surprise de debit.
#' @param bdtopo Desserte de référence (sortie d'[acquire_desserte()]).
#' @param osm Desserte candidate (sortie d'[acquire_desserte_osm()]).
#' @param corridor_m Demi-largeur du corridor (m). Défaut 15, la valeur de
#'   `dsr_detecter()` pour exclure le réseau de référence.
#' @return Une liste de classe `foretaccess_osm_compare` :
#'   \describe{
#'     \item{`osm`}{linéaire OSM total et hors corridor, par type.}
#'     \item{`bdtopo`}{linéaire BD TOPO hors corridor OSM, par classe.}
#'     \item{`resume`}{les cinq totaux (`osm_km`, `osm_hors_km`,
#'       `osm_couvert_pct`, `bdtopo_km`, `bdtopo_hors_km`).}
#'     \item{`corridor_m`}{la demi-largeur employée.}
#'     \item{`osm_hors_corridor`}{`sf` des tronçons OSM **amputés** de leur part
#'       dans le corridor BD TOPO : attributs d'origine plus `hors_m` (m).
#'       Géométrie homogène en `MULTILINESTRING`, CRS de l'entrée, `sf` à 0 ligne
#'       si rien ne sort du corridor (jamais `NULL`).}
#'     \item{`bdtopo_hors_corridor`}{le symétrique, BD TOPO hors corridor OSM.}
#'   }
#' @seealso [acquire_desserte_osm()], `specs/028`.
#' @export
comparer_desserte_osm <- function(bdtopo, osm, corridor_m = 15) {
  b <- sf::st_as_sf(.as_vector(bdtopo, "bdtopo"))
  o <- sf::st_as_sf(.as_vector(osm, "osm"))
  checkmate::assert_number(corridor_m, lower = 0, finite = TRUE)

  # Longueur de chaque troncon HORS d'un corridor donne, ET les morceaux
  # correspondants. Calcul un a un : st_difference vectorise ne conserve pas
  # l'appariement d'origine quand des entrees deviennent vides, et un mauvais
  # appariement fausserait toute la table.
  hors <- function(x, corr) {
    n <- nrow(x)
    if (n == 0 || is.null(corr)) {
      return(list(long = rep(0, n), parts = vector("list", n)))
    }
    parts <- lapply(seq_len(n), function(i) sf::st_difference(sf::st_geometry(x)[i], corr))
    long <- vapply(parts, function(g) if (length(g)) sum(as.numeric(sf::st_length(g))) else 0,
                   numeric(1))
    list(long = long, parts = parts)
  }
  corr_b <- if (nrow(b)) sf::st_union(sf::st_buffer(sf::st_geometry(b), corridor_m)) else NULL
  corr_o <- if (nrow(o)) sf::st_union(sf::st_buffer(sf::st_geometry(o), corridor_m)) else NULL

  h_o <- hors(o, corr_b)
  h_b <- hors(b, corr_o)
  # Assemblage AVANT les colonnes de travail : elles n'ont rien a faire dans une
  # couche destinee a la carte.
  osm_hc <- .sf_hors(o, h_o)
  bdtopo_hc <- .sf_hors(b, h_b)

  o$long_m <- if (nrow(o)) as.numeric(sf::st_length(o)) else numeric(0)
  o$hors_m <- h_o$long
  b$long_m <- if (nrow(b)) as.numeric(sf::st_length(b)) else numeric(0)
  b$hors_m <- h_b$long

  par_groupe <- function(x, champ) {
    if (nrow(x) == 0) {
      return(data.frame(groupe = character(0), total_km = numeric(0),
                        hors_km = numeric(0)))
    }
    g <- as.character(x[[champ]])
    data.frame(
      groupe = sort(unique(g)),
      total_km = as.numeric(tapply(x$long_m, g, sum)[sort(unique(g))]) / 1000,
      hors_km = as.numeric(tapply(x$hors_m, g, sum)[sort(unique(g))]) / 1000,
      row.names = NULL
    )
  }
  tot_o <- sum(o$long_m)
  structure(
    list(
      osm = par_groupe(o, "highway"),
      bdtopo = par_groupe(b, "classe"),
      resume = c(
        osm_km = tot_o / 1000,
        osm_hors_km = sum(o$hors_m) / 1000,
        osm_couvert_pct = if (tot_o > 0) 100 * (1 - sum(o$hors_m) / tot_o) else NA_real_,
        bdtopo_km = sum(b$long_m) / 1000,
        bdtopo_hors_km = sum(b$hors_m) / 1000
      ),
      corridor_m = corridor_m,
      osm_hors_corridor = osm_hc,
      bdtopo_hors_corridor = bdtopo_hc
    ),
    class = "foretaccess_osm_compare"
  )
}

# Assemble les morceaux hors corridor en un `sf` : attributs d'origine + hors_m.
# st_difference rend un LINESTRING quand rien n'est coupe et un MULTILINESTRING
# quand le corridor coupe le troncon en deux ; sans le cast la couche porterait
# DEUX types de geometrie et l'ecriture GeoPackage en aval deviendrait hasardeuse.
.sf_hors <- function(x, h) {
  crs <- sf::st_crs(x)
  att <- sf::st_drop_geometry(x)
  att <- att[, setdiff(names(att), c("long_m", "hors_m")), drop = FALSE]
  att$hors_m <- h$long
  keep <- which(h$long > 0)
  g <- if (length(keep)) {
    sf::st_cast(do.call(c, h$parts[keep]), "MULTILINESTRING")
  } else {
    sf::st_sfc(sf::st_multilinestring(), crs = crs)[0]
  }
  sf::st_sf(att[keep, , drop = FALSE], geometry = g, crs = crs)
}

#' @export
print.foretaccess_osm_compare <- function(x, ...) {
  r <- x$resume
  cli::cli_h3("OSM vs BD TOPO (corridor {x$corridor_m} m)")
  cli::cli_text("OSM {round(r[['osm_km']], 2)} km, dont
                 {round(r[['osm_couvert_pct']], 1)} % deja dans le corridor
                 BD TOPO ; {round(r[['osm_hors_km']], 2)} km hors corridor.")
  cli::cli_text("BD TOPO {round(r[['bdtopo_km']], 2)} km, dont
                 {round(r[['bdtopo_hors_km']], 2)} km hors corridor OSM.")
  cat("\n-- lineaire OSM par type (km) --\n")
  print(x$osm, row.names = FALSE)
  cat("\n-- lineaire BD TOPO par classe (km) --\n")
  print(x$bdtopo, row.names = FALSE)
  cat("\nGeometries clippees : $osm_hors_corridor (", nrow(x$osm_hors_corridor),
      " troncons), $bdtopo_hors_corridor (", nrow(x$bdtopo_hors_corridor),
      ").\n", sep = "")
  cat("\nUn lineaire hors corridor n'est PAS une desserte manquante prouvee :\n")
  cat("decalage de saisie, trace erronee, chemin non carrossable. Gisement a\n")
  cat("instruire (CA-28.5).\n")
  invisible(x)
}
