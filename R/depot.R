# Places de depot pour le cable-mat : derivation de candidates depuis la desserte
# (entree `departs` de `potentiel_cable()`, spec 004 section Places de depot).
#
# Sylvaccess prend la couche de depart comme une DONNEE (`c_file_departure`,
# attribut CABLE) : la place de depot est un fait de terrain, pas un derive
# calculable du MNT. Cette fonction ne pretend pas la remplacer -- elle produit
# des CANDIDATES a partir des criteres qu'on sait verifier sur la donnee
# disponible (acces camion, planeite, demi-tour, proximite de la foret), et le
# dit explicitement. Une place de depot reelle se valide sur le terrain.
#
# CONFRONTATION A L'ORACLE (ColduPre, `CABLE != 0` = 2 troncons sur 125). La
# premiere version (v1.6.0) n'en retrouvait AUCUN, a tous les seuils. Deux
# erreurs de modele, corrigees en v1.6.1 :
#
#  - la PLANEITE etait mesuree par la pente omnidirectionnelle du MNT au point.
#    A 5 m de resolution la banquette d'une route (4-5 m) n'est PAS resolue :
#    on mesurait le VERSANT, pas la plateforme. Les 2 vraies places sont sur des
#    versants a 24 % et 65 % -- la seconde est le troncon le plus raide du
#    reseau. Filtrer la-dessus elimine la montagne, c'est-a-dire le terrain ou
#    l'on cable. On mesure desormais la pente EN LONG locale (denivele le long
#    de la route sur `fenetre_plateforme_m`) : une route traverse un versant a
#    65 % avec 1 % en long. Les 2 vraies places y sont a 1,1 % et 3,2 %.
#  - l'ACCES rejetait les `classe == "piste"` et les `dfci == 0`. Or l'une des
#    deux vraies places est une piste forestiere non DFCI. Ces attributs ne
#    discriminent pas : ils informent desormais (colonne `acces`) mais ne
#    rejettent plus. Seule une largeur MESUREE et insuffisante rejette.

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
#' 1. **Truck access** -- a segment is rejected only on **hard evidence**: a
#'    *measured* carriageway width (LiDAR `largeur_carrossable_m`, else BD TOPO
#'    `largeur` / `largeur_de_chaussee`) below `largeur_min_m`. The `dfci` flag of
#'    [flag_dfci()] and the `classe` are
#'    recorded in the `acces` column but never reject: on the only oracle
#'    available they do not discriminate (see *Validation*).
#' 2. **Turn-around** -- only when `retournements` is supplied: the segment is
#'    either a through-route (both ends connected to the network) or a dead-end
#'    with a turning area within `rayon_retournement_m` of its dangling tip.
#'    Without that layer the criterion is **not** applied -- absence of evidence
#'    is not evidence of absence.
#' 3. **Platform** -- **longitudinal grade** of the road at the candidate point
#'    `<= pente_max_pct`, measured over `fenetre_plateforme_m` along the
#'    centreline. Deliberately *not* the terrain slope: at 5 m resolution a road
#'    bench is not resolved by the DTM, so terrain slope measures the hillside,
#'    not the platform -- and would eliminate exactly the steep ground where
#'    cable yarding is used.
#' 4. **Usefulness** -- only when `foret` is supplied: within
#'    `distance_foret_max_m` of forest. A landing with no wood to reach is not
#'    one.
#'
#' Sampling puts one candidate every `espacement_min_m` **along each segment**
#' (at least one per segment, whatever its length): the balance of
#' [potentiel_cable()] is proportional to the number of departure cells, so a
#' 2 km road must not yield 400 of them. The spacing is deliberately **not**
#' enforced *between* segments: a greedy cross-segment thinning evicted both real
#' ColduPre landings, each beaten by a flatter point 18 m and 93 m away on a
#' neighbouring road. Recall matters more than tidiness in a pre-filter.
#'
#' @section Validation:
#' Confronted with the only oracle available -- the Sylvaccess ColduPre test set,
#' whose road network carries the surveyed `CABLE` attribute: **2 landings among
#' 125 segments**. Both are retained (**recall 2/2**) at every threshold below,
#' and `pente_max_pct` buys the reduction:
#'
#' | `pente_max_pct` | segments kept | recall | margin on the worst true landing |
#' |---|---|---|---|
#' | 4 % | 43/125 (34 %) | 2/2 | 0.6 pt |
#' | **6 %** (default) | **54/125 (43 %)** | **2/2** | **2.6 pt** |
#' | 8 % | 71/125 (57 %) | 2/2 | 4.6 pt |
#' | 15 % | 104/125 (83 %) | 2/2 | 11.6 pt |
#'
#' Read the other column honestly: **precision is ~4 %**. This is a **coarse
#' pre-filter** -- it halves the search space while keeping the real landings --
#' **not** a substitute for a survey. The `CABLE` attribute encodes field
#' knowledge the geometry does not carry; no threshold on this data isolates the
#' two real landings. Use the output to *narrow* a field or photo-interpretation
#' pass, not to feed [potentiel_cable()] blind.
#'
#' The default is calibrated on **two** landings. Treat it as an order of
#' magnitude, and re-tune it on your own massif if you can.
#'
#' The bench is reproducible: `data-raw/oracle_places_depot.R`.
#'
#' @section Performance et selectivite:
#' `places_depot()` scans the whole network by pure coordinate interpolation
#' (no per-point `sf` call): sub-second on a departmental network. **But its
#' output size -- the number of landings -- is what governs the cost of the step
#' after it**, [potentiel_cable()], whose runtime is proportional to the number of
#' departures. On a raw BD TOPO network **with no measured width and no
#' `retournements` layer**, criteria 1-2 reject nothing, so only grade and forest
#' proximity filter -- yielding *hundreds to thousands* of loose departures and an
#' over-optimistic cable coverage.
#'
#' To bring departures down to an **exploitable** count (tens), feed it richer
#' inputs, in order of effect:
#' * a **`retournements`** layer (turn-arounds) -- turns criterion 2 on, the
#'   single biggest cut on a real network;
#' * a **measured width** (`largeur` / `largeur_de_chaussee`, or LiDAR-derived,
#'   see `acquire_desserte_lidar()` roadmap) -- turns criterion 1 into a real
#'   truck-access filter;
#' * a tighter **`espacement_min_m`** and lower **`pente_max_pct`**.
#'
#' Without any of these it stays a coarse pre-filter: usable to *narrow* a manual
#' pass, not to feed the cable engine blind at interactive speed.
#'
#' @param desserte Road network: path to a vector file or an `sf` of lines.
#' @param mnt Digital terrain model: `SpatRaster` or path. Must share the CRS of
#'   `desserte` (no implicit reprojection, ADR-004).
#' @param foret Forest: path or `sf` of polygons, or `NULL` (criterion 4 off).
#' @param retournements Turning areas: path or `sf` of points, or `NULL`
#'   (criterion 2 off).
#' @param largeur_min_m Minimum carriageway width for a log truck (m). Only ever
#'   applied to a *measured* width; see criterion 1.
#' @param largeur_champ Optional name of the column holding the measured width. By
#'   default the LiDAR carriageway `largeur_carrossable_m` (from
#'   [acquire_desserte_lidar()] / [qualifier_desserte()]) is used when present,
#'   then the BD TOPO `largeur` / `largeur_de_chaussee`. Set this to compose with a
#'   custom width column.
#' @param pente_max_pct Maximum **longitudinal grade** of the road at the
#'   platform (%), not terrain slope -- see criterion 3.
#' @param fenetre_plateforme_m Length of road over which that grade is measured,
#'   centred on the candidate point (m). Roughly the length a landing occupies.
#' @param distance_foret_max_m Maximum distance to forest (m), used when `foret`
#'   is supplied.
#' @param espacement_min_m Spacing between two candidates *along the same*
#'   segment (m). At least one candidate per segment regardless.
#' @param rayon_retournement_m Max distance dead-end tip <-> turning area (m),
#'   used when `retournements` is supplied.
#' @param sortie `"points"` (default) for the landings themselves, `"troncons"`
#'   for the road segments that carry them.
#'
#' @return An `sf` with a `cable` column (always `1L`, the field read by
#'   [potentiel_cable()]): `POINT` when `sortie = "points"` (columns `id`,
#'   `cable`, `troncon` -- the row of `desserte` it sits on --, `acces`,
#'   `largeur_m`, `pente_pct` -- the longitudinal grade), `LINESTRING` when
#'   `sortie = "troncons"` (columns `troncon`, `cable`, `acces`, `largeur_m`,
#'   `pente_pct`, `n_places`).
#'
#' @seealso [potentiel_cable()] (consumes the layer), [flag_dfci()] (feeds the
#'   `dfci` flag reported by criterion 1).
#' @export
#' @examples
#' toy <- system.file("extdata/toy", package = "foretaccess")
#' places <- places_depot(
#'   desserte = file.path(toy, "desserte.gpkg"),
#'   mnt = file.path(toy, "mnt.tif"),
#'   foret = file.path(toy, "foret.gpkg"),
#'   espacement_min_m = 100
#' )
#' places
places_depot <- function(desserte,
                         mnt,
                         foret = NULL,
                         retournements = NULL,
                         largeur_min_m = 4,
                         largeur_champ = NULL,
                         pente_max_pct = 6,
                         fenetre_plateforme_m = 50,
                         distance_foret_max_m = 100,
                         espacement_min_m = 200,
                         rayon_retournement_m = 20,
                         sortie = c("points", "troncons")) {
  sortie <- match.arg(sortie)
  checkmate::assert_number(largeur_min_m, lower = 0, finite = TRUE)
  checkmate::assert_number(pente_max_pct, lower = 0, finite = TRUE)
  checkmate::assert_number(fenetre_plateforme_m, lower = 0, finite = TRUE)
  checkmate::assert_number(distance_foret_max_m, lower = 0, finite = TRUE)
  checkmate::assert_number(espacement_min_m, lower = 0, finite = TRUE)
  checkmate::assert_number(rayon_retournement_m, lower = 0, finite = TRUE)

  mnt <- .as_raster(mnt, "mnt")
  des <- .desserte_lignes(desserte, mnt)
  n_troncons <- length(unique(des$troncon))

  # --- 1. Acces camion ------------------------------------------------------
  acces <- .acces_camion(des, largeur_min_m, largeur_champ)
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
  # La pente est celle de la ROUTE (en long), pas celle du versant : cf. l'entete
  # du fichier, une banquette n'est pas resolue par un MNT a 5 m.
  pts <- .points_le_long(des, espacement_min_m)
  pente <- .pente_en_long(pts, des, mnt, fenetre_plateforme_m)
  # Pente indeterminee (bord du MNT, troncon degenere) : ecartee, on ne devine
  # pas une plateforme.
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

  pts$cable <- 1L
  pts$id <- seq_len(nrow(pts))
  pts <- pts[, c("id", "cable", "troncon", "acces", "largeur_m", "pente_pct")]

  cli::cli_inform(c(
    "v" = "{nrow(pts)} place{?s} de depot candidate{?s} sur
           {length(unique(pts$troncon))}/{n_troncons} troncon{?s}.",
    "!" = "Pre-filtre grossier, pas un releve. Sur l'oracle ColduPre : les 2 vraies
           places de depot sont retrouvees, mais parmi 54 troncons sur 125
           (precision ~4 %).",
    "i" = "A confirmer par photo-interpretation ou visite. Voir la section
           {.emph Validation} de {.fn places_depot}."
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

  # `hors_desserte` (CL_SVAC = 0) porte la topologie, pas l'exploitation : un
  # sentier ou une bretelle de rond-point n'est pas une place de depot. Retire
  # APRES la numerotation, pour que `troncon` reste l'index de la couche fournie.
  #
  # Ce n'est PAS le critere d'acces ecarte sur ColduPre (cf. `.acces_camion()`) :
  # celui-la rejetait sur `classe == "piste"` / `dfci == 0`, des attributs de
  # QUALITE, et eliminait une vraie place sur deux. Ici la classe dit que le
  # troncon n'est pas de la desserte du tout.
  n_hd <- nrow(des)
  des <- .sans_hors_desserte(des)
  n_hd <- n_hd - nrow(des)
  if (n_hd > 0) {
    cli::cli_inform(c(
      "i" = "{n_hd} troncon{?s} {.val hors_desserte} ecarte{?s}
             (hors exploitation, CL_SVAC = 0)."
    ))
  }
  .arreter_si_vide(des, "classe de desserte", "desserte")

  des <- suppressWarnings(sf::st_cast(des, "LINESTRING"))

  # Troncons de longueur nulle : ni abscisse, ni pente en long. ColduPre en
  # contient (longueur minimale du reseau = 0 m).
  nulle <- as.numeric(sf::st_length(des)) <= 0
  if (any(nulle)) {
    cli::cli_inform(c(
      "i" = "{sum(nulle)} troncon{?s} de longueur nulle ecarte{?s}
             (pas de plateforme mesurable)."
    ))
    des <- des[!nulle, ]
  }
  .arreter_si_vide(des, "longueur non nulle", "desserte")
  des
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

# Acces camion. Seule une largeur MESUREE et insuffisante rejette : c'est la
# seule preuve dure dont on dispose.
#
# `dfci` et `classe` sont RAPPORTES (colonne `acces`) mais ne rejettent plus.
# Confrontation a ColduPre : l'une des deux vraies places de depot est une piste
# forestiere a `CL_DFCI = 0` -- rejeter sur ces attributs elimine une vraie place
# sur deux. Ils informent, ils ne tranchent pas.
.acces_camion <- function(des, largeur_min_m, largeur_champ = NULL) {
  n <- nrow(des)
  larg <- .largeur_desserte(des, largeur_champ)
  dfci <- if (!is.null(des[["dfci"]])) as.integer(des$dfci) else rep(NA_integer_, n)
  classe <- if (!is.null(des[["classe"]])) as.character(des$classe) else rep(NA_character_, n)

  mesuree <- !is.na(larg)
  apte <- !mesuree | larg >= largeur_min_m

  acces <- rep("indetermine", n)
  acces[!is.na(classe)] <- paste0("classe:", classe[!is.na(classe)])
  acces[!is.na(dfci) & dfci == 1L] <- "dfci"
  acces[mesuree] <- "largeur"

  if (!any(mesuree)) {
    cli::cli_inform(c(
      "!" = "Aucune largeur mesuree ({.field largeur_carrossable_m} / {.field largeur}
             / {.field largeur_de_chaussee}) : le critere d'acces camion ne rejette rien.",
      "i" = "Les colonnes {.field dfci} et {.field classe} sont rapportees dans
             {.field acces} mais ne tranchent pas -- sur l'oracle ColduPre elles
             ecartent une vraie place de depot sur deux."
    ))
  }
  list(apte = apte, acces = acces, largeur_m = larg)
}

# Pente EN LONG de la route au point candidat : denivele entre les deux bouts
# d'une fenetre de `fenetre_m` centree sur le point, rapporte a la distance
# PARCOURUE LE LONG de la route (pas a vol d'oiseau).
#
# C'est la grandeur qui decrit une plateforme. La pente omnidirectionnelle du
# MNT decrit le VERSANT : a 5 m de resolution, la banquette d'une route (4-5 m
# de large) n'est pas resolue, et une route peut traverser un versant a 65 %
# avec 1 % en long. Cf. l'entete du fichier (confrontation ColduPre).
.pente_en_long <- function(pts, des, mnt, fenetre_m) {
  g <- sf::st_geometry(des)
  lg <- pts$.longueur
  demi <- fenetre_m / 2
  a <- pmax(0, pts$.abscisse - demi)
  b <- pmin(lg, pts$.abscisse + demi)

  # Un seul jeu de coordonnees (bouts a et b concatenes) -> un seul extract MNT.
  za_zb <- .altitude_sur_ligne(g, c(pts$.ligne, pts$.ligne), c(a, b), mnt)
  n <- nrow(pts)
  za <- za_zb[seq_len(n)]
  zb <- za_zb[n + seq_len(n)]

  d <- b - a
  ifelse(d > 0, 100 * abs(zb - za) / d, NA_real_)
}

# Sommets d'une ligne + longueurs de segment cumulees. Base de toute
# interpolation le long de la ligne. `sf::st_coordinates` une fois par ligne.
.sommets_ligne <- function(geom) {
  m <- sf::st_coordinates(geom)[, 1:2, drop = FALSE]
  seg <- sqrt(diff(m[, 1])^2 + diff(m[, 2])^2)
  list(m = m, cum = c(0, cumsum(seg)), seg = seg, tot = sum(seg))
}

# Coordonnees (x, y) a la distance curviligne `d` le long d'une ligne cachee.
.interp_le_long <- function(c, d) {
  d <- min(max(d, 0), c$tot)
  j <- findInterval(d, c$cum, rightmost.closed = TRUE)
  j <- max(1L, min(j, nrow(c$m) - 1L))
  t <- if (c$seg[j] > 0) (d - c$cum[j]) / c$seg[j] else 0
  c(c$m[j, 1] + t * (c$m[j + 1, 1] - c$m[j, 1]),
    c$m[j, 2] + t * (c$m[j + 1, 2] - c$m[j, 2]))
}

# Altitude du MNT au point situe a la distance curviligne `dist_abs[i]` le long de
# la ligne `idx[i]`. Interpolation de coordonnees -- PAS de `sf::st_line_sample`
# par point : celui-ci re-parse le CRS a chaque appel (`CPL_crs_parameters` = 73 %
# du temps de places_depot, profilage 2026-07-22). Sommets extraits une seule fois
# par ligne UNIQUE, puis un seul `terra::extract` sur la matrice x/y.
.altitude_sur_ligne <- function(g, idx, dist_abs, mnt) {
  cache <- new.env(parent = emptyenv())
  coords_ligne <- function(li) {
    cle <- as.character(li)
    if (is.null(cache[[cle]])) cache[[cle]] <- .sommets_ligne(g[[li]])
    cache[[cle]]
  }
  xy <- t(vapply(seq_along(idx), function(i) {
    .interp_le_long(coords_ligne(idx[i]), dist_abs[i])
  }, numeric(2)))
  as.numeric(terra::extract(mnt, xy)[, 1])
}

# Points candidats le long de chaque troncon, un tous les `espacement_m` au plus
# (au moins un par troncon, au milieu, quelle que soit sa longueur). On garde
# l'abscisse curviligne : la pente en long se mesure le long de la ligne.
#
# Interpolation de coordonnees (pas de `sf::st_line_sample` ni `st_length` par
# ligne, tous deux re-parsant le CRS -- meme piege que `.altitude_sur_ligne`).
# Les points sont batis en UN SEUL `st_as_sf` (un parse de CRS au lieu de N).
.points_le_long <- function(des, espacement_m) {
  g <- sf::st_geometry(des)
  crs <- sf::st_crs(g)
  attrs <- sf::st_drop_geometry(des)

  rows <- lapply(seq_along(g), function(i) {
    c <- .sommets_ligne(g[[i]])
    k <- max(1L, floor(c$tot / espacement_m))
    frac <- if (k == 1L) 0.5 else seq(0.5 / k, 1 - 0.5 / k, length.out = k)
    abscisse <- frac * c$tot
    xy <- t(vapply(abscisse, function(d) .interp_le_long(c, d), numeric(2)))
    cbind(
      data.frame(.ligne = i, .abscisse = abscisse, .longueur = c$tot),
      attrs[rep(i, k), , drop = FALSE],
      x = xy[, 1], y = xy[, 2]
    )
  })
  df <- do.call(rbind, rows)
  sf::st_as_sf(df, coords = c("x", "y"), crs = crs)
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
