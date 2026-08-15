# CA-28.3 : `comparer_desserte_osm()` reproduit-elle la table du sec. 1 de la spec 028 ?
#
# La mesure d'origine (2026-07-30) a ete faite par `diag_osm_vs_bdtopo.R`, un
# script ad hoc qui calculait le recoupement a la main. Le CA demande que la
# FONCTION rende la meme chose sur les memes entrees -- sans quoi la table de la
# spec documente un script mort et pas le paquet.
#
# Entrees construites a l'identique du script d'origine :
#   - BD TOPO acquise sur AOI + 100 m, puis restreinte aux troncons qui
#     INTERSECTENT l'AOI (troncons entiers, pas clippes) ;
#   - OSM en UNE requete `highway` toutes valeurs, meme restriction.
# `acquire_desserte_osm()` n'est deliberement PAS utilisee ici : elle filtre les
# types (`path` et `tertiary` exclus) et CLIPPE sur l'AOI, deux ecarts qui
# rendraient la comparaison a la table impossible.
#
# Usage : Rscript data-raw/ca_28_3_table_sec1.R
.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressPackageStartupMessages({
  library(sf)
  pkgload::load_all(quiet = TRUE)
})

AOI <- st_read("data-raw/aoi.gpkg", quiet = TRUE)
CACHE <- Sys.getenv("ACCESSFOR_CACHE", "/tmp/accessfor-cache")
CORRIDOR_M <- 15

# Table du sec. 1 telle qu'ecrite dans la spec (mesure du 2026-07-30).
REF_OSM <- data.frame(
  groupe = c("track", "path", "unclassified", "tertiary", "service+residential"),
  total_km = c(40.28, 17.53, 8.47, 6.59, 0.48),
  hors_km = c(13.52, 14.09, 1.06, 3.79, 0.05)
)
REF_BDT <- data.frame(
  groupe = c("piste", "route", "reseau_public"),
  hors_km = c(5.40, 0.00, 0.01)
)
REF_TOT <- c(bdtopo_n = 169, bdtopo_km = 44.64, osm_n = 115, osm_km = 73.35,
             osm_couvert_pct = 55.7)

# --- 1. Entrees -------------------------------------------------------------
bdt <- acquire_desserte(st_buffer(AOI, 100), cache_dir = CACHE)
bdt <- bdt[lengths(st_intersects(st_geometry(bdt), st_geometry(AOI))) > 0, ]

# Cache local du brut OSM : Overpass bride des qu'on relance, et la mesure doit
# rester rejouable sans dependre de l'humeur d'une instance. `OSM_REFETCH=1`
# force la reacquisition.
osm_brut <- file.path(CACHE, "ca283_osm_highway_brut.gpkg")
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)
if (file.exists(osm_brut) && !nzchar(Sys.getenv("OSM_REFETCH"))) {
  lignes <- st_read(osm_brut, quiet = TRUE)
  cat(sprintf("OSM : relu du cache %s\n", osm_brut))
} else {
  bb <- st_bbox(st_transform(AOI, 4326))
  osm <- foretaccess:::.fetch_osm(bb, key = "highway", timeout = 180)
  if (is.null(osm$osm_lines) || nrow(osm$osm_lines) == 0) {
    stop("Overpass n'a rien rendu -- relancer plus tard (bride d'instance).")
  }
  lignes <- st_transform(osm$osm_lines, 2154)
  lignes <- lignes[lengths(st_intersects(st_geometry(lignes), st_geometry(AOI))) > 0, ]
  lignes <- lignes[, c("highway",
    intersect(c("tracktype", "surface", "access"), names(lignes)))]
  st_write(lignes, osm_brut, delete_dsn = TRUE, quiet = TRUE)
}

cat(sprintf("\nBD TOPO : %d troncons (ref %d) | %.2f km (ref %.2f)\n",
  nrow(bdt), REF_TOT[["bdtopo_n"]],
  sum(as.numeric(st_length(bdt))) / 1000, REF_TOT[["bdtopo_km"]]))
cat(sprintf("OSM     : %d lignes    (ref %d) | %.2f km (ref %.2f)\n",
  nrow(lignes), REF_TOT[["osm_n"]],
  sum(as.numeric(st_length(lignes))) / 1000, REF_TOT[["osm_km"]]))

# --- 2. LA fonction ---------------------------------------------------------
t0 <- Sys.time()
cmp <- comparer_desserte_osm(bdt, lignes, corridor_m = CORRIDOR_M)
cat(sprintf("\ncomparer_desserte_osm() : %.1f s\n",
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))
print(cmp)

# --- 3. Confrontation a la table du sec. 1 --------------------------------------
# `service` et `residential` sont une seule ligne dans la spec : on regroupe.
o <- cmp$osm
o$groupe[o$groupe %in% c("service", "residential")] <- "service+residential"
o <- aggregate(cbind(total_km, hors_km) ~ groupe, data = o, FUN = sum)

cat("\n=== sec. 1.1 -- lineaire OSM par type (km) ===\n")
t1 <- merge(REF_OSM, o, by = "groupe", all.x = TRUE, suffixes = c("_ref", "_obt"))
t1[is.na(t1)] <- 0
t1$d_total <- round(t1$total_km_obt - t1$total_km_ref, 2)
t1$d_hors <- round(t1$hors_km_obt - t1$hors_km_ref, 2)
print(t1[order(-t1$total_km_ref), ], row.names = FALSE)

cat("\n  types OSM absents de la table du sec. 1 (apparus depuis) :\n")
sup <- cmp$osm[!cmp$osm$groupe %in% c(REF_OSM$groupe, "service", "residential"), ]
if (nrow(sup)) print(sup, row.names = FALSE) else cat("  (aucun)\n")

cat("\n=== sec. 1.2 -- lineaire BD TOPO hors corridor OSM (km) ===\n")
t2 <- merge(REF_BDT, cmp$bdtopo[, c("groupe", "hors_km")], by = "groupe",
            all.x = TRUE, suffixes = c("_ref", "_obt"))
t2[is.na(t2)] <- 0
t2$ecart <- round(t2$hors_km_obt - t2$hors_km_ref, 2)
print(t2, row.names = FALSE)

cat(sprintf("\n=== part du lineaire OSM DEJA dans le corridor : %.1f %% (ref %.1f %%) ===\n",
  cmp$resume[["osm_couvert_pct"]], REF_TOT[["osm_couvert_pct"]]))

# --- 4. Ce que la table compte, desormais inspectable ------------------------
# C'est l'apport de la 2.4.0 : on ne verifie plus seulement des nombres, on peut
# ouvrir la couche et regarder les troncons comptes.
dir.create("data-raw/oracle/aoi", recursive = TRUE, showWarnings = FALSE)
st_write(cmp$osm_hors_corridor, "data-raw/oracle/aoi/ca283_osm_hors_corridor.gpkg",
  delete_dsn = TRUE, quiet = TRUE)
st_write(cmp$bdtopo_hors_corridor, "data-raw/oracle/aoi/ca283_bdtopo_hors_corridor.gpkg",
  delete_dsn = TRUE, quiet = TRUE)
cat("\nsorties : data-raw/oracle/aoi/ca283_{osm,bdtopo}_hors_corridor.gpkg\n")
cat(sprintf("  OSM hors corridor    : %d troncons, %.2f km\n",
  nrow(cmp$osm_hors_corridor), sum(cmp$osm_hors_corridor$hors_m) / 1000))
cat(sprintf("  BD TOPO hors corridor: %d troncons, %.2f km\n",
  nrow(cmp$bdtopo_hors_corridor), sum(cmp$bdtopo_hors_corridor$hors_m) / 1000))

cat("\nRAPPEL : OSM est une source VIVANTE. Un ecart sur un type n'invalide pas la\n")
cat("fonction -- il peut signaler une edition amont depuis le 2026-07-30. Ce qui\n")
cat("est teste ici, c'est que la fonction rend LA table, pas qu'OSM soit fige.\n")

# --- 5. Contre-epreuve : d'ou vient l'ecart ? --------------------------------
# La BD TOPO acquise aujourd'hui porte une classe `hors_desserte` (sentiers,
# rond-points, liaisons -- CL_SVAC = 0) que la mesure du 2026-07-30 n'avait pas :
# `garder_hors_desserte = TRUE` date du jour meme (6b9df26 / 451935d). Ces
# troncons ELARGISSENT le corridor, donc reduisent mecaniquement le lineaire OSM
# "hors corridor" -- sans que la fonction y soit pour rien.
#
# Si l'hypothese est bonne, retirer cette classe doit rendre la table du sec. 1 au
# centieme pres.
bdt3 <- bdt[bdt$classe %in% c("piste", "route", "reseau_public"), ]
cat(sprintf("\n=== CONTRE-EPREUVE : BD TOPO sans `hors_desserte` ===\n"))
cat(sprintf("BD TOPO : %d troncons (ref %d) | %.2f km (ref %.2f)\n",
  nrow(bdt3), REF_TOT[["bdtopo_n"]],
  sum(as.numeric(st_length(bdt3))) / 1000, REF_TOT[["bdtopo_km"]]))

cmp3 <- comparer_desserte_osm(bdt3, lignes, corridor_m = CORRIDOR_M)
o3 <- cmp3$osm
o3$groupe[o3$groupe %in% c("service", "residential")] <- "service+residential"
o3 <- aggregate(cbind(total_km, hors_km) ~ groupe, data = o3, FUN = sum)
t3 <- merge(REF_OSM, o3, by = "groupe", all.x = TRUE, suffixes = c("_ref", "_obt"))
t3[is.na(t3)] <- 0
t3$d_total <- round(t3$total_km_obt - t3$total_km_ref, 2)
t3$d_hors <- round(t3$hors_km_obt - t3$hors_km_ref, 2)
print(t3[order(-t3$total_km_ref), c("groupe", "total_km_ref", "total_km_obt",
                                    "d_total", "hors_km_ref", "hors_km_obt",
                                    "d_hors")], row.names = FALSE)
cat(sprintf("\npart du lineaire OSM DEJA dans le corridor : %.1f %% (ref %.1f %%)\n",
  cmp3$resume[["osm_couvert_pct"]], REF_TOT[["osm_couvert_pct"]]))
cat(sprintf("track hors corridor : %d troncons, %.2f km (CA-28.5 : 24 troncons, 13,41 km)\n",
  sum(cmp3$osm_hors_corridor$highway == "track"),
  sum(cmp3$osm_hors_corridor$hors_m[cmp3$osm_hors_corridor$highway == "track"]) / 1000))
