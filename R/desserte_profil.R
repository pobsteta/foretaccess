# Profil en travers d'un troncon de desserte, au point clique (spec 030).
#
# Ce que la fonction ajoute au paquet, et pourquoi elle ne pouvait pas etre un
# assemblage : `dessertR::dsr_profils()` echantillonne le MNT, donc une SURFACE
# INTERPOLEE. La planche visee montre le NUAGE -- un point par echo, colore par
# classe et par intensite -- et c'est precisement ce que le MNT a efface : les
# echos de vegetation basse qui bordent l'emprise, les points sol epars sous
# couvert qui disent ou le MNT est une extrapolation. Il fallait donc une
# extraction de nuage, qu'aucun moteur n'exposait (dessertR lit le nuage, mais
# ne rend que des rasters : `dsr_layers_pc()`).
#
# Le reste tient en trois regles :
#
#   1. AUCUN GRAPHIQUE. La fonction rend des donnees derivees, l'appelant trace
#      (regle 1 de nemetonshiny : pas de logique metier cote app, et pas de
#      presentation cote coeur).
#   2. COUT BORNE. Un clic doit rendre en quelques secondes : on ne lit jamais
#      une dalle entiere, on lit un RECTANGLE de `epaisseur_m` x 2 `demi_largeur`
#      autour de la station, apres avoir ecarte les dalles par leur entete.
#   3. NULL FRANC. Pas de troncon, pas de lecteur, pas de dalle, coupe vide ->
#      `NULL`, jamais une liste a moitie remplie ni une erreur. Le message `cli`
#      dit lequel des cas.
#
# Le referentiel vertical, qui commande toute la lecture de la planche : `z = 0`
# est le sol A L'AXE (altitude du MNT a la station), PAS le sol sous chaque
# point. Normaliser point par point (ce que fait `lasR::normalize()`) aplatirait
# le bombement de la chaussee -- or c'est exactement ce que la parabole ajuste.
# La hauteur au-dessus du sol reste disponible par point (`hauteur_sol`), elle
# sert aux familles de bords qui parlent de vegetation.

.PKG_RLAS <- "rlas"
.MOTIF_LAS <- "\\.(las|laz)$"

# Cinq familles de bords, vocabulaire STABLE et anglais (cles techniques, jamais
# des libelles) : c'est l'app qui traduit. Definitions dans la doc de
# `profil_travers()` -- elles sont a nous, aucun moteur ne les fournissait.
.TYPES_BORDS <- c("drivable", "road", "right_of_way", "shoulder", "rescue")

.rlas_dispo <- function() requireNamespace(.PKG_RLAS, quietly = TRUE)

#' Cross-section of a road segment at a clicked point (spec 030)
#'
#' Returns everything needed to **draw** the cross-section of the nearest road
#' segment: the LiDAR points of a slice taken across the axis, the ground
#' profile, a fitted road crown, and five families of edges with their widths.
#' It draws nothing itself -- the caller does (no plotting in the core, no
#' business logic in the app).
#'
#' @details
#' **Vertical datum.** `z = 0` is the ground **at the axis** (the DTM elevation
#' at the station), not the ground under each point. Normalising point by point
#' would flatten the road crown, which is exactly what `ajustement` fits. Height
#' above the local ground is available per point as `hauteur_sol`.
#'
#' **The five edge families.** They are defined here, not by any engine
#' (`dsr_measure()` gives the drivable width, `dsr_emprise_certu()` a normative
#' footprint; neither yields the five). All are derived from *this* profile:
#'
#' * `road` -- the **platform** (road prism): the run around the axis where the
#'   ground stays within `tol_plateforme` of the plane fitted on the central
#'   window. It stops at the ditch, the cut slope or the fill toe.
#' * `drivable` -- the **carriageway**: the run where the ground stays within
#'   `tol_chaussee` of the fitted crown parabola, **clipped to `road`**. Clipping
#'   is what makes `drivable <= road` a property rather than a hope.
#' * `shoulder` -- what is left of the platform on each side, hence **two rows**
#'   (`cote` = `"gauche"` / `"droite"`), possibly of zero width.
#' * `rescue` -- the width usable by an **emergency vehicle**: grown outwards
#'   from `road` while the ground stays crossable (cross-slope under
#'   `pente_max`), then clipped to `right_of_way`. Neither the ditch, nor the
#'   cut slope, nor the undergrowth.
#' * `right_of_way` -- the cleared corridor: the run around the axis free of any
#'   echo in the **trunk band** (`h_obstacle` m above the ground), **unioned with
#'   `road`**.
#'
#' The four symmetric families are therefore **nested by construction**:
#' `drivable <= road <= rescue <= right_of_way`. It is a property of the code,
#' not a hope about the terrain.
#'
#' **Trunks, not canopy.** The corridor is read on the trunk band and not on the
#' canopy, and that is a measurement, not a preference: on the `dessertR` sample
#' tile (Lozère, closed high forest) the crowns close **over** a 3.6 m track, so
#' a *"no echo above 2 m"* rule returns a zero-width gap and a right of way equal
#' to the platform -- a family that no longer says anything. Trunks stand back:
#' 23 m of clear corridor at the very same station.
#'
#' **Cost.** Only a rectangle of `epaisseur_m` x 2 `demi_largeur` is read, and
#' only from the tiles whose LAS header meets it. A click reads a few thousand
#' points, not a tile.
#'
#' **Degraded modes all return `NULL`** -- never an error, never a half-filled
#' list: no segment within `tolerance_m`, no `rlas` (the point-cloud reader, a
#' `dessertR` dependency), no tile under the station, or an empty slice. The
#' `cli` message says which one.
#'
#' @param desserte Road network: path or `sf` of lines (BD TOPO, ideally the
#'   corrected/qualified one -- see [qualifier_desserte()]).
#' @param xy The clicked point: `numeric(2)` (x, y in `crs`) or an `sf`/`sfc`
#'   `POINT`.
#' @param las_source Airborne LiDAR: a directory, a vector of `.las`/`.laz`
#'   files, or a `dessertR` catalogue (column `laz`) -- same vocabulary as
#'   [qualifier_desserte()].
#' @param mnt Digital terrain model: `SpatRaster` or path, **1 m or finer**.
#' @param crs Target EPSG code. Default 2154.
#' @param tolerance_m Snapping radius (m): beyond it, no segment is deemed
#'   clicked. Default 25.
#' @param demi_largeur Half-width of the cross-section (m). Default 20.
#' @param epaisseur_m Thickness (m) of the slice taken **along** the axis. The
#'   points of the slice are projected onto the section plane; a thicker slice
#'   shows more points and more longitudinal blur. Default 2.
#' @param pas_travers Transverse sampling step (m) of the ground profile and of
#'   the occupancy bins. Default 0.25.
#' @param h_obstacle Height band (m) above ground read as **standing obstacles**
#'   (trunks, regrowth, blocks), for `right_of_way`. Default `c(0.5, 5)`.
#' @param pente_max Cross-slope (m/m) up to which the ground is deemed crossable,
#'   for `rescue`. Default 0.20.
#' @param tol_chaussee,tol_plateforme Vertical tolerances (m) of the `drivable`
#'   and `road` runs. Defaults 0.05 and 0.15.
#' @param cache_dir Directory for the per-click cache. Default `tempdir()`.
#' @return A `list`, or `NULL` (see Details). Elements:
#'
#'   * `troncon` -- `sf`, one row: the snapped segment with its attributes;
#'   * `station` -- `list`: `chainage_m` along the segment, `xy` of the point
#'     projected on the axis;
#'   * `points` -- `data.frame`, one LiDAR point per row: `x_travers` (m,
#'     **signed**, 0 = axis), `z` (m, 0 = ground at the axis), `intensite`,
#'     `sol` (logical), `classification`, plus `hauteur_sol` and `abscisse`
#'     (position along the axis within the slice);
#'   * `sol` -- `data.frame`: `x_travers`, `z` of the ground profile;
#'   * `ajustement` -- `list`: `a`, `b`, `c` of the crown parabola, `rmse`, `n`,
#'     `source` (`"points_sol"` or `"mnt"`), or `NULL` if unfittable;
#'   * `bords` -- `data.frame`, one row per edge family: `type` (one of
#'     `drivable`, `road`, `right_of_way`, `shoulder`, `rescue`), `cote`,
#'     `x_gauche`, `x_droite`, `largeur_m`;
#'   * `meta` -- `list`: `moteur`, `n_points`, `n_dalles`, `demi_largeur`,
#'     `epaisseur_m`, `pas_travers`, `crs`, `z_ref` (absolute elevation of
#'     `z = 0`), `tolerance_m`, `cache`.
#' @seealso [qualifier_desserte()] (the corrected network to feed it),
#'   [classer_desserte()], `specs/030`.
#' @export
#' @examples
#' \dontrun{
#' des <- acquire_desserte(aoi)
#' p <- profil_travers(des, c(937500, 6480000), "cache/lidar_nuage", mnt)
#' if (!is.null(p)) p$bords
#' }
profil_travers <- function(desserte, xy, las_source, mnt, crs = 2154,
                           tolerance_m = 25, demi_largeur = 20,
                           epaisseur_m = 2, pas_travers = 0.25,
                           h_obstacle = c(0.5, 5), pente_max = 0.20,
                           tol_chaussee = 0.05, tol_plateforme = 0.15,
                           cache_dir = tempdir()) {
  checkmate::assert_number(tolerance_m, lower = 0)
  checkmate::assert_number(demi_largeur, lower = 1)
  checkmate::assert_number(epaisseur_m, lower = 0)
  checkmate::assert_number(pas_travers, lower = 0.01, upper = demi_largeur)
  checkmate::assert_number(pente_max, lower = 0)
  checkmate::assert_numeric(h_obstacle, len = 2L, any.missing = FALSE,
    sorted = TRUE)

  pt <- .point_clique(xy, crs)
  # Le cache est indexe sur le CLIC, pas sur la station : c'est l'entree de
  # l'appel, et deux clics voisins n'ont aucune raison de partager un fichier.
  cle <- .cle_profil(pt, demi_largeur, epaisseur_m, pas_travers, tolerance_m,
    h_obstacle, pente_max, tol_chaussee, tol_plateforme)
  cache <- .profil_cache_lire(cache_dir, cle)
  if (!is.null(cache)) {
    return(cache)
  }

  des <- sf::st_zm(sf::st_as_sf(.as_vector(desserte, "desserte")), drop = TRUE)
  if (nrow(des) == 0) {
    cli::cli_abort("La couche {.arg desserte} est vide.")
  }
  mnt <- .as_raster(mnt, "mnt")

  # Pas de reprojection implicite (ADR-004) : un clic dans un autre systeme se
  # projette a des centaines de metres de la ou l'utilisateur a vise.
  if (!is.na(sf::st_crs(des)) && !is.na(sf::st_crs(pt)) &&
      sf::st_crs(des) != sf::st_crs(pt)) {
    cli::cli_abort(c(
      "Le CRS de {.arg xy} ne correspond pas a celui de {.arg desserte}.",
      "x" = "{.arg xy} : {.val {sf::st_crs(pt)$input}} ;
             {.arg desserte} : {.val {sf::st_crs(des)$input}}.",
      "i" = "Passer {.arg crs} = le code EPSG de la desserte."
    ))
  }

  troncon <- .accrocher_troncon(des, pt, tolerance_m)
  if (is.null(troncon)) {
    cli::cli_inform(c("i" = "Aucun troncon exploitable a moins de {tolerance_m} m
                             du point : pas de profil."))
    return(NULL)
  }

  coords <- sf::st_coordinates(sf::st_geometry(troncon))[, 1:2, drop = FALSE]
  st <- .station_sur_axe(coords, sf::st_coordinates(pt)[1, 1:2])
  # Tangente lissee sur +/- 5 m : la tangente du seul segment porteur suit les
  # zigzags de numerisation de la BD TOPO, et une normale fausse de 20 degres
  # elargit la coupe d'autant (largeurs surestimees de 6 %).
  tg <- .tangente_a_chainage(coords, st$chainage, base = 5)
  normale <- c(-tg[2], tg[1])

  z_ref <- .altitude(mnt, st$xy)
  if (!is.finite(z_ref)) {
    cli::cli_inform(c("i" = "MNT sans valeur a la station : pas de profil."))
    return(NULL)
  }

  fichiers <- .las_fichiers(las_source)
  bb <- .bbox_coupe(st$xy, tg, normale, demi_largeur, epaisseur_m)
  nuage <- .lire_nuage_rect(fichiers, bb)
  if (is.null(nuage)) {
    return(NULL)
  }

  pts <- .points_coupe(nuage, st$xy, tg, normale, demi_largeur, epaisseur_m, z_ref)
  if (nrow(pts) == 0) {
    cli::cli_inform(c("i" = "Coupe vide : aucun point du nuage dans la tranche
                             ({epaisseur_m} m) a cette station."))
    return(NULL)
  }

  sol <- .profil_sol(mnt, st$xy, normale, demi_largeur, pas_travers, z_ref)
  pts$hauteur_sol <- pts$z - .interpoler_sol(sol, pts$x_travers)

  bords <- .bords_profil(sol, pts, demi_largeur, pas_travers,
    h_obstacle = h_obstacle, pente_max = pente_max,
    tol_chaussee = tol_chaussee, tol_plateforme = tol_plateforme)
  ajust <- .ajustement_chaussee(sol, pts, bords)

  out <- list(
    troncon = troncon,
    station = list(chainage_m = st$chainage, xy = st$xy),
    points = pts,
    sol = sol,
    ajustement = ajust,
    bords = bords,
    meta = list(
      moteur = .PKG_RLAS, n_points = nrow(pts),
      n_dalles = attr(nuage, "n_dalles") %||% NA_integer_,
      demi_largeur = demi_largeur, epaisseur_m = epaisseur_m,
      pas_travers = pas_travers, crs = crs, z_ref = z_ref,
      tolerance_m = tolerance_m, cache = FALSE
    )
  )
  .profil_cache_ecrire(cache_dir, cle, out)
  out
}


# --- Entrees ----------------------------------------------------------------

# Le point clique, en sfc POINT. Accepte numeric(2) (l'app envoie des
# coordonnees, pas des objets) ou un sf/sfc POINT deja projete.
.point_clique <- function(xy, crs) {
  if (inherits(xy, c("sf", "sfc"))) {
    g <- sf::st_geometry(xy)
    if (length(g) != 1L || as.character(sf::st_geometry_type(g)) != "POINT") {
      cli::cli_abort("{.arg xy} doit etre un unique {.cls POINT}.")
    }
    return(g)
  }
  if (!is.numeric(xy) || length(xy) != 2L || anyNA(xy)) {
    cli::cli_abort(c(
      "{.arg xy} doit etre {.code numeric(2)} ou un {.cls POINT}.",
      "x" = "Recu : {.cls {class(xy)[1]}} de longueur {length(xy)}."
    ))
  }
  sf::st_sfc(sf::st_point(as.numeric(xy)), crs = crs)
}

# Fichiers LAS/LAZ d'une source : dossier(s), fichiers, ou catalogue dessertR
# (colonne `laz`). Meme vocabulaire que `qualifier_desserte()`.
.las_fichiers <- function(las_source) {
  if (is.null(las_source)) {
    return(character(0))
  }
  if (is.data.frame(las_source)) {
    las_source <- if ("laz" %in% names(las_source)) {
      as.character(las_source$laz)
    } else {
      character(0)
    }
  }
  if (!is.character(las_source) || !length(las_source)) {
    return(character(0))
  }
  f <- unlist(lapply(las_source, function(s) {
    if (dir.exists(s)) {
      list.files(s, pattern = .MOTIF_LAS, full.names = TRUE, recursive = TRUE,
        ignore.case = TRUE)
    } else {
      s
    }
  }), use.names = FALSE)
  f <- unique(f[file.exists(f) & grepl(.MOTIF_LAS, f, ignore.case = TRUE)])
  f
}


# --- Accrochage et station ---------------------------------------------------

# Troncon le plus proche du clic, en LINESTRING unique, ou NULL au-dela de la
# tolerance. `st_distance` sur toute la couche est acceptable : une desserte
# d'AOI tient en quelques milliers de lignes, et sf indexe.
.accrocher_troncon <- function(des, pt, tolerance_m) {
  d <- suppressWarnings(as.numeric(sf::st_distance(sf::st_geometry(des), pt)))
  d[!is.finite(d)] <- Inf
  i <- which.min(d)
  if (!length(i) || d[i] > tolerance_m) {
    return(NULL)
  }
  .troncon_linestring(des[i, ])
}

# Projection orthogonale du clic sur la polyligne : chainage (m depuis l'origine
# du troncon) et point projete. Segment par segment, sans dependance.
.station_sur_axe <- function(coords, xy) {
  n <- nrow(coords)
  if (n < 2L) {
    return(list(chainage = 0, xy = as.numeric(coords[1, ])))
  }
  ax <- coords[-n, 1]; ay <- coords[-n, 2]
  dx <- coords[-1, 1] - ax; dy <- coords[-1, 2] - ay
  len2 <- dx * dx + dy * dy
  len2[len2 == 0] <- .Machine$double.eps
  t <- ((xy[1] - ax) * dx + (xy[2] - ay) * dy) / len2
  t <- pmin(1, pmax(0, t))
  px <- ax + t * dx; py <- ay + t * dy
  d2 <- (px - xy[1])^2 + (py - xy[2])^2
  i <- which.min(d2)
  cum <- c(0, cumsum(sqrt(len2)))
  list(chainage = unname(cum[i] + t[i] * sqrt(len2[i])),
    xy = unname(c(px[i], py[i])))
}

# Point de la polyligne au chainage `s` (borne aux extremites).
.point_a_chainage <- function(coords, s) {
  n <- nrow(coords)
  if (n < 2L) {
    return(as.numeric(coords[1, ]))
  }
  seg <- sqrt(diff(coords[, 1])^2 + diff(coords[, 2])^2)
  cum <- c(0, cumsum(seg))
  s <- min(max(s, 0), cum[n])
  i <- max(1L, findInterval(s, cum, rightmost.closed = TRUE))
  t <- if (seg[i] > 0) (s - cum[i]) / seg[i] else 0
  c(coords[i, 1] + t * (coords[i + 1, 1] - coords[i, 1]),
    coords[i, 2] + t * (coords[i + 1, 2] - coords[i, 2]))
}

# Tangente unitaire au chainage `s`, prise entre s - base et s + base : lisse la
# quantification des sommets BD TOPO. Repli sur le segment porteur si le troncon
# est plus court que la base.
.tangente_a_chainage <- function(coords, s, base = 5) {
  long <- sum(sqrt(diff(coords[, 1])^2 + diff(coords[, 2])^2))
  b <- min(base, max(long / 2, 1e-6))
  a <- .point_a_chainage(coords, max(0, s - b))
  z <- .point_a_chainage(coords, min(long, s + b))
  v <- c(z[1] - a[1], z[2] - a[2])
  nv <- sqrt(sum(v^2))
  if (!is.finite(nv) || nv == 0) {
    v <- as.numeric(coords[nrow(coords), ] - coords[1, ])
    nv <- sqrt(sum(v^2))
  }
  if (!is.finite(nv) || nv == 0) c(1, 0) else v / nv
}

.altitude <- function(mnt, xy) {
  v <- tryCatch(
    terra::extract(mnt[[1]], matrix(xy, ncol = 2), method = "bilinear")[, 1],
    error = function(e) NA_real_
  )
  as.numeric(v)[1]
}


# --- Nuage -------------------------------------------------------------------

# Rectangle englobant de la coupe, en coordonnees terrain.
.bbox_coupe <- function(centre, tg, normale, demi_largeur, epaisseur_m) {
  e <- epaisseur_m / 2
  coins <- rbind(
    centre + demi_largeur * normale + e * tg,
    centre + demi_largeur * normale - e * tg,
    centre - demi_largeur * normale + e * tg,
    centre - demi_largeur * normale - e * tg
  )
  c(min(coins[, 1]), min(coins[, 2]), max(coins[, 1]), max(coins[, 2]))
}

# Dalles dont l'entete rencontre le rectangle. Un entete coute quelques
# millisecondes, une dalle entiere des dizaines de secondes : c'est ce filtre qui
# tient le budget "quelques secondes par clic". Entete illisible -> on garde la
# dalle (le filtre spatial de la lecture tranchera), on ne l'ecarte pas en
# silence.
.dalles_intersectant <- function(fichiers, bbox) {
  if (!length(fichiers)) {
    return(character(0))
  }
  garde <- vapply(fichiers, function(f) {
    h <- tryCatch(getExportedValue(.PKG_RLAS, "read.lasheader")(f),
      error = function(e) NULL)
    if (is.null(h)) {
      return(TRUE)
    }
    xmin <- h[["Min X"]]; xmax <- h[["Max X"]]
    ymin <- h[["Min Y"]]; ymax <- h[["Max Y"]]
    if (!is.numeric(xmin) || !is.numeric(ymax)) {
      return(TRUE)
    }
    !(xmax < bbox[1] || xmin > bbox[3] || ymax < bbox[2] || ymin > bbox[4])
  }, logical(1))
  fichiers[garde]
}

# Lecture du nuage dans un RECTANGLE (coordonnees terrain). Seule I/O de la
# fonction, isolee pour rester mockable en test -- et pour que l'absence de
# `rlas` (dependance de dessertR, hors CRAN) soit un repli, pas une erreur.
.lire_nuage_rect <- function(fichiers, bbox) {
  if (!length(fichiers)) {
    cli::cli_inform(c("i" = "Aucune dalle LiDAR dans {.arg las_source} :
                             pas de profil."))
    return(NULL)
  }
  if (!.rlas_dispo()) {
    cli::cli_warn(c(
      "!" = "Profil en travers {.strong indisponible} : {.pkg rlas} absent
             (lecteur de nuage).",
      "i" = "{.code install.packages(\"rlas\")} (archive CRAN), ou installer
             {.pkg dessertR} qui en depend."
    ))
    return(NULL)
  }
  # nocov start : chemin rlas, absent de la CI (valide hors CI sur la dalle
  # d'exemple dessertR).
  fs <- .dalles_intersectant(fichiers, bbox)
  if (!length(fs)) {
    cli::cli_inform(c("i" = "Aucune dalle LiDAR sous la station : pas de profil."))
    return(NULL)
  }
  filtre <- sprintf("-keep_xy %.3f %.3f %.3f %.3f", bbox[1], bbox[2], bbox[3], bbox[4])
  lst <- lapply(fs, function(f) {
    tryCatch(
      as.data.frame(getExportedValue(.PKG_RLAS, "read.las")(f,
        select = "xyzic", filter = filtre)),
      error = function(e) NULL
    )
  })
  lst <- lst[!vapply(lst, is.null, logical(1))]
  if (!length(lst)) {
    cli::cli_inform(c("i" = "Dalle{?s} illisible{?s} : pas de profil."))
    return(NULL)
  }
  pts <- do.call(rbind, lst)
  if (!nrow(pts)) {
    return(NULL)
  }
  attr(pts, "n_dalles") <- length(lst)
  pts
  # nocov end
}

# Nuage brut -> repere de la coupe. `x_travers` est SIGNE et centre sur l'axe
# (c'est l'axe X de la planche), `abscisse` est la position le long de l'axe dans
# la tranche, `z` est relatif au sol A L'AXE.
.points_coupe <- function(nuage, centre, tg, normale, demi_largeur, epaisseur_m,
                          z_ref) {
  col <- function(nom, defaut) {
    if (nom %in% names(nuage)) nuage[[nom]] else rep(defaut, nrow(nuage))
  }
  dx <- nuage[["X"]] - centre[1]
  dy <- nuage[["Y"]] - centre[2]
  x_travers <- dx * normale[1] + dy * normale[2]
  abscisse <- dx * tg[1] + dy * tg[2]
  classification <- as.integer(col("Classification", NA_integer_))
  out <- data.frame(
    x_travers = x_travers,
    z = as.numeric(nuage[["Z"]]) - z_ref,
    intensite = as.numeric(col("Intensity", NA_real_)),
    sol = !is.na(classification) & classification == 2L,
    classification = classification,
    abscisse = abscisse
  )
  garde <- abs(out$abscisse) <= epaisseur_m / 2 &
    abs(out$x_travers) <= demi_largeur & is.finite(out$z)
  out <- out[garde, , drop = FALSE]
  rownames(out) <- NULL
  out
}


# --- Sol et bords ------------------------------------------------------------

# Profil du terrain sur le MNT, le long de la normale. Bilineaire : un
# echantillonnage plus fin que la maille rendrait sinon un escalier, et la
# recherche de bord lirait ses marches comme des ruptures.
.profil_sol <- function(mnt, centre, normale, demi_largeur, pas_travers, z_ref) {
  x <- seq(-demi_largeur, demi_largeur, by = pas_travers)
  px <- centre[1] + x * normale[1]
  py <- centre[2] + x * normale[2]
  z <- tryCatch(
    terra::extract(mnt[[1]], cbind(px, py), method = "bilinear")[, 1],
    error = function(e) rep(NA_real_, length(x))
  )
  data.frame(x_travers = x, z = as.numeric(z) - z_ref)
}

# Altitude du sol interpolee a des abscisses quelconques (hauteur des points).
.interpoler_sol <- function(sol, x) {
  ok <- is.finite(sol$z)
  if (sum(ok) < 2L) {
    return(rep(NA_real_, length(x)))
  }
  stats::approx(sol$x_travers[ok], sol$z[ok], xout = x, rule = 2)$y
}

# Parabole des moindres carres z = a x^2 + b x + c. NULL si trop peu de points ou
# ajustement degenere.
.ajuster_parabole <- function(x, z, n_min = 5L) {
  ok <- is.finite(x) & is.finite(z)
  x <- x[ok]; z <- z[ok]
  if (length(x) < n_min || length(unique(round(x, 3))) < 3L) {
    return(NULL)
  }
  fit <- tryCatch(stats::lm(z ~ x + I(x^2)), error = function(e) NULL)
  if (is.null(fit) || anyNA(stats::coef(fit))) {
    return(NULL)
  }
  co <- as.numeric(stats::coef(fit))
  r <- stats::residuals(fit)
  list(a = co[3], b = co[2], c = co[1],
    rmse = sqrt(mean(r^2)), n = length(x))
}

.evaluer_parabole <- function(p, x) p$a * x^2 + p$b * x + p$c

# Plage centree sur l'axe ou |z - reference| reste sous `tol`. Le bord est
# INTERPOLE entre le dernier echantillon conforme et le premier qui ne l'est
# plus : sans cela la largeur est quantifiee au pas transversal (biais
# systematique d'un demi-pas par cote).
.plage_ecart <- function(x, z, ref, tol) {
  ic <- which.min(abs(x))
  r <- abs(z - ref)
  n <- length(x)
  cote <- function(pas) {
    k <- ic
    repeat {
      j <- k + pas
      if (j < 1L || j > n) {
        return(x[k])
      }
      if (!is.finite(r[j]) || r[j] > tol) {
        t <- if (is.finite(r[k]) && r[j] > r[k]) (tol - r[k]) / (r[j] - r[k]) else 0
        return(x[k] + min(1, max(0, t)) * (x[j] - x[k]))
      }
      k <- j
    }
  }
  c(cote(-1L), cote(1L))
}

# Plage centree sur l'axe LIBRE d'occupation. Sert a l'emprise, la seule famille
# lue sur le nuage : de chaque cote, on s'arrete a l'echo genant le plus proche
# de l'axe. Le bord retenu est la borne INTERIEURE de la case de `pas` metres qui
# le contient -- le choix conservateur : la plage rendue est libre, elle n'est
# jamais elargie jusqu'a l'obstacle. Les deux cotes sont traites separement pour
# que la mesure reste symetrique (un decoupage en cases traversant l'axe rendrait
# des bords differents a gauche et a droite pour un profil symetrique).
.plage_libre <- function(x_occupe, demi_largeur, pas) {
  x_occupe <- x_occupe[is.finite(x_occupe)]
  lim <- function(v) {
    if (!length(v)) {
      return(demi_largeur)
    }
    max(0, min(demi_largeur, (ceiling(min(abs(v)) / pas) - 1) * pas))
  }
  c(-lim(x_occupe[x_occupe <= 0]), lim(x_occupe[x_occupe >= 0]))
}

# Pente en travers du terrain, echantillon par echantillon (differences
# centrees), et le predicat de franchissement qui en decoule.
.franchissable <- function(x, z, pente_max) {
  n <- length(x)
  s <- rep(NA_real_, n)
  if (n >= 3L) {
    s[2:(n - 1L)] <- (z[3:n] - z[1:(n - 2L)]) / (x[3:n] - x[1:(n - 2L)])
  }
  is.finite(s) & abs(s) <= pente_max
}

# Plage obtenue en s'ecartant d'une plage de DEPART tant que `ok` tient. Le
# depart est conserve : une famille ne peut pas etre plus etroite que celle
# qu'elle contient.
.plage_croissance <- function(x, ok, depart) {
  n <- length(x)
  ig <- which.min(abs(x - depart[1]))
  id <- which.min(abs(x - depart[2]))
  while (ig > 1L && isTRUE(ok[ig - 1L])) ig <- ig - 1L
  while (id < n && isTRUE(ok[id + 1L])) id <- id + 1L
  c(min(x[ig], depart[1]), max(x[id], depart[2]))
}

# Les cinq familles, EMBOITEES par construction :
#   drivable  <=  road  <=  rescue  <=  right_of_way
# `drivable` est ecrete par `road` ; `rescue` part de `road` et s'ecarte tant que
# le terrain reste franchissable ; `right_of_way` est l'union de `road` et du
# couloir sans obstacle. L'ordre n'est donc pas espere, il tient par la
# construction -- une emprise contient la route qu'elle porte, une largeur de
# secours contient la chaussee.
#
# Le choix qui compte : le couloir se lit sur la bande de TRONCS (0,5 a 5 m
# au-dessus du sol), pas sur le couvert. Mesure faite sur la dalle d'exemple
# dessertR (Lozere, futaie fermee) : les houppiers se referment au-dessus d'une
# piste de 3,6 m, donc un critere "pas d'echo a plus de 2 m" rend une trouee
# NULLE et une emprise egale a la plateforme -- une famille qui ne dit plus rien.
# Les troncs, eux, s'ecartent : 23 m de couloir libre au meme endroit. C'est
# l'emprise, au sens ou on l'a defrichee.
.bords_profil <- function(sol, pts, demi_largeur, pas_travers,
                          h_obstacle = c(0.5, 5), pente_max = 0.20,
                          tol_chaussee = 0.05, tol_plateforme = 0.15) {
  x <- sol$x_travers
  z <- sol$z

  # Plateforme : plan de chaussee ajuste sur la fenetre centrale, puis on s'ecarte
  # tant que le sol y reste. C'est la methode "planeite" de dessertR, transposee
  # a une station unique.
  fen <- min(1.5, demi_largeur / 2)
  cen <- abs(x) <= fen & is.finite(z)
  plan <- if (sum(cen) >= 3L) {
    stats::coef(stats::lm(z[cen] ~ x[cen]))
  } else {
    c(0, 0)
  }
  ref_plan <- plan[1] + plan[2] * x
  road <- .plage_ecart(x, z, ref_plan, tol_plateforme)

  # Chaussee : la parabole du bombement, ajustee sur la fenetre centrale, puis
  # meme croissance, ECRETEE par la plateforme.
  p0 <- .ajuster_parabole(x[cen], z[cen])
  ref_par <- if (is.null(p0)) ref_plan else .evaluer_parabole(p0, x)
  drivable <- .plage_ecart(x, z, ref_par, tol_chaussee)
  drivable <- c(max(drivable[1], road[1]), min(drivable[2], road[2]))

  # Emprise : lue sur le NUAGE, pas sur le MNT -- c'est exactement ce que le MNT
  # a efface. Bande de troncs (`h_obstacle`), obstacle le plus proche de l'axe de
  # chaque cote, union avec la plateforme.
  h <- pts$hauteur_sol
  degage <- .plage_libre(
    pts$x_travers[is.finite(h) & h >= h_obstacle[1] & h <= h_obstacle[2]],
    demi_largeur, pas_travers)
  row <- c(min(road[1], degage[1]), max(road[2], degage[2]))

  # Secours : depuis la plateforme, on s'ecarte tant que le terrain reste
  # franchissable (pente en travers sous `pente_max`), sans depasser l'emprise.
  # C'est la ou un vehicule peut REELLEMENT se ranger ou passer : ni le fosse, ni
  # le talus, ni le sous-bois.
  rescue <- .plage_croissance(x, .franchissable(x, z, pente_max), road)
  rescue <- c(max(rescue[1], row[1]), min(rescue[2], row[2]))

  bord <- function(type, cote, g, d) {
    data.frame(type = type, cote = cote, x_gauche = g, x_droite = d,
      largeur_m = d - g, stringsAsFactors = FALSE)
  }
  out <- rbind(
    bord("drivable", NA_character_, drivable[1], drivable[2]),
    bord("road", NA_character_, road[1], road[2]),
    bord("right_of_way", NA_character_, row[1], row[2]),
    bord("shoulder", "gauche", road[1], drivable[1]),
    bord("shoulder", "droite", drivable[2], road[2]),
    bord("rescue", NA_character_, rescue[1], rescue[2])
  )
  rownames(out) <- NULL
  out
}

# Parabole de chaussee rendue a l'appelant : ajustee sur les POINTS SOL de la
# bande roulable si le nuage en porte assez (c'est ce que la planche montre),
# sinon sur le profil MNT -- et la source est dite, parce qu'un ajustement sur un
# produit interpole ne se lit pas comme un ajustement sur les echos.
.ajustement_chaussee <- function(sol, pts, bords, n_min_sol = 10L) {
  dr <- bords[bords$type == "drivable", ][1, ]
  dans <- function(x) is.finite(x) & x >= dr$x_gauche & x <= dr$x_droite
  ps <- pts[pts$sol & dans(pts$x_travers), , drop = FALSE]
  if (nrow(ps) >= n_min_sol) {
    p <- .ajuster_parabole(ps$x_travers, ps$z)
    if (!is.null(p)) {
      p$source <- "points_sol"
      return(p)
    }
  }
  ok <- dans(sol$x_travers)
  p <- .ajuster_parabole(sol$x_travers[ok], sol$z[ok])
  if (is.null(p)) {
    return(NULL)
  }
  p$source <- "mnt"
  p
}


# --- Cache -------------------------------------------------------------------

# Cle deterministe : le clic (au demi-metre) et TOUS les parametres qui changent
# le CONTENU -- y compris les tolerances et les seuils des bords. Les omettre
# ferait servir un profil calcule avec d'autres reglages a qui vient justement de
# les changer, et ce genre de cache-la se paie en heures de diagnostic (spec 027).
.cle_profil <- function(pt, demi_largeur, epaisseur_m, pas_travers, tolerance_m,
                        h_obstacle, pente_max, tol_chaussee, tol_plateforme) {
  xy <- as.numeric(sf::st_coordinates(pt)[1, 1:2])
  cle <- sprintf(
    "profil_%.1f_%.1f_dl%.2f_ep%.2f_pt%.2f_to%.2f_ho%.2f-%.2f_pm%.3f_tc%.3f_tp%.3f",
    round(xy[1] * 2) / 2, round(xy[2] * 2) / 2,
    demi_largeur, epaisseur_m, pas_travers, tolerance_m,
    h_obstacle[1], h_obstacle[2], pente_max, tol_chaussee, tol_plateforme)
  gsub("[^0-9A-Za-z_.-]", "_", cle)
}

.profil_cache_lire <- function(cache_dir, cle) {
  f <- file.path(cache_dir, "profil_travers", paste0(cle, ".rds"))
  if (!file.exists(f)) {
    return(NULL)
  }
  out <- tryCatch(readRDS(f), error = function(e) NULL)
  if (!is.list(out) || is.null(out$meta)) {
    return(NULL)
  }
  out$meta$cache <- TRUE
  out
}

.profil_cache_ecrire <- function(cache_dir, cle, out) {
  d <- file.path(cache_dir, "profil_travers")
  tryCatch({
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    saveRDS(out, file.path(d, paste0(cle, ".rds")))
  }, error = function(e) invisible(NULL)) # un profil sans cache reste valide
  invisible(NULL)
}
