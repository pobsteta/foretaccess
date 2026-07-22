# Lot 16 : reseau de desserte multi-cibles (MTAP). Coiffe le solveur de trace du
# Lot 15 d'une couche reseau (portage de ForestRoadNetwork, Klemet, GPL v3).
# 16a : orchestration glouton (ordre heuristique + reutilisation), noyau Rust
# `desserte_reseau` (boucle MTAP->STAP, table de voisinage batie une fois).

#' Design a forest-road network serving several parcels
#'
#' Builds a road network connecting N parcels to an existing road network, at
#' minimum cumulated construction cost, by the greedy MTAP heuristic: parcels are
#' ordered, then each is connected to the current network with the Lot 15
#' constrained solver, the new road growing the network for later parcels (reuse
#' -> tree). A parcel cell already within `skidding_m` of a road needs no road.
#'
#' @param pre A `foretaccess_preprocessing` object (DEM, terrain slope).
#' @param cout A `foretaccess_cout_construction` object (Lot 14): crossability.
#' @param parcelles An `sf` POLYGON of the areas to serve.
#' @param desserte_existante An `sf` LINESTRING of the network to connect to.
#' @param heuristique Ordering of parcels: `"plus_proche"` (closest first),
#'   `"plus_gros_volume"` (largest volume first) or `"aleatoire"` (random).
#' @param skidding_m Skidding distance (m): a parcel cell within it of a road is
#'   served without building a road.
#' @param volume_champ Optional name of the parcel volume column (for
#'   `"plus_gros_volume"`); each cell inherits its parcel volume.
#' @param pondere_cout If `TRUE`, weights the trace by the Lot 14 construction
#'   cost surface (`cout$cout`, euros/m) instead of pure geometric distance; the
#'   trace then minimises monetary cost. Default `FALSE` (SylvaRoad behaviour).
#' @param config A `foretaccess_config`; the solver settings live in
#'   `config$desserte$trace`.
#' @param graine Optional integer seed for the `"aleatoire"` ordering.
#' @return A `foretaccess_reseau` object: `lignes` (an `sf` LINESTRING of the
#'   created roads, one feature per road, with creation `ordre`, `cout` and
#'   planimetric `longueur` in m), `reseau` (a `SpatRaster` of the whole
#'   network, for Lot 17), `desserte` (the existing network, kept for the Lot 17
#'   graph), `cout` (total), `connexe` and `raccorde` (two connectivity flags,
#'   see *Connectivity* below), `desservies` (a logical, one per parcel, CA-16.1)
#'   and the recall of the `mode` and `heuristique`.
#'
#' @section Connectivity:
#' Two booleans, with **different** meanings -- read the right one:
#' * **`connexe`** -- does the *whole* raster network (existing roads + created
#'   roads) form a **single** 8-connected component (CA-16.5)? This is dominated
#'   by the **existing** network's own fragmentation: a real reference network is
#'   thousands of segments that do not touch at grid resolution, so `connexe` is
#'   almost always `FALSE` on real data. **A `FALSE` here does *not* mean a
#'   created road dangles** -- it usually just reflects a fragmented input.
#' * **`raccorde`** -- do the created roads add **no new** connected component
#'   relative to the existing network alone? `TRUE` iff every created road
#'   attaches to the existing network (directly or through another created road);
#'   a road left dangling would raise the component count. This is the flag that
#'   answers *"is every road I built actually connected?"* -- the one to surface
#'   as a quality badge, not `connexe`.
#' @param mode Construction mode: `"glouton"` (greedy MTAP->STAP, default) or
#'   `"steiner"` (minimum-spanning-tree approximation over the terminals, a
#'   quality alternative at the cost of N^2 traces).
#' @rdname reseau_desserte
#' @export
reseau_desserte <- function(pre, cout, parcelles, desserte_existante,
                            heuristique = c("plus_proche", "plus_gros_volume", "aleatoire"),
                            mode = c("glouton", "steiner"),
                            skidding_m = 0, volume_champ = NULL, pondere_cout = FALSE,
                            config = foretaccess_config(), graine = NULL) {
  heuristique <- match.arg(heuristique)
  mode <- match.arg(mode)
  validate_config(config)

  ctx <- .reseau_preparer(pre, cout, parcelles, desserte_existante, config, pondere_cout)
  res <- if (mode == "steiner") {
    .reseau_steiner(ctx, parcelles)
  } else {
    .reseau_glouton(ctx, parcelles, heuristique, skidding_m, volume_champ, graine)
  }

  .reseau_assembler(res$paths, res$costs, ctx, desserte_existante, parcelles,
                    skidding_m, heuristique, mode, config)
}

# Preparation commune (Lots 16 et 18) : grilles aplaties, reseau existant
# rasterise, dimensions. Renvoie le contexte partage par les modes/strategies.
.reseau_preparer <- function(pre, cout, parcelles, desserte_existante, config,
                             pondere_cout = FALSE) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  checkmate::assert_class(cout, "foretaccess_cout_construction")
  tr <- config$desserte$trace
  grille <- pre$mnt
  road_r <- terra::rasterize(terra::vect(desserte_existante), grille, field = 1, background = NA)
  net_cells1 <- which(!is.na(terra::values(road_r)))
  if (length(net_cells1) == 0) {
    cli::cli_abort("{.arg desserte_existante} ne couvre aucune cellule de la grille.")
  }
  if (nrow(parcelles) == 0) {
    cli::cli_abort("{.arg parcelles} est vide.")
  }
  list(
    g = .desserte_grilles(pre, cout, tr), grille = grille,
    nr = terra::nrow(grille), nc = terra::ncol(grille), csize = terra::res(grille)[1],
    tr = tr, road_r = road_r, net_cells1 = net_cells1,
    cost = .desserte_grille_cout(cout, grille, pondere_cout)
  )
}

# Grille de coût €/m consommee par le solveur (pondération monetaire du trace).
# `pondere_cout = FALSE` -> grille neutre (1.0) = trace purement geometrique
# (SylvaRoad). Sinon, la surface `cout` €/m du Lot 14 (les valeurs non finies ou
# <= 0 sont neutralisees cote Rust ; les cellules bloquees ne sont jamais lues).
.desserte_grille_cout <- function(cout, grille, pondere_cout) {
  if (!isTRUE(pondere_cout)) {
    return(rep(1, terra::ncell(grille)))
  }
  as.numeric(terra::values(cout$cout))
}

# Assemblage de l'objet `foretaccess_reseau` a partir des chemins/couts retenus
# (partage par le glouton, le Steiner et l'optimiseur du Lot 18).
.reseau_assembler <- function(paths, costs, ctx, desserte_existante, parcelles,
                              skidding_m, heuristique, mode, config) {
  grille <- ctx$grille
  crs_grille <- sf::st_crs(terra::crs(grille))
  lignes <- .desserte_paths_en_sf(paths, costs, grille, crs_grille)

  # Raster du reseau complet (existant + routes creees), pour le Lot 17. Le
  # voisinage disque du solveur avance par sauts : on rasterise les *geometries*
  # (routes creees + reseau existant, `touches`) pour un reseau continu, sans trous.
  reseau_r <- terra::rast(grille)
  terra::values(reseau_r) <- 0
  names(reseau_r) <- "reseau"
  reseau_r[ctx$net_cells1] <- 1
  geoms_reseau <- if (nrow(lignes) > 0) {
    c(sf::st_geometry(lignes), sf::st_geometry(desserte_existante))
  } else {
    sf::st_geometry(desserte_existante)
  }
  trace_r <- terra::rasterize(terra::vect(geoms_reseau), grille, field = 1,
                              background = NA, touches = TRUE)
  reseau_r[which(!is.na(terra::values(trace_r)))] <- 1

  # Raster du reseau EXISTANT seul (routes creees exclues), pour `raccorde` : on
  # veut savoir si les routes creees s'accrochent bien a l'existant, sans se
  # laisser dominer par la fragmentation propre de l'existant (cf. `raccorde`).
  existant_r <- terra::rast(grille)
  terra::values(existant_r) <- 0
  existant_r[ctx$net_cells1] <- 1
  trace_ex <- terra::rasterize(
    terra::vect(sf::st_geometry(desserte_existante)), grille,
    field = 1, background = NA, touches = TRUE
  )
  existant_r[which(!is.na(terra::values(trace_ex)))] <- 1

  # Connexite (CA-16.5) et desserte de chaque parcelle (CA-16.1).
  structure(
    list(
      lignes = lignes,
      reseau = reseau_r,
      desserte = sf::st_sf(geometry = sf::st_geometry(desserte_existante)),
      cout = sum(costs),
      heuristique = heuristique,
      mode = mode,
      connexe = .reseau_connexe(reseau_r),
      raccorde = .reseau_raccorde(reseau_r, existant_r),
      desservies = .reseau_desservies(parcelles, reseau_r, grille, skidding_m),
      config = config
    ),
    class = "foretaccess_reseau"
  )
}

# Parametres du solveur (bloc commun aux bindings `desserte_reseau`/`desserte_trace`).
.desserte_solver_params <- function(tr, csize) {
  list(
    csize = csize,
    min_slope = tr$pente_long_min, max_slope = tr$pente_long_max,
    penalty_xy = tr$penalty_xy, penalty_z = tr$penalty_z,
    max_diff_z = tr$max_diff_z_m, d_neighborhood = tr$d_neighborhood_m,
    angle_hairpin = tr$angle_epingle, lmax_ab_sl = tr$lmax_devers_m,
    radius = tr$rayon_braquage_m, prop_sl_max = tr$prop_devers_max,
    max_slope_hairpin = tr$max_slope_hairpin, tal = tr$tal, modhair = tr$modhair
  )
}

# Mode glouton (MTAP->STAP, Lot 16a) : boucle en Rust (`desserte_reseau`).
.reseau_glouton <- function(ctx, parcelles, heuristique, skidding_m, volume_champ, graine) {
  parc_ids <- .desserte_cellules_parcelles(parcelles, ctx$grille, volume_champ)
  if (length(parc_ids$cells) == 0) {
    cli::cli_abort("{.arg parcelles} ne couvre aucune cellule de la grille.")
  }
  ordre <- .desserte_ordre(parc_ids, ctx$road_r, heuristique, graine)
  sources0 <- as.integer(parc_ids$cells[ordre] - 1L)
  res <- do.call(desserte_reseau, c(
    list(alt = ctx$g$alt, obs = ctx$g$obs, obs2 = ctx$g$obs2,
         local_slope = ctx$g$local_slope, zone = ctx$g$zone,
         nr = ctx$nr, nc = ctx$nc, sources = sources0,
         network0 = as.integer(ctx$net_cells1 - 1L), skidding = skidding_m),
    .desserte_solver_params(ctx$tr, ctx$csize), list(cost = ctx$cost)
  ))
  list(paths = res$paths, costs = res$costs)
}

# Mode steiner (Lot 16b) : arbre couvrant de poids minimal (approximation de
# Steiner) sur le graphe des terminaux -- reseau existant + un noeud d'acces par
# parcelle. Chaque arete est un plus court chemin contraint du Lot 15 : N traces
# reseau<->parcelle (`desserte_reseau`, source unique) + N(N-1)/2 traces
# parcelle<->parcelle (`desserte_trace`). Prim retient l'arbre de cout minimal.
.reseau_steiner <- function(ctx, parcelles) {
  grille <- ctx$grille
  n_parc <- nrow(parcelles)

  v <- terra::vect(parcelles)
  v$pid_steiner <- seq_len(n_parc)
  pid_vals <- terra::values(
    terra::rasterize(v, grille, field = "pid_steiner", background = NA)
  )[, 1]
  dist_vals <- terra::values(terra::distance(ctx$road_r))[, 1]

  # Noeud d'acces de chaque parcelle : cellule la plus proche du reseau existant.
  acces <- integer(0)
  for (p in seq_len(n_parc)) {
    cp <- which(pid_vals == p)
    if (length(cp) == 0) next
    acces <- c(acces, cp[which.min(dist_vals[cp])])
  }
  n <- length(acces)
  if (n == 0) {
    cli::cli_abort("{.arg parcelles} ne couvre aucune cellule de la grille.")
  }

  params <- .desserte_solver_params(ctx$tr, ctx$csize)
  base <- list(alt = ctx$g$alt, obs = ctx$g$obs, obs2 = ctx$g$obs2,
               local_slope = ctx$g$local_slope, zone = ctx$g$zone,
               nr = ctx$nr, nc = ctx$nc)
  params <- c(params, list(cost = ctx$cost)) # ponderation monetaire (Lot 14)

  # Graphe des terminaux : 1 = reseau, 2..n+1 = parcelles. `cost` symetrique ;
  # `paths` indexe par cle(a, b) = (a - 1) * nt + b (a, b 1-based).
  nt <- n + 1L
  cost <- matrix(Inf, nt, nt)
  paths <- vector("list", nt * nt)
  key <- function(a, b) (a - 1L) * nt + b

  # Aretes reseau <-> parcelle (source unique vers l'ensemble reseau).
  for (p in seq_len(n)) {
    r <- do.call(desserte_reseau, c(base, list(
      sources = as.integer(acces[p] - 1L),
      network0 = as.integer(ctx$net_cells1 - 1L), skidding = 0), params))
    if (length(r$paths) >= 1L && length(r$paths[[1]]) > 0L) {
      cost[1, p + 1L] <- cost[p + 1L, 1] <- r$costs[1]
      paths[[key(1L, p + 1L)]] <- r$paths[[1]]
    }
  }
  # Aretes parcelle <-> parcelle (tracé waypoint a waypoint).
  if (n >= 2L) {
    for (i in seq_len(n - 1L)) {
      for (j in (i + 1L):n) {
        tr <- do.call(desserte_trace, c(base, list(
          waypoints = as.integer(c(acces[i], acces[j]) - 1L), bufgoal = 0), params))
        if (isTRUE(tr$feasible) && length(tr$path) > 0L) {
          cost[i + 1L, j + 1L] <- cost[j + 1L, i + 1L] <- tr$cost
          paths[[key(i + 1L, j + 1L)]] <- tr$path
        }
      }
    }
  }

  # Arbre couvrant de poids minimal (Prim) enracine sur le reseau existant. Prim
  # ajoute chaque terminal apres son parent : l'ordre des aretes est donc un
  # parcours racine -> feuilles valide (chaque enfant se greffe sur un ancetre
  # deja materialise).
  mst <- .steiner_prim(cost)

  # Materialisation avec reutilisation : chaque parcelle, dans l'ordre de l'arbre,
  # se raccorde au reseau *courant* (existant + tronçons deja materialises). Cette
  # etape fusionne les cellules partagees (coût abaissé a ~0, comme le glouton) et
  # elague les branches redondantes -- une greffe mi-parcours plutot qu'un doublon.
  net_courant <- ctx$net_cells1
  sel_paths <- list()
  sel_costs <- numeric(0)
  for (e in mst) {
    p <- e[2] - 1L # terminal enfant -> index de parcelle (terminal 1 = reseau)
    r <- do.call(desserte_reseau, c(base, list(
      sources = as.integer(acces[p] - 1L),
      network0 = as.integer(net_courant - 1L), skidding = 0), params))
    if (length(r$paths) >= 1L && length(r$paths[[1]]) > 0L) {
      pth <- r$paths[[1]]
      sel_paths[[length(sel_paths) + 1L]] <- pth
      sel_costs <- c(sel_costs, r$costs[1])
      net_courant <- unique(c(net_courant, pth))
    }
  }
  list(paths = sel_paths, costs = sel_costs)
}

# Prim : arbre couvrant de poids minimal enracine sur le terminal 1 (reseau).
# Renvoie la liste des aretes retenues c(a, b) (indices 1-based). Les terminaux
# inaccessibles (cout infini) sont laisses de cote.
.steiner_prim <- function(cost) {
  nt <- nrow(cost)
  in_tree <- rep(FALSE, nt)
  in_tree[1] <- TRUE
  best <- cost[1, ]
  best[1] <- Inf
  from <- rep(1L, nt)
  edges <- list()
  repeat {
    cand <- which(!in_tree)
    if (length(cand) == 0) break
    k <- cand[which.min(best[cand])]
    if (!is.finite(best[k])) break # terminaux restants non raccordables
    in_tree[k] <- TRUE
    edges[[length(edges) + 1L]] <- c(from[k], k)
    rest <- which(!in_tree)
    if (length(rest) > 0) {
      newc <- cost[k, rest]
      upd <- newc < best[rest]
      best[rest[upd]] <- newc[upd]
      from[rest[upd]] <- k
    }
  }
  edges
}

# --- Helpers -----------------------------------------------------------------

# Grilles aplaties du solveur (MNT, obstacles, devers, fraction locale, zone).
# Partage la meme logique que `tracer_desserte` (Lot 15c).
.desserte_grilles <- function(pre, cout, tr) {
  grille <- pre$mnt
  csize <- terra::res(grille)[1]
  slope <- as.numeric(terra::values(pre$slope_pct))
  fr <- as.numeric(terra::values(cout$franchissable))
  bloque <- is.na(fr) | fr <= 0
  list(
    alt = as.numeric(terra::values(grille)),
    obs = as.integer(bloque),
    zone = as.integer(!bloque),
    obs2 = as.integer(!is.na(slope) & slope > tr$trans_slope_all),
    local_slope = .desserte_local_slope(pre$slope_pct, tr$trans_slope_hairpin,
                                        tr$rayon_braquage_m, csize)
  )
}

# Cellules (1-based) couvertes par les parcelles + volume par cellule.
.desserte_cellules_parcelles <- function(parcelles, grille, volume_champ) {
  v <- terra::vect(parcelles)
  parc_r <- terra::rasterize(v, grille, field = 1, background = NA)
  cells <- which(!is.na(terra::values(parc_r)))
  vol <- rep(1, length(cells))
  if (!is.null(volume_champ)) {
    checkmate::assert_choice(volume_champ, names(parcelles))
    vol_r <- terra::rasterize(v, grille, field = volume_champ, background = NA)
    vol <- as.numeric(terra::values(vol_r))[cells]
    vol[is.na(vol)] <- 0
  }
  list(cells = cells, volume = vol)
}

# Ordre d'insertion des cellules de parcelle selon l'heuristique.
.desserte_ordre <- function(parc_ids, road_r, heuristique, graine) {
  cells <- parc_ids$cells
  n <- length(cells)
  if (heuristique == "aleatoire") {
    if (is.null(graine)) {
      return(sample.int(n))
    }
    # Tirage reproductible sans polluer le RNG global.
    if (exists(".Random.seed", envir = globalenv())) {
      old <- get(".Random.seed", envir = globalenv())
      on.exit(assign(".Random.seed", old, envir = globalenv()), add = TRUE)
    }
    set.seed(graine)
    return(sample.int(n))
  }
  # Distance de chaque cellule au reseau existant (tie-break / critere principal).
  dist_r <- terra::distance(road_r)
  d <- as.numeric(terra::values(dist_r))[cells]
  if (heuristique == "plus_gros_volume") {
    order(-parc_ids$volume, d) # plus gros volume d'abord, puis plus proche
  } else {
    order(d) # plus proche d'abord
  }
}

# Liste de chemins (cellules 1-based) -> sf LINESTRING (une feature par route).
.desserte_paths_en_sf <- function(paths, costs, grille, crs_grille) {
  if (length(paths) == 0) {
    return(sf::st_sf(
      ordre = integer(0), cout = numeric(0), longueur = numeric(0),
      geometry = sf::st_sfc(crs = crs_grille)
    ))
  }
  geoms <- lapply(paths, function(cells) {
    xy <- terra::xyFromCell(grille, cells)
    if (nrow(xy) == 1L) xy <- rbind(xy, xy)
    sf::st_linestring(xy)
  })
  out <- sf::st_sf(
    ordre = seq_along(paths),
    cout = costs,
    geometry = sf::st_sfc(geoms, crs = crs_grille)
  )
  out$longueur <- as.numeric(sf::st_length(out)) # metres (CRS projete)
  out[, c("ordre", "cout", "longueur", attr(out, "sf_column"))]
}

# Nombre de composantes 8-connexes d'un raster de reseau (cellules > 0).
.n_composantes <- function(r) {
  bin <- terra::ifel(r > 0, 1L, NA)
  if (all(is.na(terra::values(bin)))) {
    return(0L)
  }
  pat <- terra::patches(bin, directions = 8, zeroAsNA = TRUE)
  length(unique(stats::na.omit(terra::values(pat)[, 1])))
}

# Connexite (CA-16.5) : le reseau COMPLET (existant + routes creees) forme-t-il
# une seule composante 8-connexe ? ATTENTION a la lecture (cf. `raccorde` et la
# doc de reseau_desserte) : ce booleen est domine par la fragmentation propre du
# reseau EXISTANT. Sur une desserte reelle (des milliers de troncons qui ne se
# touchent pas a la resolution de la grille), il vaut presque toujours FALSE --
# ce n'est PAS le signe qu'une route creee pend dans le vide.
.reseau_connexe <- function(reseau_r) {
  .n_composantes(reseau_r) <= 1L
}

# Raccordement (le booleen utile pour la conception d'acces) : les routes creees
# ajoutent-elles zero nouvelle composante par rapport au reseau existant seul ?
# Vrai <=> aucune route creee n'est isolee de l'existant (chacune s'y accroche,
# directement ou via une autre route creee). Une route qui pendrait dans le vide
# ferait AUGMENTER le compte de composantes. Insensible a la fragmentation de
# l'existant, contrairement a `connexe`.
.reseau_raccorde <- function(reseau_r, existant_r) {
  .n_composantes(reseau_r) <= .n_composantes(existant_r)
}

# Desserte (CA-16.1) : chaque parcelle a-t-elle au moins une cellule sur le
# reseau ou a distance de debardage d'une route ?
.reseau_desservies <- function(parcelles, reseau_r, grille, skidding_m) {
  v <- terra::vect(parcelles)
  v$pid_serv <- seq_len(nrow(parcelles))
  pid <- terra::values(
    terra::rasterize(v, grille, field = "pid_serv", background = NA)
  )[, 1]
  net_bin <- terra::ifel(reseau_r > 0, 1L, NA)
  dist <- terra::values(terra::distance(net_bin))[, 1]
  vapply(seq_len(nrow(parcelles)), function(p) {
    cp <- which(pid == p)
    length(cp) > 0L && min(dist[cp]) <= skidding_m + 1e-9
  }, logical(1))
}

#' @export
print.foretaccess_reseau <- function(x, ...) {
  cli::cli_h1("Reseau de desserte")
  if (!is.null(x$strategie)) {
    cli::cli_text("Strategie : {.val {x$strategie}} ({length(x$journal)} essai{?s})")
  }
  cli::cli_text("Mode : {.val {x$mode}}")
  cli::cli_text("Heuristique : {.val {x$heuristique}}")
  cli::cli_text("Routes creees : {nrow(x$lignes)}")
  cli::cli_text("Parcelles desservies : {sum(x$desservies)}/{length(x$desservies)}")
  cli::cli_text("Routes creees raccordees : {ifelse(x$raccorde %||% NA, 'oui', 'non')}")
  cli::cli_text("Reseau global connexe : {ifelse(x$connexe, 'oui', 'non')} \\
                 {.dim (souvent 'non' : existant fragmente -- voir ?reseau_desserte)}")
  cli::cli_text("Cout total : {round(x$cout, 1)}")
  invisible(x)
}
