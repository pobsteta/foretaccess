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

.fetch_wfs <- function(aoi, typename) {
  .require_pkg("happign")
  happign::get_wfs(x = aoi, layer = typename)
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
  cli::cli_abort("Aucune couche MNT ne couvre l'emprise (essaye : {.val {couches}}).")
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
#'   (CL_SVAC = 0) dans la sortie, au lieu de les retirer ? Défaut `FALSE` —
#'   la couche Sylvaccess d'ACCESSFOR ne contient que les classes 1/2/3.
#'   `TRUE` sert à inspecter ce qui a été écarté ; **ne pas** passer une telle
#'   couche à [preprocess()].
#' @return Un objet `sf` de lignes avec un champ `classe`.
#' @export
acquire_desserte <- function(aoi, crs = 2154, cache_dir = tempdir(),
                             overwrite = FALSE, country = "FR",
                             classification = c("accessfor", "clsvac", "heuristique"),
                             garder_hors_desserte = FALSE) {
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
    cli::cli_inform("Desserte : {sum(hd)} troncon{?s} hors desserte
                     (CL_SVAC = 0) retire{?s} -- {.val {unique(d$classe[!hd])}} conserve{?s}.")
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
