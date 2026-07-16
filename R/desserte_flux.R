# Lot 17 : flux de bois & typage des routes. Coiffe le reseau (Lot 16) d'un
# graphe topologique, puis accumule le volume et type les troncons. Portage de
# ForestRoadNetwork (Klemet, `woodFluxInNetwork_algorithm.py`,
# `RoadTypeDetermination_algorithm.py`, GPL v3). Lot R pur -- pas de Rust.
# 17a : vectorisation topologique du reseau -> graphe.
#
# Choix d'implementation : graphe natif leger (tables noeuds/troncons + `sf`)
# plutot que `sfnetworks`/`igraph`. Le reseau vit sur la grille raster, donc les
# indices de cellule (`terra::cellFromXY`) servent d'identifiants de noeud
# exacts (cellules partagees -> meme noeud, sans collage flottant), et le reseau
# est arborescent (le flux s'accumule en sous-arbre). Cela evite une dependance
# compilee lourde, conformement au caractere "R pur" du lot.

#' Vectorise a forest-road network into a topological graph
#'
#' Turns the raster/polyline network of a `foretaccess_reseau` (Lot 16) into a
#' clean node/edge graph: raster cells are canonical node ids (shared cells ->
#' shared nodes), fine segments are contracted along degree-2 chains into
#' `troncons` (edges) between the remarkable nodes (outlets, junctions of degree
#' >= 3, leaves of degree 1). This is the graph the wood-flux (Lot 17b) and road
#' typing (Lot 17c) operate on.
#'
#' @param reseau A `foretaccess_reseau` object (Lot 16).
#' @return A `foretaccess_reseau_graphe` object: `noeuds` (an `sf` POINT with
#'   `id`, `cell`, `degre`, `type` in outlet/junction/leaf), `troncons` (an `sf`
#'   LINESTRING with `id`, `de`, `vers` node ids and `longueur` in m),
#'   `exutoires` (outlet node ids) and the recall of the grid.
#' @export
vectoriser_reseau <- function(reseau) {
  checkmate::assert_class(reseau, "foretaccess_reseau")
  grille <- reseau$reseau
  crs <- sf::st_crs(reseau$lignes)

  # Cellules du reseau existant : exutoires potentiels (raccords au principal).
  net_r <- terra::rasterize(terra::vect(reseau$desserte), grille, field = 1,
                            background = NA, touches = TRUE)
  exutoire_cells <- which(!is.na(terra::values(net_r)))

  # Aretes fines : segments entre cellules consecutives de chaque route.
  fines <- .graphe_aretes_fines(reseau$lignes, grille)
  if (nrow(fines) == 0) {
    cli::cli_abort("Le reseau ne contient aucune route a vectoriser.")
  }

  # Contraction des chaines de degre 2 -> troncons entre noeuds remarquables.
  g <- .graphe_contracter(fines, exutoire_cells)

  # Table des noeuds remarquables -> sf POINT.
  rnodes <- g$noeuds
  node_id <- stats::setNames(seq_along(rnodes), rnodes)
  xy_n <- terra::xyFromCell(grille, rnodes)
  is_exu <- rnodes %in% exutoire_cells
  type <- ifelse(is_exu, "exutoire",
                 ifelse(g$degre >= 3, "jonction",
                        ifelse(g$degre == 1, "feuille", "passage")))
  noeuds <- sf::st_sf(
    id = unname(node_id), cell = rnodes, degre = unname(g$degre), type = type,
    geometry = sf::st_sfc(
      lapply(seq_len(nrow(xy_n)), function(i) sf::st_point(xy_n[i, ])), crs = crs
    )
  )

  # Table des troncons -> sf LINESTRING (geometrie complete via cellules).
  geoms <- lapply(g$troncons, function(t) {
    p <- terra::xyFromCell(grille, t$cells)
    if (nrow(p) == 1L) p <- rbind(p, p)
    sf::st_linestring(p)
  })
  de <- vapply(g$troncons, function(t) t$cells[1], numeric(1))
  vers <- vapply(g$troncons, function(t) t$cells[length(t$cells)], numeric(1))
  troncons <- sf::st_sf(
    id = seq_along(g$troncons),
    de = unname(node_id[as.character(de)]),
    vers = unname(node_id[as.character(vers)]),
    longueur = vapply(g$troncons, function(t) t$longueur, numeric(1)),
    geometry = sf::st_sfc(geoms, crs = crs)
  )

  structure(
    list(
      noeuds = noeuds,
      troncons = troncons,
      exutoires = noeuds$id[noeuds$type == "exutoire"],
      grille = terra::rast(grille)
    ),
    class = "foretaccess_reseau_graphe"
  )
}

# --- Helpers 17a -------------------------------------------------------------

# Aretes fines uniques (indices de cellule, a < b) + longueur planimetrique du
# segment entre les centres des deux cellules.
.graphe_aretes_fines <- function(lignes, grille) {
  vide <- data.frame(a = integer(0), b = integer(0), longueur = numeric(0))
  if (nrow(lignes) == 0) {
    return(vide)
  }
  edges <- list()
  for (i in seq_len(nrow(lignes))) {
    xy <- sf::st_coordinates(sf::st_geometry(lignes)[[i]])
    xy <- xy[, c(1, 2), drop = FALSE]
    cells <- terra::cellFromXY(grille, xy)
    cells <- cells[!is.na(cells)]
    if (length(cells) < 2L) next
    # Supprime les repetitions consecutives (sauts du voisinage disque).
    keep <- c(TRUE, cells[-1L] != cells[-length(cells)])
    cells <- cells[keep]
    if (length(cells) < 2L) next
    for (k in seq_len(length(cells) - 1L)) {
      a <- cells[k]
      b <- cells[k + 1L]
      edges[[length(edges) + 1L]] <- c(min(a, b), max(a, b))
    }
  }
  if (length(edges) == 0L) {
    return(vide)
  }
  m <- unique(do.call(rbind, edges))
  ca <- terra::xyFromCell(grille, m[, 1])
  cb <- terra::xyFromCell(grille, m[, 2])
  data.frame(
    a = m[, 1], b = m[, 2],
    longueur = sqrt((ca[, 1] - cb[, 1])^2 + (ca[, 2] - cb[, 2])^2)
  )
}

# Contracte les chaines de degre 2 en troncons entre noeuds remarquables.
# Renvoie : `noeuds` (cellules remarquables), `degre` (nomme par cellule) et
# `troncons` (liste de list(cells, longueur)).
.graphe_contracter <- function(fines, exutoire_cells) {
  nodes <- sort(unique(c(fines$a, fines$b)))
  # Adjacence : pour chaque cellule, data.frame(nb, eid).
  inc <- data.frame(
    from = c(fines$a, fines$b),
    nb = c(fines$b, fines$a),
    eid = rep(seq_len(nrow(fines)), 2L)
  )
  adj <- split(inc[, c("nb", "eid")], inc$from)
  deg <- vapply(nodes, function(c) nrow(adj[[as.character(c)]]), integer(1))
  names(deg) <- as.character(nodes)
  is_exu <- nodes %in% exutoire_cells
  names(is_exu) <- as.character(nodes)
  # Noeud remarquable : degre != 2, ou situe sur le reseau existant (exutoire).
  remark <- (deg != 2L) | is_exu

  visited <- logical(nrow(fines))
  troncons <- list()
  for (r in nodes[remark]) {
    ar <- adj[[as.character(r)]]
    for (row in seq_len(nrow(ar))) {
      if (visited[ar$eid[row]]) next
      cells <- r
      len_tot <- 0
      cur <- ar$nb[row]
      eid <- ar$eid[row]
      repeat {
        visited[eid] <- TRUE
        len_tot <- len_tot + fines$longueur[eid]
        cells <- c(cells, cur)
        if (remark[as.character(cur)]) break
        # Cellule de passage (degre 2) : poursuivre vers l'autre voisin.
        a2 <- adj[[as.character(cur)]]
        nxt <- which(a2$eid != eid)[1]
        eid <- a2$eid[nxt]
        cur <- a2$nb[nxt]
      }
      troncons[[length(troncons) + 1L]] <- list(cells = cells, longueur = len_tot)
    }
  }
  list(noeuds = nodes[remark], degre = deg[remark], troncons = troncons)
}

#' @export
print.foretaccess_reseau_graphe <- function(x, ...) {
  cli::cli_h1("Graphe du reseau de desserte")
  cli::cli_text("Noeuds : {nrow(x$noeuds)} (dont {length(x$exutoires)} exutoire{?s})")
  cli::cli_text("Troncons : {nrow(x$troncons)}")
  cli::cli_text("Longueur totale : {round(sum(x$troncons$longueur), 1)} m")
  invisible(x)
}
