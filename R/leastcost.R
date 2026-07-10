#' Propagation de coût cumulé depuis des sources (service partagé)
#'
#' Service de plus court chemin sur grille, **sans aucune règle métier** : il est
#' mutualisé entre le skidder (Lot 2), le porteur (Lot 3) et le camion DFCI
#' (Lot 6). Reproduit `calcul_distance_de_cout()` de Sylvaccess v3.6.
#'
#' @details
#' Sémantique, fidèle au code source Sylvaccess (spec 002 §4.1) :
#' * **8-connexité** ; le pas vaut la résolution, ou `résolution × sqrt(2)` en
#'   diagonale ;
#' * le coût d'un pas est `surface_cout[cellule d'arrivée] × pas`. C'est le coût de
#'   la **cellule d'arrivée**, et non la moyenne des deux cellules — ce qui
#'   distingue Sylvaccess de [terra::costDist()] et interdit de s'en servir tel quel ;
#' * une cellule de coût `NA`, ou hors de `zone`, est **infranchissable** ;
#' * `cout_max` plafonne la propagation : au-delà, la sortie vaut `NA`.
#'
#' L'algorithme est un Dijkstra à tas binaire. C'est le candidat naturel à un
#' portage Rust si la performance l'exige (ADR-001).
#'
#' @param surface_cout `SpatRaster` de coût par cellule (`NA` = infranchissable).
#' @param sources Sources de la propagation : `SpatRaster` (toute cellule non
#'   `NA` et non nulle est une source, sa valeur servant d'identifiant), ou objet
#'   `sf` qui sera rasterisé sur la grille de `surface_cout`.
#' @param zone `SpatRaster` logique délimitant les cellules traversables, ou
#'   `NULL` (défaut) pour n'exclure que les cellules de coût `NA`.
#' @param cout_max Coût cumulé maximal. Défaut `Inf` (aucun plafond).
#'
#' @return Un objet de classe `foretaccess_propagation` : une liste de trois
#'   `SpatRaster` sur la grille de `surface_cout`.
#'   \describe{
#'     \item{`cout_cumule`}{coût cumulé depuis la source la moins coûteuse.}
#'     \item{`allocation`}{identifiant de cette source (`Out_alloc` du `.pyx`).}
#'     \item{`predecesseur`}{indice de la cellule précédente sur le chemin optimal,
#'       qui permet de reconstruire le trajet avec [chemin_optimal()].}
#'   }
#'   Les cellules non atteintes valent `NA` dans les trois couches.
#'
#' @seealso [chemin_optimal()]
#' @export
#' @examples
#' cout <- terra::rast(nrows = 11, ncols = 11, xmin = 0, xmax = 11,
#'                     ymin = 0, ymax = 11, crs = "EPSG:2154")
#' terra::values(cout) <- 1
#' src <- terra::rast(cout)
#' src[6, 6] <- 1
#' prop <- propager_cout(cout, src)
#' prop$cout_cumule[6, 1]
propager_cout <- function(surface_cout, sources, zone = NULL, cout_max = Inf) {
  surface_cout <- .as_raster(surface_cout, "surface_cout")
  checkmate::assert_number(cout_max, lower = 0)

  res <- terra::res(surface_cout)
  if (!isTRUE(all.equal(res[1], res[2]))) {
    cli::cli_abort(c(
      "{.arg surface_cout} doit avoir des cellules carrees.",
      "x" = "Resolution : {paste(res, collapse = ' x ')}."
    ))
  }

  src <- .rasteriser_sources(sources, surface_cout)
  nr <- terra::nrow(surface_cout)
  nc <- terra::ncol(surface_cout)

  cout <- as.numeric(terra::values(surface_cout))
  ids <- as.numeric(terra::values(src))
  ids[!is.na(ids) & ids == 0] <- NA_real_

  franchissable <- !is.na(cout)
  if (!is.null(zone)) {
    zone <- .as_raster(zone, "zone")
    .valider_grille(zone, surface_cout, "zone")
    zv <- as.numeric(terra::values(zone))
    franchissable <- franchissable & !is.na(zv) & zv != 0
  }

  depart <- which(!is.na(ids))
  if (!length(depart)) {
    cli::cli_abort("{.arg sources} ne contient aucune cellule source.")
  }

  sortie <- .dijkstra(
    cout = cout, franchissable = franchissable, ids = ids, depart = depart,
    nr = nr, nc = nc, pas = res[1], cout_max = cout_max
  )

  gabarit <- terra::rast(surface_cout)
  faire <- function(v, nom) {
    r <- terra::rast(gabarit)
    terra::values(r) <- v
    names(r) <- nom
    r
  }

  structure(
    list(
      cout_cumule  = faire(sortie$dist, "cout_cumule"),
      allocation   = faire(sortie$alloc, "allocation"),
      predecesseur = faire(sortie$pred, "predecesseur")
    ),
    class = "foretaccess_propagation"
  )
}

# Normalise les sources en un raster d'identifiants sur la grille de reference.
.rasteriser_sources <- function(sources, gabarit) {
  if (inherits(sources, "SpatRaster")) {
    .valider_grille(sources, gabarit, "sources")
    return(sources)
  }
  if (inherits(sources, "sf") || inherits(sources, "SpatVector")) {
    v <- terra::vect(sources)
    r <- terra::rasterize(v, gabarit)
    return(r)
  }
  cli::cli_abort(c(
    "{.arg sources} doit etre un {.cls SpatRaster} ou un objet {.cls sf}.",
    "x" = "Recu : {.cls {class(sources)[1]}}."
  ))
}

# Dijkstra a tas binaire, 8-connexite, cout porte par la cellule d'arrivee.
# Travaille sur des vecteurs en ordre "row-major" (celui de terra::values()).
.dijkstra <- function(cout, franchissable, ids, depart, nr, nc, pas, cout_max) {
  n <- nr * nc
  diag <- pas * sqrt(2)

  dist <- rep(Inf, n)
  alloc <- rep(NA_real_, n)
  pred <- rep(NA_real_, n)
  fige <- logical(n)

  # Decalages des 8 voisins : (dligne, dcolonne, longueur du pas).
  dl <- c(-1L, -1L, -1L, 0L, 0L, 1L, 1L, 1L)
  dc <- c(-1L, 0L, 1L, -1L, 1L, -1L, 0L, 1L)
  pas_v <- c(diag, pas, diag, pas, pas, diag, pas, diag)

  # Les sources sont a cout nul et s'allouent a elles-memes.
  dist[depart] <- 0
  alloc[depart] <- ids[depart]

  tas <- .tas_creer(length(depart) + 16L)
  for (s in depart) tas <- .tas_ajouter(tas, s, 0)

  while (tas$n > 0L) {
    tete <- .tas_retirer(tas)
    tas <- tete$tas
    u <- tete$cle
    if (fige[u]) next
    fige[u] <- TRUE

    du <- dist[u]
    lu <- ((u - 1L) %/% nc) + 1L
    cu <- ((u - 1L) %% nc) + 1L

    for (k in seq_len(8L)) {
      lv <- lu + dl[k]
      cv <- cu + dc[k]
      if (lv < 1L || lv > nr || cv < 1L || cv > nc) next

      v <- (lv - 1L) * nc + cv
      if (fige[v] || !franchissable[v]) next

      # Cout du pas : celui de la cellule d'arrivee (et non la moyenne).
      dv <- du + cout[v] * pas_v[k]
      if (dv > cout_max || dv >= dist[v]) next

      dist[v] <- dv
      alloc[v] <- alloc[u]
      pred[v] <- u
      tas <- .tas_ajouter(tas, v, dv)
    }
  }

  dist[!is.finite(dist)] <- NA_real_
  list(dist = dist, alloc = alloc, pred = pred)
}

# --- Tas binaire minimal (cle = indice de cellule, priorite = cout cumule) ----
# Implemente a la main : aucune dependance, et le portage Rust sera direct.

# Echange deux elements du tas (cle et priorite ensemble).
.tas_echanger <- function(tas, i, j) {
  tmp <- tas$cle[i]
  tas$cle[i] <- tas$cle[j]
  tas$cle[j] <- tmp
  tmp <- tas$prio[i]
  tas$prio[i] <- tas$prio[j]
  tas$prio[j] <- tmp
  tas
}

.tas_creer <- function(capacite = 64L) {
  list(cle = integer(capacite), prio = numeric(capacite), n = 0L)
}

.tas_ajouter <- function(tas, cle, prio) {
  if (tas$n == length(tas$cle)) {
    tas$cle <- c(tas$cle, integer(length(tas$cle)))
    tas$prio <- c(tas$prio, numeric(length(tas$prio)))
  }
  i <- tas$n + 1L
  tas$cle[i] <- cle
  tas$prio[i] <- prio
  tas$n <- i

  # Remontee.
  while (i > 1L) {
    p <- i %/% 2L
    if (tas$prio[p] <= tas$prio[i]) break
    tas <- .tas_echanger(tas, p, i)
    i <- p
  }
  tas
}

.tas_retirer <- function(tas) {
  cle <- tas$cle[1L]
  tas$cle[1L] <- tas$cle[tas$n]
  tas$prio[1L] <- tas$prio[tas$n]
  tas$n <- tas$n - 1L

  # Descente.
  i <- 1L
  while (TRUE) {
    g <- 2L * i
    d <- g + 1L
    petit <- i
    if (g <= tas$n && tas$prio[g] < tas$prio[petit]) petit <- g
    if (d <= tas$n && tas$prio[d] < tas$prio[petit]) petit <- d
    if (petit == i) break
    tas <- .tas_echanger(tas, petit, i)
    i <- petit
  }
  list(tas = tas, cle = cle)
}

#' Trajet optimal d'une cellule vers sa source
#'
#' Remonte le raster de prédécesseurs produit par [propager_cout()] pour
#' reconstituer le chemin de moindre coût, de `depuis` jusqu'à la source qui lui a
#' été allouée.
#'
#' @param propagation Objet `foretaccess_propagation` issu de [propager_cout()].
#' @param depuis Cellule de départ : indice de cellule (entier), ou objet `sf` de
#'   points (chaque point donne un trajet).
#'
#' @return Un objet `sf` de `LINESTRING` dans le CRS de la propagation, avec les
#'   colonnes `cellule` (cellule de départ), `source` (identifiant alloué) et
#'   `cout` (coût cumulé). Les cellules non atteintes sont ignorées, avec un
#'   avertissement.
#' @export
chemin_optimal <- function(propagation, depuis) {
  checkmate::assert_class(propagation, "foretaccess_propagation")

  cout <- propagation$cout_cumule
  pred <- as.numeric(terra::values(propagation$predecesseur))
  dist <- as.numeric(terra::values(cout))
  alloc <- as.numeric(terra::values(propagation$allocation))

  cellules <- .cellules_depuis(depuis, cout)

  atteintes <- !is.na(dist[cellules])
  if (!any(atteintes)) {
    cli::cli_abort("Aucune cellule de {.arg depuis} n'a ete atteinte par la propagation.")
  }
  if (!all(atteintes)) {
    cli::cli_warn("{sum(!atteintes)} cellule{?s} de {.arg depuis} non atteinte{?s} : ignoree{?s}.")
    cellules <- cellules[atteintes]
  }

  lignes <- lapply(cellules, function(cel) {
    chaine <- .remonter(cel, pred)
    xy <- terra::xyFromCell(cout, chaine)
    # Une cellule source seule ne forme pas une ligne : on la double.
    if (nrow(xy) == 1L) xy <- rbind(xy, xy)
    sf::st_linestring(xy)
  })

  sf::st_sf(
    cellule = cellules,
    source = alloc[cellules],
    cout = dist[cellules],
    geometry = sf::st_sfc(lignes, crs = sf::st_crs(terra::crs(cout)))
  )
}

# Remonte la chaine des predecesseurs jusqu'a la source (predecesseur NA).
.remonter <- function(cel, pred) {
  chaine <- cel
  courant <- cel
  while (!is.na(pred[courant])) {
    courant <- as.integer(pred[courant])
    chaine <- c(chaine, courant)
  }
  chaine
}

# Normalise `depuis` en un vecteur d'indices de cellules.
.cellules_depuis <- function(depuis, gabarit) {
  if (inherits(depuis, "sf") || inherits(depuis, "SpatVector")) {
    xy <- terra::crds(terra::vect(depuis))
    return(terra::cellFromXY(gabarit, xy))
  }
  checkmate::assert_integerish(depuis, lower = 1, upper = terra::ncell(gabarit),
                               any.missing = FALSE, .var.name = "depuis")
  as.integer(depuis)
}

#' @export
print.foretaccess_propagation <- function(x, ...) {
  d <- terra::values(x$cout_cumule)
  cli::cli_inform(c(
    "Propagation de cout ForetAccess",
    "*" = "cellules atteintes : {sum(!is.na(d))} / {length(d)}",
    "*" = "cout cumule max : {signif(max(d, na.rm = TRUE), 5)}"
  ))
  invisible(x)
}
