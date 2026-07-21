# Places de depot pour le cable-mat : derivation de candidates depuis la desserte
# (entree `departs` de `potentiel_cable()`, spec 004 section Places de depot).
#
# Sylvaccess prend la couche de depart comme une DONNEE (`c_file_departure`,
# attribut CABLE) : la place de depot est un fait de terrain, pas un derive
# calculable du MNT. Cette fonction ne pretend pas la remplacer -- elle produit
# des CANDIDATES a partir des criteres qu'on sait verifier sur la donnee
# disponible (acces camion, planeite, demi-tour, proximite de la foret), et le
# dit explicitement. Une place de depot reelle se valide sur le terrain.

#' Derive candidate cable landings from a road network
#'
#' A cable yarder line cannot start just anywhere: it needs a landing with a
#' truck-accessible platform. `potentiel_cable(departs = )` therefore expects a
#' dedicated layer, which Sylvaccess treats as an input of its own
#' (`c_file_departure`, attribute `CABLE`). When no such survey exists, this
#' function derives **candidates** from the road network, by filters that are
#' checkable on the available data.
#'
#' The result is an `sf` carrying a `cable` field, ready to be passed straight to
#' [potentiel_cable()] or written with `sf::st_write()`.
#'
#' @section Criteres:
#' A road segment yields candidate landings when it passes, in order:
#' 1. **Truck access** -- carriageway width `>= largeur_min_m` where a width
#'    attribute is available (`largeur`, `largeur_de_chaussee`); failing that,
#'    the `dfci` flag of [flag_dfci()]; failing that, a `classe` of `"route"` or
#'    `"dfci"`. A network carrying none of those attributes cannot be filtered on
#'    access at all: everything passes, and the function says so.
#' 2. **Turn-around** -- only when `retournements` is supplied: the segment is
#'    either a through-route (both ends connected to the network) or a dead-end
#'    with a turning area within `rayon_retournement_m` of its dangling tip.
#'    Without that layer the criterion is **not** applied -- absence of evidence
#'    is not evidence of absence.
#' 3. **Platform** -- terrain slope at the candidate point `<= pente_max_pct`
#'    (Horn, [calculer_terrain()]). A point where slope is undefined (MNT border)
#'    is dropped.
#' 4. **Usefulness** -- only when `foret` is supplied: within
#'    `distance_foret_max_m` of forest. A landing with no wood to reach is not
#'    one.
#'
#' Surviving points are then **thinned** to `espacement_min_m`, flattest first:
#' the balance of `potentiel_cable()` is proportional to the number of departure
#' cells, and two landings 20 m apart sweep the same forest twice.
#'
#' @param desserte Road network: path to a vector file or an `sf` of lines.
#' @param mnt Digital terrain model: `SpatRaster` or path. Must share the CRS of
#'   `desserte` (no implicit reprojection, ADR-004).
#' @param foret Forest: path or `sf` of polygons, or `NULL` (criterion 4 off).
#' @param retournements Turning areas: path or `sf` of points, or `NULL`
#'   (criterion 2 off).
#' @param largeur_min_m Minimum carriageway width for a log truck (m).
#' @param pente_max_pct Maximum terrain slope of the platform (%).
#' @param distance_foret_max_m Maximum distance to forest (m), used when `foret`
#'   is supplied.
#' @param espacement_min_m Minimum spacing between two landings (m).
#' @param rayon_retournement_m Max distance dead-end tip <-> turning area (m),
#'   used when `retournements` is supplied.
#' @param sortie `"points"` (default) for the landings themselves, `"troncons"`
#'   for the road segments that carry them.
#'
#' @return An `sf` with a `cable` column (always `1L`, the field read by
#'   [potentiel_cable()]): `POINT` when `sortie = "points"` (columns `id`,
#'   `cable`, `troncon` -- the row of `desserte` it sits on --, `acces`,
#'   `largeur_m`, `pente_pct`), `LINESTRING` when `sortie = "troncons"` (columns
#'   `troncon`, `cable`, `acces`, `largeur_m`, `pente_pct`, `n_places`).
#'
#' @seealso [potentiel_cable()] (consumes the layer), [flag_dfci()] (feeds the
#'   `dfci` flag used by criterion 1).
#' @export
#' @examples
#' toy <- system.file("extdata/toy", package = "foretaccess")
#' # Le MNT jouet est un plan a 20 % : on releve le seuil de planeite en
#' # consequence (aucune plateforme a 15 % sur ce terrain).
#' places <- places_depot(
#'   desserte = file.path(toy, "desserte.gpkg"),
#'   mnt = file.path(toy, "mnt.tif"),
#'   foret = file.path(toy, "foret.gpkg"),
#'   pente_max_pct = 25,
#'   espacement_min_m = 100
#' )
#' places
places_depot <- function(desserte,
                         mnt,
                         foret = NULL,
                         retournements = NULL,
                         largeur_min_m = 4,
                         pente_max_pct = 15,
                         distance_foret_max_m = 100,
                         espacement_min_m = 200,
                         rayon_retournement_m = 20,
                         sortie = c("points", "troncons")) {
  sortie <- match.arg(sortie)
  checkmate::assert_number(largeur_min_m, lower = 0, finite = TRUE)
  checkmate::assert_number(pente_max_pct, lower = 0, finite = TRUE)
  checkmate::assert_number(distance_foret_max_m, lower = 0, finite = TRUE)
  checkmate::assert_number(espacement_min_m, lower = 0, finite = TRUE)
  checkmate::assert_number(rayon_retournement_m, lower = 0, finite = TRUE)

  mnt <- .as_raster(mnt, "mnt")
  des <- .desserte_lignes(desserte, mnt)
  n_troncons <- length(unique(des$troncon))

  # --- 1. Acces camion ------------------------------------------------------
  acces <- .acces_camion(des, largeur_min_m)
  des$acces <- acces$acces
  des$largeur_m <- acces$largeur_m
  des <- des[acces$apte, ]
  .arreter_si_vide(des, "acces camion", "largeur_min_m")

  # --- 2. Demi-tour (seulement si une couche de retournements est fournie) ---
  if (is.null(retournements)) {
    cli::cli_inform(c("i" = "Aucune couche {.arg retournements} : le critere de
                             demi-tour n'est pas applique."))
  } else {
    ret <- .as_vector(retournements, "retournements")
    .verifier_crs(ret, mnt, "retournements")
    deg <- .degres_extremites(des)
    traversante <- deg$deg_debut >= 2 & deg$deg_fin >= 2
    des <- des[traversante |
      .retournement_a_portee(des, deg, ret, rayon_retournement_m), ]
    .arreter_si_vide(des, "demi-tour", "rayon_retournement_m")
  }

  # --- 3. Plateforme : points candidats le long des troncons, puis pente ----
  pts <- .points_le_long(des, espacement_min_m)
  pente <- as.numeric(terra::extract(
    calculer_terrain(mnt)$slope_pct, terra::vect(pts)
  )[, 2])
  # Pente indeterminee (bord du MNT) : ecartee, on ne devine pas une plateforme.
  garde <- !is.na(pente) & pente <= pente_max_pct
  pts <- pts[garde, ]
  pts$pente_pct <- pente[garde]
  .arreter_si_vide(pts, "planeite", "pente_max_pct")

  # --- 4. Proximite de la foret ---------------------------------------------
  if (!is.null(foret)) {
    fo <- .as_vector(foret, "foret")
    .verifier_crs(fo, mnt, "foret")
    d <- sf::st_distance(sf::st_geometry(pts), sf::st_union(sf::st_geometry(fo)))
    pts <- pts[as.numeric(d) <= distance_foret_max_m, ]
    .arreter_si_vide(pts, "proximite de la foret", "distance_foret_max_m")
  }

  # --- 5. Espacement : la plateforme la plus plate d'abord ------------------
  pts <- pts[.espacer(pts, espacement_min_m), ]

  pts$cable <- 1L
  pts$id <- seq_len(nrow(pts))
  pts <- pts[, c("id", "cable", "troncon", "acces", "largeur_m", "pente_pct")]

  cli::cli_inform(c(
    "v" = "{nrow(pts)} place{?s} de depot candidate{?s} sur
           {length(unique(pts$troncon))}/{n_troncons} troncon{?s}.",
    "!" = "Candidates heuristiques, pas un releve : une place de depot exige une
           plateforme et un acces grumier a valider sur le terrain.",
    "i" = "A defaut, {.fn potentiel_cable} part de TOUTE la desserte -- couverture
           beaucoup trop optimiste."
  ))

  if (sortie == "points") {
    return(pts)
  }
  .troncons_porteurs(des, pts)
}

# --- Chargement et verifications --------------------------------------------

# Desserte en LINESTRING simples, indexees par leur troncon d'origine : les
# criteres (degre des extremites, echantillonnage) travaillent par ligne simple,
# mais la sortie doit pouvoir se raccrocher a la ligne fournie par l'appelant.
.desserte_lignes <- function(desserte, mnt) {
  des <- .as_vector(desserte, "desserte")
  if (nrow(des) == 0) {
    cli::cli_abort("La couche {.arg desserte} est vide.")
  }
  .verifier_crs(des, mnt, "desserte")

  des <- sf::st_zm(des, drop = TRUE)
  types <- as.character(sf::st_geometry_type(des))
  if (!any(grepl("LINE", types))) {
    cli::cli_abort(c(
      "{.arg desserte} doit etre une couche de lignes.",
      "x" = "Geometries recues : {.val {unique(types)}}."
    ))
  }
  des <- des[grepl("LINE", types), ]
  des$troncon <- seq_len(nrow(des))
  suppressWarnings(sf::st_cast(des, "LINESTRING"))
}

# Aucune reprojection implicite (ADR-004) : une couche mal projetee est une
# erreur de l'appelant, pas quelque chose a rattraper en silence.
.verifier_crs <- function(x, mnt, arg) {
  if (is.na(sf::st_crs(x))) {
    cli::cli_abort("La couche {.arg {arg}} n'a pas de CRS.")
  }
  if (sf::st_crs(x) != sf::st_crs(mnt)) {
    cli::cli_abort(c(
      "Le CRS de {.arg {arg}} differe de celui du MNT.",
      "i" = "Aucune reprojection implicite : reprojeter en amont (ADR-004)."
    ))
  }
  invisible(TRUE)
}

.arreter_si_vide <- function(x, critere, param) {
  if (nrow(x) > 0) {
    return(invisible(TRUE))
  }
  cli::cli_abort(c(
    "Aucune place de depot candidate : le critere {.emph {critere}} elimine tout.",
    "i" = "Assouplir {.arg {param}}, ou fournir une couche de places de depot relevee."
  ))
}

# --- Criteres ---------------------------------------------------------------

# Acces camion, par ordre de force de la preuve : la largeur mesuree prime sur
# le flag DFCI, qui prime sur la classe. Sans aucun de ces attributs, le critere
# est indeterminable -- on retient tout, en le disant (le filtrage se fera sur
# les criteres geometriques).
.acces_camion <- function(des, largeur_min_m) {
  n <- nrow(des)
  larg <- .largeur_desserte(des)
  dfci <- if (!is.null(des[["dfci"]])) as.integer(des$dfci) else rep(NA_integer_, n)
  classe <- if (!is.null(des[["classe"]])) as.character(des$classe) else rep(NA_character_, n)

  apte <- logical(n)
  acces <- rep(NA_character_, n)

  par_largeur <- !is.na(larg)
  apte[par_largeur] <- larg[par_largeur] >= largeur_min_m
  acces[par_largeur] <- "largeur"

  par_dfci <- !par_largeur & !is.na(dfci)
  apte[par_dfci] <- dfci[par_dfci] == 1L
  acces[par_dfci] <- "dfci"

  par_classe <- !par_largeur & !par_dfci & !is.na(classe)
  apte[par_classe] <- classe[par_classe] %in% c("route", "dfci")
  acces[par_classe] <- "classe"

  indetermine <- !par_largeur & !par_dfci & !par_classe
  apte[indetermine] <- TRUE
  acces[indetermine] <- "indetermine"

  if (any(indetermine)) {
    cli::cli_inform(c(
      "!" = "{sum(indetermine)} troncon{?s} sans attribut d'acces
             ({.field largeur}, {.field dfci}, {.field classe}) : critere d'acces
             camion non applique, ils passent le filtre.",
      "i" = "Poser le flag {.field dfci} avec {.fn flag_dfci} affine le tri."
    ))
  }
  list(apte = apte, acces = acces, largeur_m = larg)
}

# Points candidats le long de chaque troncon, un tous les `espacement_m` au plus
# (au moins un par troncon, au milieu, quelle que soit sa longueur).
.points_le_long <- function(des, espacement_m) {
  g <- sf::st_geometry(des)
  lg <- as.numeric(sf::st_length(g))
  attrs <- sf::st_drop_geometry(des)

  morceaux <- lapply(seq_along(g), function(i) {
    k <- max(1L, floor(lg[i] / espacement_m))
    frac <- if (k == 1L) 0.5 else seq(0.5 / k, 1 - 0.5 / k, length.out = k)
    p <- sf::st_cast(sf::st_line_sample(g[i], sample = frac), "POINT")
    sf::st_sf(attrs[rep(i, length(p)), , drop = FALSE], geometry = p)
  })
  do.call(rbind, morceaux)
}

# Eclaircissement glouton : on garde la place la plus plate, puis toute place a
# au moins `espacement_m` de celles deja gardees. Le cout du balayage cable est
# proportionnel au nombre de cellules de depart -- deux places voisines balaient
# deux fois la meme foret.
.espacer <- function(pts, espacement_m) {
  xy <- sf::st_coordinates(pts)
  garde <- integer(0)
  for (i in order(pts$pente_pct)) {
    if (!length(garde) ||
      all(sqrt((xy[i, 1] - xy[garde, 1])^2 + (xy[i, 2] - xy[garde, 2])^2) >= espacement_m)) {
      garde <- c(garde, i)
    }
  }
  sort(garde)
}

# Troncons portant au moins une place retenue, avec la pente de leur meilleure.
.troncons_porteurs <- function(des, pts) {
  att <- sf::st_drop_geometry(pts)
  meilleure <- tapply(att$pente_pct, att$troncon, min)
  n_places <- table(att$troncon)
  ids <- as.integer(names(meilleure))

  tr <- des[match(ids, des$troncon), ]
  tr$cable <- 1L
  tr$pente_pct <- as.numeric(meilleure)
  tr$n_places <- as.integer(n_places)
  # `tapply` groupe par facteur (ordre lexical) : on remet l'ordre des troncons.
  tr <- tr[order(tr$troncon), ]
  tr[, c("troncon", "cable", "acces", "largeur_m", "pente_pct", "n_places")]
}
