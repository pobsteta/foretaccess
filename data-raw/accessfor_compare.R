# Livrable sec. 5 du brief nemeton (specs/brief-foretaccess-accessfor.md, cote
# nemeton) : matrice de confusion classes_debardage() vs la couche ACCESSFOR de
# l'IGN, sur l'AOI Chastel-Nouvel (dep 48, deja instrumentee).
#
# Reseau (WFS ACCESSFOR + acquisition IGN) -> data-raw, hors CI. La MECANIQUE de
# comparaison (rasterisation near, intersection des masques, matrice) vit dans
# comparer_accessfor() (R/accessfor.R), testee hors ligne. Ici on ne fait que
# CABLER les vraies donnees.
#
#   Rscript data-raw/accessfor_compare.R
#   FA_DFCI=0 Rscript data-raw/accessfor_compare.R   # sans le flag DFCI (OSM)
#
# On compare les DEUX variantes de masque ACCESSFOR (defaut ET MASQUE-FORETV3,
# decision utilisateur) : l'ecart entre les deux borne l'artefact de masque.

.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressMessages({
  library(sf)
  library(terra)
  library(httr2)
  pkgload::load_all(quiet = TRUE)
})

WFS <- "https://data.geopf.fr/wfs/ows"
DEP <- "48"

# Recupere les polygones ACCESSFOR d'une couche sur l'emprise (bbox en 2154),
# filtres par departement. Pagine si besoin (COUNT max IGN = 5000 / page).
accessfor_couche <- function(couche, bbox_2154, variante = "") {
  ns <- if (nzchar(variante)) {
    paste0("IGNF_ACCESSIBILITE-PHYSIQUE-FORETS-", variante)
  } else {
    "IGNF_ACCESSIBILITE-PHYSIQUE-FORETS-"
  }
  typ <- paste0(ns, ":", couche)
  b <- as.numeric(bbox_2154)
  # BBOX en 2154 (EPSG:2154). ACCESSFOR est servi en Lambert-93.
  bbox_str <- sprintf("%f,%f,%f,%f,EPSG:2154", b[1], b[2], b[3], b[4])

  out <- list()
  start <- 0L
  repeat {
    req <- request(WFS) |>
      req_url_query(
        SERVICE = "WFS", VERSION = "2.0.0", REQUEST = "GetFeature",
        TYPENAMES = typ, SRSNAME = "EPSG:2154",
        BBOX = bbox_str, COUNT = "5000", STARTINDEX = start, OUTPUTFORMAT = "application/json"
      )
    tf <- tempfile(fileext = ".json")
    resp <- tryCatch(req_perform(req), error = function(e) NULL)
    if (is.null(resp)) break
    writeBin(resp_body_raw(resp), tf)
    part <- tryCatch(sf::st_read(tf, quiet = TRUE), error = function(e) NULL)
    if (is.null(part) || nrow(part) == 0) break
    out[[length(out) + 1]] <- part
    if (nrow(part) < 5000) break
    start <- start + 5000L
  }
  if (!length(out)) {
    return(NULL)
  }
  d <- do.call(rbind, out)
  sf::st_transform(d, 2154)
}

# --- 1. Entrees ForetAccess sur l'AOI ---------------------------------------
aoi <- st_read("data-raw/aoi.gpkg", quiet = TRUE)
# Cache PERSISTANT : l'acquisition IGN (MNT LiDAR fin) est lourde, on la reutilise
# d'un run a l'autre. Surchargeable via ACCESSFOR_CACHE.
cache <- Sys.getenv("ACCESSFOR_CACHE", "/tmp/accessfor-cache")
dir.create(cache, recursive = TRUE, showWarnings = FALSE)
cat("== Acquisition IGN + pretraitement (AOI Chastel-Nouvel) ==\n"); flush.console()
# FA_DFCI=0 saute le flag DFCI, comme oracle_aoi.R et oracle_aoi_ugf.R :
# acquire_dfci() ne met rien en cache quand OSM ECHOUE (throttling Overpass), et
# le flag ne sert a rien ici -- ACCESSFOR ne modelise ni DFCI ni camion.
DFCI <- !identical(Sys.getenv("FA_DFCI"), "0")
if (!DFCI) cat("  DFCI         SAUTE (FA_DFCI=0)\n")
inp <- acquire_inputs(aoi, sources = c("mnt", "desserte", "foret"),
  cache_dir = cache, res_m = 5, buffer_m = 100, dfci = DFCI)
pre <- preprocess(inp$mnt, inp$desserte, inp$foret)
cat("  pretraitement OK :", terra::ncell(pre$mnt), "cellules\n"); flush.console()

# classes_debardage AVEC `pre` : sinon la classe `inexploitable` (= ACCESSFOR
# class 2) manque et fausserait la comparaison.
cl_sk <- classes_debardage(skidder(pre), pre)
cl_po <- classes_debardage(porteur(pre), pre)
cat("  moteurs OK (skidder + porteur)\n"); flush.console()

bbox_2154 <- st_bbox(pre$mnt)

# --- 2. Comparaison par engin x variante de masque --------------------------
comparer <- function(cl, couche, variante) {
  cat("  WFS ACCESSFOR :", couche, if (nzchar(variante)) variante else "defaut", "...\n")
  flush.console()
  af <- accessfor_couche(couche, bbox_2154, variante)
  if (is.null(af)) {
    cat("  [", couche, variante, "] aucune donnee ACCESSFOR sur l'emprise\n")
    return(invisible(NULL))
  }
  cmp <- comparer_accessfor(cl, af)
  cat("\n--- ", couche, " | masque ", if (nzchar(variante)) variante else "defaut", " ---\n", sep = "")
  cat(sprintf("accord global (9 classes)    : %.1f %%\n", 100 * cmp$accord_global))
  cat(sprintf("accord agrege (access./non)  : %.1f %%\n", 100 * cmp$accord_agrege))
  cat(sprintf("surface comparee : %.1f ha (foret hors ACCESSFOR : %.1f ; ACCESSFOR hors notre foret : %.1f)\n",
    cmp$surface_ha$commun, cmp$surface_ha$notre_seul, cmp$surface_ha$accessfor_seul))
  cat("Matrice de confusion (ha) -- lignes = foretaccess, colonnes = ACCESSFOR :\n")
  print(round(cmp$matrice, 1))
  invisible(cmp)
}

for (v in c("", "MASQUE-FORETV3")) {
  comparer(cl_sk, "acces_skidder", v)
  comparer(cl_po, "acces_porteur", v)
}

cat("\nLecture : l'accord AGREGE (accessible/non) est le chiffre robuste. Un\n")
cat("desaccord sur les bandes lointaines est attendu (parametrage engin, desserte\n")
cat("de reference) ; un flip accessible<->inaccessible est a instruire. L'ecart\n")
cat("entre les deux variantes de masque borne l'artefact de masque (sec. 4a).\n")
