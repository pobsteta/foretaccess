# Acquisition des couches IGN Geoplateforme via happign (Lot 10).
#
# Les appels reseau reels sont isoles dans de minces wrappers internes
# (.fetch_wms_raster / .fetch_wfs) : les tests unitaires les remplacent par des
# fixtures (local_mocked_bindings), sans reseau ni dependance installee.

# Garde de dependance optionnelle (happign/osmdata sont en Suggests).
.require_pkg <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cli::cli_abort(c(
      "Le paquet {.pkg {pkg}} est requis pour cette acquisition.",
      "i" = "Installez-le : {.code install.packages(\"{pkg}\")}."
    ))
  }
  invisible(TRUE)
}

# --- Wrappers reseau (points de mock) ---------------------------------------

.fetch_wms_raster <- function(aoi, layer, res, crs, filename) {
  .require_pkg("happign")
  happign::get_wms_raster(
    x = aoi, layer = layer, res = res, crs = crs,
    rgb = FALSE, filename = filename, overwrite = TRUE, verbose = FALSE
  )
}

# Cote (m) des tuiles de requetage WFS. Le WFS IGN rend des jeux INCOMPLETS sur
# une grande bbox : mesure sur l'AOI oracle le 2026-07-30, une requete unique sur
# une emprise de 1600 m de buffer rendait 1380 features dont seulement 86
# touchaient l'AOI stricte, contre 245 en decoupant la meme emprise en quadrants.
# La perte n'est PAS repartie au hasard -- le WFS rend les features dans son ordre
# interne, pas spatial -- et rien ne la signale. Un reseau ampute produit des
# composantes orphelines fictives (cf. spec 025) et des surfaces inaccessibles a
# tort. 2 km : sous le regime ou la perte apparait sur les couches testees.
.TUILE_WFS_M <- 2000

.fetch_wfs <- function(aoi, typename, tuile_m = .TUILE_WFS_M) {
  .require_pkg("happign")
  aoi_sf <- sf::st_as_sf(sf::st_geometry(sf::st_as_sf(aoi)))
  tuiles <- .tuiles_bbox(aoi_sf, tuile_m)
  if (length(tuiles) <= 1L) {
    return(happign::get_wfs(x = aoi, layer = typename))
  }
  morceaux <- lapply(tuiles, function(t) {
    tryCatch(happign::get_wfs(x = t, layer = typename), error = function(e) NULL)
  })
  morceaux <- morceaux[!vapply(morceaux, is.null, logical(1))]
  morceaux <- morceaux[vapply(morceaux, function(x) nrow(x) > 0, logical(1))]
  if (!length(morceaux)) {
    return(happign::get_wfs(x = aoi, layer = typename)) # nocov
  }
  .dedupe_features(.rbind_features(morceaux))
}

# Decoupe la bbox de `aoi` en tuiles carrees d'au plus `tuile_m` de cote. Rend une
# liste de `sfc` ; un seul element si l'emprise tient dans une tuile.
.tuiles_bbox <- function(aoi_sf, tuile_m) {
  bb <- sf::st_bbox(aoi_sf)
  crs <- sf::st_crs(aoi_sf)
  nx <- max(1L, ceiling(as.numeric(bb["xmax"] - bb["xmin"]) / tuile_m))
  ny <- max(1L, ceiling(as.numeric(bb["ymax"] - bb["ymin"]) / tuile_m))
  if (nx * ny <= 1L) {
    return(list(sf::st_as_sfc(bb)))
  }
  xs <- seq(bb["xmin"], bb["xmax"], length.out = nx + 1L)
  ys <- seq(bb["ymin"], bb["ymax"], length.out = ny + 1L)
  out <- vector("list", nx * ny)
  k <- 0L
  for (i in seq_len(nx)) {
    for (j in seq_len(ny)) {
      k <- k + 1L
      # Chevauchement d'une tuile sur l'autre : un troncon a cheval doit sortir
      # ENTIER d'au moins une requete, sinon la deduplication garderait deux
      # moities et le graphe resterait coupe.
      b <- c(xmin = xs[i] - tuile_m * 0.05, ymin = ys[j] - tuile_m * 0.05,
             xmax = xs[i + 1L] + tuile_m * 0.05, ymax = ys[j + 1L] + tuile_m * 0.05)
      g <- sf::st_as_sfc(sf::st_bbox(b))
      sf::st_crs(g) <- crs
      out[[k]] <- g
    }
  }
  out
}

# rbind tolerant : les pages WFS peuvent differer d'une colonne a l'autre selon
# les valeurs rencontrees. On s'aligne sur les colonnes COMMUNES plutot que
# d'echouer -- perdre une colonne annexe vaut mieux que perdre la tuile.
.rbind_features <- function(morceaux) {
  communs <- Reduce(intersect, lapply(morceaux, names))
  if (!length(communs)) {
    return(morceaux[[1]]) # nocov
  }
  do.call(rbind, lapply(morceaux, function(x) x[, communs, drop = FALSE]))
}

# Deduplication des features rendues par plusieurs tuiles. `cleabs` est
# l'identifiant stable de la BD TOPO ; a defaut on retombe sur la geometrie.
.dedupe_features <- function(x) {
  if (nrow(x) == 0) {
    return(x)
  }
  cle <- if ("cleabs" %in% names(x)) {
    as.character(x$cleabs)
  } else {
    vapply(sf::st_geometry(x), function(g) {
      paste0(format(unclass(sf::st_bbox(g)), digits = 12), collapse = "|")
    }, character(1))
  }
  x[!duplicated(cle), , drop = FALSE]
}

# --- Utilitaires communs ----------------------------------------------------

# Chemin de cache d'une couche : cache_dir/layers/<couche>/<couche>.<ext>.
.chemin_cache <- function(cache_dir, couche, ext) {
  d <- file.path(cache_dir, "layers", couche)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  file.path(d, paste0(couche, ".", ext))
}

# Reprojette un sf vers le CRS cible puis le decoupe sur l'AOI (polygone deja
# dans le CRS cible). Les WFS ne filtrent que par bbox : le clip est necessaire.
.reprojeter_clip <- function(x, aoi_cible, crs) {
  x <- sf::st_transform(x, crs)
  x <- sf::st_make_valid(x)
  inter <- suppressWarnings(sf::st_intersection(x, sf::st_geometry(aoi_cible)))
  inter[!sf::st_is_empty(inter), , drop = FALSE]
}

# Mapping de la classe de desserte depuis les attributs BD TOPO `troncon_de_route`.
# Comparaison en ASCII replie (les valeurs BD TOPO sont accentuees ; litteraux R
# ASCII). La classe `dfci` reste vide en phase 1 (spec 010 Q2), alimentee a part.
#
# Deux classifications :
#  * "heuristique" (historique, bit-pour-bit) : piste si `nature` contient
#    chemin/sentier/empierree/escalier/piste cyclable, sinon route. BUG : la
#    "Route empierree" (carrossable, route forestiere) y tombe en PISTE, ce qui
#    force le trainage le long et gonfle la distance de debardage.
#  * "clsvac" (defaut, spec 022) : trois classes facon Sylvaccess CL_SVAC --
#    piste (chemins/sentiers, on y traine), route forestiere = terminus du
#    trainage (routes carrossables, y compris empierrees) et reseau public =
#    grands axes (barriere : le skidder n'y va pas). Rapproche d'ACCESSFOR.
#  * "accessfor" (defaut, spec 024) : la table PUBLIEE du rapport ACCESSFOR
#    (annexe p.51), fondee sur `nature` SEUL -- `importance` n'y figure pas :
#      Route a 2 chaussees / Route a 1 chaussee -> 3 reseau public
#      Route empierree / Route forestiere nommee -> 2 route forestiere
#      Chemin -> 1 piste
#      tout le reste (dont Sentier, Rond-point) -> 0 HORS DESSERTE
#    La spec 022 croyait cette table non publiee et l'avait calee empiriquement
#    ("clsvac") : sur l'AOI oracle les deux divergent sur 108/256 troncons.
.mapper_classe_desserte <- function(x, classification = c("accessfor", "clsvac",
                                                          "heuristique"),
                                    cleabs_forestieres = character(0)) {
  classification <- match.arg(classification)
  nat <- if ("nature" %in% names(x)) as.character(x$nature) else rep(NA_character_, nrow(x))
  nat_ascii <- tolower(iconv(nat, to = "ASCII//TRANSLIT"))

  if (classification == "accessfor") {
    # Transcription A LA LETTRE de l'annexe p.51 : appariement sur la modalite
    # ENTIERE de `nature`, pas par mots-cles -- « Route a 1 chaussee » ne doit pas
    # etre attrapee par un motif « route » trop large.
    classe <- rep("hors_desserte", length(nat_ascii))
    classe[nat_ascii %in% c("route a 2 chaussees", "route a 1 chaussee")] <- "reseau_public"
    classe[nat_ascii == "route empierree"] <- "route"
    classe[nat_ascii == "chemin"] <- "piste"
    # Route forestiere nommee : l'annexe la lit sur la couche LIEE « Route
    # numerotee ou nommee » (`type_de_route`), pas sur `nature`. Le lien est
    # porte par `liens_vers_route_nommee` (cleabs de la couche liee).
    if (length(cleabs_forestieres) &&
        "liens_vers_route_nommee" %in% names(x)) {
      lien <- as.character(x$liens_vers_route_nommee)
      est_rf <- !is.na(lien) & lien %in% cleabs_forestieres
      classe[est_rf] <- "route"
    }
    return(classe)
  }

  if (classification == "heuristique") {
    motifs_piste <- c("chemin", "sentier", "empierree", "escalier", "piste cyclable")
    est_piste <- Reduce(`|`, lapply(motifs_piste, function(p) {
      r <- grepl(p, nat_ascii, fixed = TRUE)
      r[is.na(r)] <- FALSE
      r
    }))
    classe <- rep("route", length(nat_ascii))
    classe[est_piste] <- "piste"
    return(classe)
  }

  # --- CL_SVAC (defaut) ------------------------------------------------------
  imp <- if ("importance" %in% names(x)) {
    suppressWarnings(as.integer(as.character(x$importance)))
  } else {
    rep(NA_integer_, nrow(x))
  }
  # piste (CL_SVAC=1) : voies non carrossables camion, on y traine le bois.
  est_piste <- grepl("chemin|sentier|escalier|piste cyclable|bac", nat_ascii)
  est_piste[is.na(est_piste)] <- FALSE
  # reseau public (CL_SVAC=3, barriere) : grands axes (autoroute, ou importance
  # elevee <= 3 : nationales/departementales structurantes). Le skidder n'y va pas.
  est_public <- grepl("autorout", nat_ascii) | (!is.na(imp) & imp <= 3L)
  est_public[is.na(est_public)] <- FALSE
  # Defaut : route forestiere (CL_SVAC=2) = terminus du trainage (Route empierree,
  # Route a 1/2 chaussees d'importance 4-6).
  classe <- rep("route", length(nat_ascii))
  classe[est_piste] <- "piste"
  classe[est_public] <- "reseau_public"
  classe
}

# Identifiants (`cleabs`) des ROUTES FORESTIERES NOMMEES, sur la couche liee
# « Route numerotee ou nommee » de la BD TOPO. L'annexe ACCESSFOR p.51 les classe
# en CL_SVAC = 2 au meme titre que les routes empierrees, mais l'information ne
# vit PAS dans `nature` : elle est portee par `type_de_route` de la couche liee,
# que `troncon_de_route` reference via `liens_vers_route_nommee`.
# Couche absente ou vide -> vecteur vide, donc aucun reclassement : degradation
# silencieuse, jamais d'echec (CA-24.3).
.ROUTES_NOMMEES_TYPENAME <- "BDTOPO_V3:route_numerotee_ou_nommee"

.cleabs_routes_forestieres <- function(aoi) {
  rn <- tryCatch(.fetch_wfs(aoi, .ROUTES_NOMMEES_TYPENAME), error = function(e) NULL)
  if (is.null(rn) || nrow(rn) == 0 ||
      !all(c("cleabs", "type_de_route") %in% names(rn))) {
    return(character(0))
  }
  est_f <- grepl("forestiere", tolower(iconv(as.character(rn$type_de_route),
    to = "ASCII//TRANSLIT")), fixed = TRUE)
  est_f[is.na(est_f)] <- FALSE
  unique(as.character(rn$cleabs)[est_f])
}

#' Acquiert un MNT RGE ALTI depuis les **dalles départementales** (Géoservices)
#'
#' Alternative saine au RGE ALTI servi par WMS, qui rend un MNT **blocky** (blocs
#' plats à marches) dont la pente est fausse. C'est le produit que prescrit la
#' notice ACCESSFOR (rapport février 2025, annexe p. 50) : *« Livraison d'un MNT
#' provenant du RGE Alti 5m converti en 32bit »*, téléchargé par département.
#'
#' @details
#' L'archive départementale (~450 Mo en `.7z` pour le 5 m) est téléchargée une
#' fois et mise en cache ; seules les **dalles couvrant l'AOI** en sont extraites,
#' puis mosaïquées et découpées. L'extraction requiert `py7zr` (Python) ou un
#' binaire `7z` sur le `PATH` -- l'archive Géoservices n'est pas lisible autrement.
#'
#' Sur la même AOI, ce produit donne une distribution de pente quasi identique au
#' MNT LiDAR HD (médiane 39,96 % contre 40,99 %), là où la variante WMS donnait
#' une médiane de 18,89 % et un maximum de 382 %.
#'
#' @inheritParams acquire_mnt
#' @param dep Code du département sur deux caractères (ex. `"48"`).
#' @param res_m Résolution du produit RGE ALTI : 5 ou 1. Défaut 5.
#' @return Le chemin du raster `mnt_rgealti.tif` écrit en cache.
#' @seealso [acquire_mnt()] (LIDAR HD, source par défaut).
#' @export
acquire_mnt_rgealti <- function(aoi, dep, res_m = 5, crs = 2154,
                                cache_dir = tempdir(), overwrite = FALSE) {
  checkmate::assert_string(dep, min.chars = 2, max.chars = 3)
  checkmate::assert_choice(as.integer(res_m), c(1L, 5L))
  chemin <- .chemin_cache(cache_dir, "mnt_rgealti", "tif")
  if (file.exists(chemin) && !overwrite) {
    return(chemin)
  }
  # nocov start : reseau + archive lourde, hors CI (valide sur le dep 48).
  d <- file.path(cache_dir, "rgealti")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  arch <- .rgealti_archive(dep, res_m, d)
  asc <- .rgealti_extraire(arch, aoi, crs, d)
  if (!length(asc)) {
    cli::cli_abort("Aucune dalle RGE ALTI ne couvre l'emprise (dep {.val {dep}}).")
  }
  tuiles <- lapply(asc, function(f) {
    r <- terra::rast(f)
    terra::crs(r) <- paste0("EPSG:", crs) # l'ASC ne porte pas le CRS
    r
  })
  mos <- if (length(tuiles) == 1L) tuiles[[1]] else do.call(terra::merge, tuiles)
  aoi_c <- sf::st_transform(sf::st_geometry(sf::st_as_sf(aoi)), crs)
  mos <- terra::crop(mos, terra::vect(aoi_c), snap = "out")
  terra::writeRaster(mos, chemin, overwrite = TRUE)
  chemin
  # nocov end
}

# Telecharge (une fois) l'archive departementale RGE ALTI depuis la Geoplateforme.
# L'identifiant de livraison porte une DATE qui varie par departement : on la
# resout via le flux Atom de la ressource plutot que de la coder en dur.
.rgealti_archive <- function(dep, res_m, dir_cache) { # nocov start
  f <- file.path(dir_cache, sprintf("RGEALTI_D%s_%dM.7z", dep, res_m))
  if (file.exists(f) && file.size(f) > 1e6) {
    return(f)
  }
  motif <- sprintf("RGEALTI[A-Za-z0-9_.-]*%dM_ASC_LAMB93[A-Za-z0-9_.-]*D0*%s_[0-9-]+",
    res_m, dep)
  id <- NULL
  for (p in seq_len(30)) {
    u <- sprintf("https://data.geopf.fr/telechargement/resource/RGEALTI?page=%d", p)
    txt <- tryCatch(paste(readLines(u, warn = FALSE), collapse = "\n"),
      error = function(e) "")
    hit <- regmatches(txt, regexpr(motif, txt))
    if (length(hit) && nzchar(hit)) {
      id <- hit
      break
    }
  }
  if (is.null(id)) {
    cli::cli_abort("Livraison RGE ALTI {.val {res_m}} m introuvable pour le
                    departement {.val {dep}}.")
  }
  url <- sprintf("https://data.geopf.fr/telechargement/download/RGEALTI/%s/%s.7z",
    id, id)
  cli::cli_inform("RGE ALTI {.val {dep}} : telechargement de {.val {id}} (~450 Mo).")
  utils::download.file(url, f, mode = "wb", quiet = TRUE)
  f
}

# Extrait les seules dalles couvrant l'AOI. Les dalles sont nommees
# `RGEALTI_FXX_<xmin_km>_<ymax_km>_MNT_...asc` ; on selectionne sur ces bornes.
.rgealti_extraire <- function(arch, aoi, crs, dir_cache) {
  bb <- sf::st_bbox(sf::st_transform(sf::st_geometry(sf::st_as_sf(aoi)), crs))
  deja <- list.files(dir_cache, pattern = "\\.asc$", recursive = TRUE,
    full.names = TRUE)
  garder <- function(f) {
    m <- regmatches(basename(f), regexec("_(\\d{4})_(\\d{4})_", basename(f)))[[1]]
    if (length(m) < 3) {
      return(FALSE)
    }
    x0 <- as.numeric(m[2]) * 1000
    y1 <- as.numeric(m[3]) * 1000
    # Dalle de 5 km (produit 5 m) : [x0, x0+5000] x [y1-5000, y1].
    x0 <= bb["xmax"] && (x0 + 5000) >= bb["xmin"] &&
      (y1 - 5000) <= bb["ymax"] && y1 >= bb["ymin"]
  }
  sel <- deja[vapply(deja, garder, logical(1))]
  if (length(sel)) {
    return(sel)
  }
  .rgealti_desarchiver(arch, dir_cache)
  deja <- list.files(dir_cache, pattern = "\\.asc$", recursive = TRUE,
    full.names = TRUE)
  deja[vapply(deja, garder, logical(1))]
}

# Desarchivage : py7zr (Python) ou binaire 7z. L'archive Geoservices est en .7z,
# format que ni utils::unzip ni archive::archive ne lisent par defaut.
.rgealti_desarchiver <- function(arch, dir_cache) {
  bin <- Sys.which(c("7z", "7za", "7zr"))
  bin <- bin[nzchar(bin)]
  if (length(bin)) {
    system2(bin[[1]], c("x", "-y", shQuote(arch), paste0("-o", shQuote(dir_cache))),
      stdout = FALSE, stderr = FALSE)
    return(invisible(TRUE))
  }
  py <- Sys.which("python3")
  if (!nzchar(py)) {
    cli::cli_abort("Ni {.code 7z} ni {.code python3} : impossible d'ouvrir
                    l'archive RGE ALTI.")
  }
  code <- sprintf(
    "import py7zr; z=py7zr.SevenZipFile(%s,'r'); z.extractall(%s)",
    shQuote(arch, type = "sh"), shQuote(dir_cache, type = "sh"))
  st <- system2(py, c("-c", shQuote(code)), stdout = FALSE, stderr = FALSE)
  if (!identical(st, 0L)) {
    cli::cli_abort("Extraction de l'archive RGE ALTI echouee
                    ({.code py7zr} absent ?).")
  }
  invisible(TRUE)
} # nocov end

# --- Acquisition par source -------------------------------------------------

#' Acquiert le MNT depuis RGE ALTI (IGN WMS)
#'
#' @param aoi Objet `sf`/`sfc` d'emprise, dans le CRS cible.
#' @param res_m Résolution du raster (m). Défaut 5.
#' @param crs Code EPSG de sortie. Défaut 2154.
#' @param cache_dir Répertoire de cache.
#' @param overwrite Re-télécharger même si le cache existe. Défaut `FALSE`.
#' @param country Code pays ISO. Défaut `"FR"`.
#' @param res_lidar_m Résolution fine (m) de téléchargement du **MNT LIDAR HD**
#'   (couche primaire) sur l'emprise, agrégée ensuite à `res_m`. Défaut 1. Doit
#'   diviser `res_m` (ex. 1 → 5). Passer `res_lidar_m >= res_m` désactive
#'   l'agrégation (téléchargement direct à `res_m`).
#' @return Le chemin du raster `mnt.tif` écrit en cache.
#' @export
acquire_mnt <- function(aoi, res_m = 5, crs = 2154, cache_dir = tempdir(),
                        overwrite = FALSE, country = "FR", res_lidar_m = 1) {
  chemin <- .chemin_cache(cache_dir, "mnt", "tif")
  if (file.exists(chemin) && !overwrite) {
    return(chemin)
  }
  checkmate::assert_number(res_lidar_m, lower = 0, finite = TRUE)
  info <- get_layer_service("dem", country)
  if (is.null(info)) {
    cli::cli_abort("Couche {.val dem} introuvable pour le pays {.val {country}}.")
  }
  # Chaine de couches d'altitude : LIDAR HD (Lambert-93 natif, propre) -> HIGHRES
  # -> RGE ALTI. Le WMS d'altitude sert depuis une pyramide de tuiles web-mercator
  # rereprojetee ; sur certaines tuiles RGE ALTI cela produit un MNT "blocky" (blocs
  # plats a marches) qui fabrique de fausses pentes en grille (jusqu'a > 300 %) et
  # donc de faux "inexploitable". Les couches LIDAR HD n'ont pas cet artefact. On
  # essaie chaque couche jusqu'a une couverture suffisante (le LIDAR HD n'est pas
  # partout : hors couverture, le WMS rend un raster majoritairement NA).
  couches <- c(info$layer, as.character(info$fallback_layers))
  .verifier_couches_mnt(couches)
  for (i in seq_along(couches)) {
    ly <- couches[[i]]
    # La couche PRIMAIRE (LIDAR HD MNT) est telechargee FINE (res_lidar_m) sur
    # l'emprise -> `lidar_mnt_aoi_buffer.tif`, puis AGREGEE (moyenne) a res_m : le
    # 5 m est ainsi derive proprement d'un MNT fin, plutot que demande directement
    # au WMS (qui echantillonnerait depuis une pyramide plus grossiere). Les replis
    # (HIGHRES / RGE ALTI, plus grossiers) restent telecharges en direct a res_m.
    fine <- i == 1L && res_lidar_m < res_m
    ok <- tryCatch(
      if (fine) {
        .acquerir_mnt_fin(aoi, ly, res_m, res_lidar_m, crs, chemin)
      } else {
        .fetch_wms_raster(aoi, layer = ly, res = res_m, crs = crs, filename = chemin)
        .mnt_couverture_suffisante(chemin)
      },
      error = function(e) FALSE
    )
    if (isTRUE(ok)) {
      if (i > 1L) {
        cli::cli_inform("MNT : couche principale indisponible sur l'emprise, repli sur {.val {ly}}.")
      }
      return(chemin)
    }
  }
  cli::cli_abort(c(
    "Aucune couche MNT ne couvre l'emprise (essaye : {.val {couches}}).",
    "i" = "Il n'y a plus de repli WMS : les couches RGE ALTI servies par WMS
           rendent un MNT {.strong blocky} (blocs plats a marches, fausses pentes
           jusqu'a 382 %) -- cf. {.fn acquire_mnt_rgealti}.",
    "i" = "Hors couverture LIDAR HD : {.code acquire_mnt_rgealti(aoi, dep = \"48\")}
           telecharge les dalles departementales RGE ALTI, saines."
  ))
}

# Interdiction dure : aucune couche RGE ALTI par WMS ne doit revenir dans la
# chaine. Le WMS d'altitude sert une pyramide web-mercator rereprojetee ; sur
# certaines tuiles elle rend un MNT blocky dont la pente est fausse (Q1 a 1,9 %
# pour une mediane a 18,9 % et un MAX a 382 %, mesure sur l'AOI oracle le
# 2026-07-29). Un tel MNT a alimente le banc `aoi` pendant deux semaines sans
# que rien ne le signale. Garde-fou teste, pas seulement documente.
.COUCHES_WMS_INTERDITES <- c(
  "ELEVATION.ELEVATIONGRIDCOVERAGE",
  "ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES"
)

.verifier_couches_mnt <- function(couches) {
  mauvaises <- intersect(couches, .COUCHES_WMS_INTERDITES)
  if (length(mauvaises)) {
    cli::cli_abort(c(
      "Couche{?s} MNT interdite{?s} : {.val {mauvaises}}.",
      "x" = "Le RGE ALTI par WMS rend un MNT {.strong blocky} a fausses pentes.",
      "i" = "Utiliser {.fn acquire_mnt_rgealti} (dalles departementales)."
    ))
  }
  invisible(TRUE)
}

# Telecharge le MNT LIDAR HD fin (res_lidar_m) sur l'emprise dans
# `lidar_mnt_aoi_buffer.tif`, puis l'agrege (moyenne, facteur res_m/res_lidar_m)
# vers `chemin` (base de calcul a res_m). Renvoie TRUE si la couverture est
# suffisante (sinon on laisse la boucle basculer sur un repli). Le fin brut est
# conserve en cache : produit intermediaire reutilisable (autres usages fins).
.acquerir_mnt_fin <- function(aoi, ly, res_m, res_lidar_m, crs, chemin) {
  chemin_fin <- file.path(dirname(chemin), "lidar_mnt_aoi_buffer.tif")
  .fetch_wms_raster(aoi, layer = ly, res = res_lidar_m, crs = crs, filename = chemin_fin)
  if (!.mnt_couverture_suffisante(chemin_fin)) {
    return(FALSE)
  }
  fact <- max(1L, as.integer(round(res_m / res_lidar_m)))
  agg <- terra::aggregate(terra::rast(chemin_fin), fact = fact, fun = "mean", na.rm = TRUE)
  terra::writeRaster(agg, chemin, overwrite = TRUE)
  .mnt_couverture_suffisante(chemin)
}

# Le MNT couvre-t-il assez l'emprise ? Le LIDAR HD n'est pas partout ; hors
# couverture le WMS rend un raster majoritairement NA, on passe alors au repli.
.mnt_couverture_suffisante <- function(chemin, seuil = 0.9) {
  if (!file.exists(chemin)) {
    return(FALSE)
  }
  v <- terra::values(terra::rast(chemin), mat = FALSE)
  length(v) > 0 && mean(is.finite(v)) >= seuil
}

#' Acquiert la desserte depuis BD TOPO (IGN WFS)
#'
#' Récupère `troncon_de_route`, reprojette, découpe sur l'AOI et dérive le champ
#' `classe` attendu par [preprocess()].
#'
#' @inheritParams acquire_mnt
#' @param classification Comment classer la BD TOPO en desserte Sylvaccess.
#'   `"accessfor"` (défaut, spec 024) applique la table **publiée** du rapport
#'   ACCESSFOR (annexe p. 51), fondée sur `nature` **seul** : « Route à 1 ou 2
#'   chaussées » → `reseau_public`, « Route empierrée » et route forestière
#'   nommée → `route`, « Chemin » → `piste`, **tout le reste** (dont « Sentier »)
#'   → hors desserte, donc retiré. `"clsvac"` (spec 022) est le calage empirique
#'   antérieur, qui utilisait `importance` ; `"heuristique"` l'historique deux
#'   classes. Sur l'AOI oracle, `"accessfor"` et `"clsvac"` divergent sur 42 %
#'   des tronçons.
#' @param garder_hors_desserte Conserver les tronçons `hors_desserte`
#'   (CL_SVAC = 0) dans la sortie ? **Défaut `TRUE` depuis le 2026-07-30.**
#'   Les retirer **coupe le réseau** : mesuré sur l'AOI oracle, leur suppression
#'   faisait passer les infractions de connectivité de 15 à 21 à 1600 m de
#'   buffer. L'annexe ACCESSFOR le dit elle-même du rond-point — « non
#'   nécessaire mais **permet de garder un réseau intègre** ». Ils sont donc
#'   conservés pour la **topologie**, et exclus du **débardage** par
#'   [preprocess()], qui ne connaît que les classes de
#'   `.classes_desserte()`. `FALSE` reproduit la couche Sylvaccess stricte
#'   (classes 1/2/3 seulement).
#' @return Un objet `sf` de lignes avec un champ `classe`.
#' @export
acquire_desserte <- function(aoi, crs = 2154, cache_dir = tempdir(),
                             overwrite = FALSE, country = "FR",
                             classification = c("accessfor", "clsvac", "heuristique"),
                             garder_hors_desserte = TRUE) {
  classification <- match.arg(classification)
  chemin <- .chemin_cache(cache_dir, "desserte", "gpkg")
  if (file.exists(chemin) && !overwrite) {
    return(sf::st_read(chemin, quiet = TRUE))
  }
  info <- get_layer_service("roads", country)
  if (is.null(info)) {
    cli::cli_abort("Couche {.val roads} introuvable pour le pays {.val {country}}.")
  }
  brut <- .fetch_wfs(aoi, info$typename)
  d <- .reprojeter_clip(brut, aoi, crs)
  # Routes forestieres nommees : une seule requete sur la couche liee, et
  # seulement quand la classification s'en sert.
  cleabs_f <- if (classification == "accessfor") {
    .cleabs_routes_forestieres(aoi)
  } else {
    character(0)
  }
  d$classe <- .mapper_classe_desserte(d, classification, cleabs_f)
  # On conserve la largeur BD TOPO (emprise) : critere du repli geometrique DFCI
  # (`.flag_dfci_repli`). Absente du flux -> NA (colonne quand meme presente).
  d$largeur <- .largeur_desserte(d)
  d <- d[, c("classe", "largeur")]
  # CL_SVAC = 0 : ces troncons ne sont PAS de la desserte forestiere (la couche
  # Sylvaccess d'ACCESSFOR ne contient que 1/2/3). On les retire, sans quoi ils
  # deviendraient des pistes praticables. Ils ne sont PAS ajoutes a
  # `.classes_desserte()` : `.rasteriser_desserte()` code les classes par leur
  # RANG et prend le `max` (la barriere l'emporte) -- une 5e classe passerait
  # devant `reseau_public`.
  hd <- d$classe == "hors_desserte"
  if (any(hd) && !isTRUE(garder_hors_desserte)) {
    cli::cli_inform(c(
      "Desserte : {sum(hd)} troncon{?s} hors desserte (CL_SVAC = 0) retire{?s}.",
      "!" = "Les retirer COUPE le reseau : ils portent la connectivite
             (rond-points, liaisons). Preferer {.code garder_hors_desserte = TRUE}."
    ))
    d <- d[!hd, , drop = FALSE]
  }
  sf::st_write(d, chemin, delete_dsn = TRUE, quiet = TRUE)
  d
}

# Codes BD Foret v2 exclus du masque foret par ACCESSFOR (rapport fev. 2025,
# annexe p.50) : « FORET = 0 pour les polygones ou CODE_TFV = LA4 (landes
# ligneuses), LA6 (landes herbacees) ; FORET = 1 pour l'ensemble des autres ».
# Une lande n'est pas une ressource a mobiliser : la compter en foret gonfle la
# surface accessible.
.CODES_TFV_NON_FORET <- c("LA4", "LA6")

#' Acquiert la forêt depuis BD Forêt v2 (IGN WFS)
#'
#' @details
#' Conforme au masque forêt d'ACCESSFOR (rapport février 2025, annexe p. 50) :
#' les **landes** (`code_tfv` `LA4` ligneuses, `LA6` herbacées) sont **exclues**
#' du masque -- elles portent `FORET = 0` chez ACCESSFOR, donc n'entrent pas dans
#' le calcul d'accessibilité. Passer `exclure_landes = FALSE` pour l'ancien
#' comportement (tous les polygones BD Forêt retenus).
#'
#' @inheritParams acquire_mnt
#' @param exclure_landes Exclure les landes (`code_tfv` dans `LA4`/`LA6`) du
#'   masque forêt, comme ACCESSFOR ? Défaut `TRUE`. Sans colonne `code_tfv` dans
#'   le flux, aucun filtrage n'est possible et la couche est renvoyée telle quelle.
#' @return Un objet `sf` de polygones de forêt.
#' @export
acquire_foret <- function(aoi, crs = 2154, cache_dir = tempdir(),
                          overwrite = FALSE, country = "FR",
                          exclure_landes = TRUE) {
  chemin <- .chemin_cache(cache_dir, "foret", "gpkg")
  if (file.exists(chemin) && !overwrite) {
    # Filtrage applique AUSSI a la relecture du cache : un cache ecrit avant la
    # v1.27.1 contient les landes, et le nom de fichier ne porte pas la trace du
    # filtre. Ne filtrer qu'a l'ecriture rendrait la correction inoperante sur
    # tout cache existant -- le piege exact de la classification de desserte
    # (cache heuristique servi indefiniment apres le passage en clsvac).
    return(.exclure_landes(sf::st_read(chemin, quiet = TRUE), exclure_landes))
  }
  info <- get_layer_service("bdforet_v2", country)
  if (is.null(info)) {
    cli::cli_abort("Couche {.val bdforet_v2} introuvable pour le pays {.val {country}}.")
  }
  brut <- .fetch_wfs(aoi, info$typename)
  f <- .reprojeter_clip(brut, aoi, crs)
  f <- .exclure_landes(f, exclure_landes)
  sf::st_write(f, chemin, delete_dsn = TRUE, quiet = TRUE)
  f
}

# Retire les landes du masque foret (cf. .CODES_TFV_NON_FORET). Sans colonne
# `code_tfv` on ne peut pas filtrer : on renvoie tel quel plutot que d'echouer.
.exclure_landes <- function(f, exclure = TRUE) {
  if (!isTRUE(exclure) || !("code_tfv" %in% names(f)) || nrow(f) == 0) {
    return(f)
  }
  est_lande <- toupper(trimws(as.character(f$code_tfv))) %in% .CODES_TFV_NON_FORET
  est_lande[is.na(est_lande)] <- FALSE
  if (any(est_lande)) {
    # Variable locale SANS point initial : cli >= 3.4 traite `{.x}` comme un
    # style, pas comme une expression.
    codes <- .CODES_TFV_NON_FORET
    cli::cli_inform("Masque foret : {sum(est_lande)} polygone{?s} de lande
                     ({.val {codes}}) exclu{?s} (conforme ACCESSFOR).")
  }
  f[!est_lande, , drop = FALSE]
}

#' Acquiert le parcellaire cadastral (IGN WFS, optionnel)
#'
#' @inheritParams acquire_mnt
#' @return Un objet `sf` de polygones de parcelles.
#' @export
acquire_cadastre <- function(aoi, crs = 2154, cache_dir = tempdir(),
                             overwrite = FALSE, country = "FR") {
  chemin <- .chemin_cache(cache_dir, "cadastre", "gpkg")
  if (file.exists(chemin) && !overwrite) {
    return(sf::st_read(chemin, quiet = TRUE))
  }
  info <- get_layer_service("cadastre", country)
  if (is.null(info)) {
    cli::cli_abort("Couche {.val cadastre} introuvable pour le pays {.val {country}}.")
  }
  brut <- .fetch_wfs(aoi, info$typename)
  p <- .reprojeter_clip(brut, aoi, crs)
  sf::st_write(p, chemin, delete_dsn = TRUE, quiet = TRUE)
  p
}
