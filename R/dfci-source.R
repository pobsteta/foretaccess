# Alimentation du flag DFCI (`CL_DFCI`) sur la desserte : source du camion DFCI
# (spec 006). Le flag est ORTHOGONAL aux classes route/piste/reseau_public --
# une meme desserte peut etre route classique ET reseau de defense.
#
# Deux voies, dans l'ordre :
#  - Voie A (source dediee) : appariement au reseau DFCI officiel OpenStreetMap,
#    tague `ref:FR:DFCI` (wiki OSM FR:France/DFCI_et_DECI). C'est l'identifiant
#    sans ambiguite d'une piste DFCI (reference du panneau terrain, "AL 04").
#  - Voie B (repli geometrique) : quand OSM ne rend aucune piste DFCI, on retient
#    les pistes soit TRAVERSANTES et d'emprise suffisante, soit en CUL-DE-SAC
#    munies d'une aire de retournement. Heuristique explicitement signalee.
#
# Comble le maillon « a alimenter via une source DFCI dediee » laisse ouvert en
# phase 1 (spec 010 §10.2).

#' Pose le flag DFCI (CL_DFCI) sur la desserte
#'
#' Marks the road segments that make up the fire-defence network (DFCI), the
#' source of the DFCI truck engine (spec 006). The flag is orthogonal to the
#' `route`/`piste`/`reseau_public` classes. Two strategies, in order:
#' * **Route A (dedicated OSM source)** — a segment is flagged when it coincides
#'   (within `tol_appariement_m`) with an OSM DFCI track (`ref:FR:DFCI`).
#' * **Route B (geometric fallback)** — when `dfci_lignes` is empty/`NULL`, keep
#'   the tracks that are either *through-routes* wider than `emprise_min_m`, or
#'   *dead-ends fitted with a turning area* (within `rayon_retournement_m` of the
#'   dangling end). This is an explicitly heuristic guess (false positives
#'   possible), logged as such.
#'
#' @param desserte An `sf` of line features (from [acquire_desserte()]).
#' @param dfci_lignes An `sf` of DFCI tracks (from [acquire_dfci()]), or `NULL`.
#' @param retournements An `sf` of turning-area points, or `NULL`.
#' @param emprise_min_m Minimum width of a through DFCI track (m). Default 10.
#' @param rayon_retournement_m Max distance dead-end tip <-> turning area (m).
#'   Default 20.
#' @param tol_appariement_m Matching tolerance desserte <-> OSM DFCI (m). Default 10.
#' @return `desserte` with an added integer column `dfci` (0/1).
#' @seealso [acquire_dfci()], [acquire_desserte()]
#' @export
flag_dfci <- function(desserte, dfci_lignes = NULL, retournements = NULL,
                      emprise_min_m = 10, rayon_retournement_m = 20,
                      tol_appariement_m = 10) {
  desserte$dfci <- 0L
  if (nrow(desserte) == 0) {
    return(desserte)
  }

  # Voie A : reseau DFCI officiel OSM disponible -> appariement geometrique.
  if (!is.null(dfci_lignes) && nrow(dfci_lignes) > 0) {
    desserte$dfci <- .flag_dfci_osm(desserte, dfci_lignes, tol_appariement_m)
    cli::cli_inform(
      "Réseau DFCI : {sum(desserte$dfci)} tronçon{?s} flaggé{?s} \\
       (source OSM {.field ref:FR:DFCI})."
    )
    return(desserte)
  }

  # Voie B : repli geometrique, signale.
  desserte$dfci <- .flag_dfci_repli(desserte, retournements, emprise_min_m,
    rayon_retournement_m)
  cli::cli_inform(c(
    "!" = "Réseau DFCI : aucune piste OSM {.field ref:FR:DFCI} sur l'emprise, \\
           repli géométrique.",
    "i" = "{sum(desserte$dfci)} tronçon{?s} retenu{?s} \\
           (heuristique emprise / traversée / retournement)."
  ))
  desserte
}

# --- Voie A -----------------------------------------------------------------

# Un troncon est DFCI s'il intersecte le tampon (tol_m) de l'union des lignes
# DFCI OSM. Rapproche la geometrie OSM (souvent decalee de quelques metres) du
# reseau BD TOPO qui porte le flag.
.flag_dfci_osm <- function(desserte, dfci_lignes, tol_m) {
  dfci_lignes <- sf::st_transform(dfci_lignes, sf::st_crs(desserte))
  tampon <- sf::st_union(sf::st_buffer(sf::st_geometry(dfci_lignes), tol_m))
  touche <- lengths(sf::st_intersects(sf::st_geometry(desserte), tampon)) > 0
  as.integer(touche)
}

# --- Voie B (repli geometrique) ---------------------------------------------

# Une piste est retenue si :
#  (a) TRAVERSANTE (les deux extremites raccordees au reseau) ET emprise >= seuil ;
#  (b) en CUL-DE-SAC (au moins une extremite pendante) MAIS avec une aire de
#      retournement a portee du bout pendant (le camion peut y faire demi-tour).
# Restreint aux `classe == "piste"` (les routes carrossables sont deja desservies).
.flag_dfci_repli <- function(desserte, retournements, emprise_min_m, rayon_retournement_m) {
  n <- nrow(desserte)
  est_piste <- if (!is.null(desserte[["classe"]])) {
    as.character(desserte$classe) == "piste"
  } else {
    rep(TRUE, n)
  }
  est_piste[is.na(est_piste)] <- FALSE

  deg <- .degres_extremites(desserte)
  traversante <- deg$deg_debut >= 2 & deg$deg_fin >= 2
  cul_de_sac  <- deg$deg_debut == 1 | deg$deg_fin == 1

  larg <- .largeur_desserte(desserte)
  emprise_ok <- !is.na(larg) & larg >= emprise_min_m

  branche_a <- traversante & emprise_ok
  branche_b <- cul_de_sac &
    .retournement_a_portee(desserte, deg, retournements, rayon_retournement_m)

  as.integer(est_piste & (branche_a | branche_b))
}

# Degre de chaque extremite d'un troncon = nombre d'extremites (tous troncons
# confondus) coincidant a ce noeud. Graphe base-R (pas d'igraph, cf. Lot 17) : on
# hache les coordonnees d'extremites arrondies a `tol_m`. L'extremite propre du
# troncon compte pour 1 -> deg >= 2 <=> raccordee a un autre troncon ; deg == 1
# <=> extremite pendante (cul-de-sac).
.degres_extremites <- function(desserte, tol_m = 1) {
  g <- sf::st_geometry(desserte)
  bornes <- lapply(g, function(ls) {
    m <- sf::st_coordinates(ls)[, 1:2, drop = FALSE]
    list(debut = m[1, ], fin = m[nrow(m), ])
  })
  cle <- function(p) paste(round(p[1] / tol_m), round(p[2] / tol_m), sep = "_")
  cles_debut <- vapply(bornes, function(e) cle(e$debut), character(1))
  cles_fin   <- vapply(bornes, function(e) cle(e$fin), character(1))
  compte <- table(c(cles_debut, cles_fin))
  data.frame(
    deg_debut = as.integer(compte[cles_debut]),
    deg_fin   = as.integer(compte[cles_fin])
  )
}

# Emprise/largeur disponible (m) : colonne `largeur`, sinon `largeur_de_chaussee`
# (attribut BD TOPO). Absente -> NA (critere d'emprise indeterminable, la piste ne
# peut alors etre retenue que par la branche cul-de-sac + retournement).
.largeur_desserte <- function(x) {
  col <- intersect(c("largeur", "largeur_de_chaussee", "LARGEUR"), names(x))
  if (!length(col)) {
    return(rep(NA_real_, nrow(x)))
  }
  suppressWarnings(as.numeric(as.character(x[[col[1]]])))
}

# Une aire de retournement est-elle a portee du bout PENDANT (extremite de degre 1)
# de chaque troncon ? Vrai si au moins un point de retournement est a <= rayon_m
# d'une extremite pendante du troncon.
.retournement_a_portee <- function(desserte, deg, retournements, rayon_m) {
  n <- nrow(desserte)
  if (is.null(retournements) || nrow(retournements) == 0) {
    return(rep(FALSE, n))
  }
  retournements <- sf::st_transform(retournements, sf::st_crs(desserte))
  pts_ret <- sf::st_geometry(retournements)
  g <- sf::st_geometry(desserte)
  out <- logical(n)
  for (i in seq_len(n)) {
    m <- sf::st_coordinates(g[[i]])[, 1:2, drop = FALSE]
    bouts <- list()
    if (deg$deg_debut[i] == 1) bouts <- c(bouts, list(m[1, ]))
    if (deg$deg_fin[i] == 1) bouts <- c(bouts, list(m[nrow(m), ]))
    if (!length(bouts)) next
    pt_bouts <- sf::st_sfc(lapply(bouts, sf::st_point), crs = sf::st_crs(desserte))
    d <- sf::st_distance(pt_bouts, pts_ret)
    out[i] <- any(as.numeric(d) <= rayon_m)
  }
  out
}
