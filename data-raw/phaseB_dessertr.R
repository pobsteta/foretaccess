# Banc Phase B (spec 023 sec. 7) : validation de l'INTEGRATION dessertR dans
# foretaccess. Rejoue le protocole de la spec 020 sec. 6bis -- dalle LiDAR HD IGN
# `LHD_FXX_0737_6385` (Chastel-Nouvel, Lozere) + desserte BD TOPO -- mais avec le
# moteur `dessertr` au lieu d'ALSroads, et publie les invariants attendus.
#
# Prerequis :
#   * dessertR installe HORS renv (lib globale 4.6) -- cf. .libPaths ci-dessous ;
#   * la dalle .copc.laz dans data-raw/oracle/aoi/cache/lidar_nuage/ (~260 Mo,
#     jamais versionnee : data-raw/oracle/ est gitignore).
#     URL : https://data.geopf.fr/telechargement/download/LiDARHD-NUALID/
#           NUALHD_1-0__LAZ_LAMB93_MN_2024-12-13/
#           LHD_FXX_0737_6385_PTS_LAMB93_IGN69.copc.laz
#
# Usage : Rscript data-raw/phaseB_dessertr.R [res_mnt_m]
#   res_mnt_m : resolution du MNT servi a dsr_measure (defaut 1). Le MNT LiDAR HD
#   descend a 0.5 : la MESURE s'affine, mais la grille morphometrique reste a 1 m
#   (dtm_res), conformement a ?dsr_grille_reference -- « descendre a 0.5
#   uniquement pour la mesure fine ». Cache et sorties sont suffixes par la
#   resolution : les deux runs coexistent et se comparent.
.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressPackageStartupMessages({
  library(sf)
  library(terra)
  pkgload::load_all(quiet = TRUE)
})

stopifnot(requireNamespace("dessertR", quietly = TRUE))
cat("dessertR", as.character(packageVersion("dessertR")), "\n")

ARGS <- commandArgs(trailingOnly = TRUE)
RES_MNT <- if (length(ARGS)) as.numeric(ARGS[[1]]) else 1
stopifnot(is.finite(RES_MNT), RES_MNT > 0)
SUFFIXE <- sub("\\.", "p", format(RES_MNT, trim = TRUE)) # 0.5 -> "0p5"
cat("resolution MNT :", RES_MNT, "m\n")

RACINE <- normalizePath("data-raw/oracle/aoi", mustWork = TRUE)
LAZ <- file.path(RACINE, "cache", "lidar_nuage",
  "LHD_FXX_0737_6385_PTS_LAMB93_IGN69.copc.laz")
stopifnot(file.exists(LAZ))
# Cache dedie ET suffixe par la resolution : ne pas ecraser le MNT 5 m du banc
# oracle, ni le MNT d'un run a une autre resolution.
CACHE <- file.path(RACINE, "phaseB", paste0("cache_", SUFFIXE))
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)

# --- 1. Emprise = la dalle -------------------------------------------------
# Protocole spec 020 : les troncons ENTIEREMENT dans la dalle sont mesurables.
dalle <- st_as_sfc(st_bbox(c(xmin = 737000, ymin = 6384000,
                             xmax = 738000, ymax = 6385000), crs = 2154))
dalle <- st_sf(geom = dalle)

# --- 2. Entrees : desserte BD TOPO + MNT ------------------------------------
# MNT a 1 m ou plus fin EXIGE (spec 020 sec. 6bis : le 5 m rendait des largeurs NA).
desserte <- acquire_desserte(dalle, cache_dir = CACHE)
mnt1 <- acquire_mnt(dalle, res_m = RES_MNT, res_lidar_m = RES_MNT, cache_dir = CACHE)

cat(sprintf("desserte : %d troncons | MNT : %s\n", nrow(desserte),
  paste(res(rast(mnt1)), collapse = " x ")))
print(table(desserte$classe))

# --- 3. Mesure dessertR -----------------------------------------------------
t0 <- proc.time()[["elapsed"]]
dl <- acquire_desserte_lidar(desserte, las_source = LAZ, mnt = mnt1,
  moteur = "dessertr", cache_dir = CACHE, dtm_res = 1, long_min_m = 40)
duree <- proc.time()[["elapsed"]] - t0

cat("\n=== PHASE B : moteur", attr(dl, "moteur"), "| NDP", attr(dl, "ndp"),
    "|", round(duree / 60, 1), "min ===\n")
cat("bilan :\n"); print(attr(dl, "bilan"))

# --- 4. Invariants (spec 020 sec. 6bis) -------------------------------------
mesures <- dl[!is.na(dl$largeur_carrossable_m), ]
cat("\n--- largeurs mesurees (n =", nrow(mesures), ") ---\n")
print(summary(mesures$largeur_carrossable_m))
cat("\nlargeur de plateforme :\n"); print(summary(mesures$largeur_plateforme_m))
cat("\npente en long (%) :\n"); print(summary(mesures$pente_pct))
cat("\netat_classe (4 classes) :\n"); print(table(dl$etat_classe, useNA = "ifany"))
cat("\nscore_lidar :\n"); print(summary(dl$score_lidar))

cat("\n--- colonnes BONUS dessertR ---\n")
for (col in c("etat_dessertr", "devers", "fosses", "rayon_courbure_p05",
              "apte_grumier", "motif_inaptitude")) {
  cat("\n", col, " (", sum(!is.na(dl[[col]])), " non-NA) :\n", sep = "")
  v <- dl[[col]]
  if (is.numeric(v)) print(summary(v)) else print(table(v, useNA = "ifany"))
}

# --- 5. Invariants de coherence (assertions, pas seulement des chiffres) ----
cat("\n--- invariants ---\n")
# COMPLETUDE d'abord : un invariant de domaine ("etat_classe dans 1:4") passe a
# VIDE sur du tout-NA. C'est ce qui avait rendu un 9/9 vert avec trois colonnes
# entierement NA au premier passage.
non_na <- function(col) sum(!is.na(dl[[col]])) > 0
inv <- c(
  "contrat de colonnes" = all(c("largeur_carrossable_m", "largeur_plateforme_m",
    "pente_pct", "etat_classe", "score_lidar") %in% names(dl)),
  "colonnes bonus presentes" = all(c("etat_dessertr", "devers", "fosses",
    "rayon_courbure_p05", "apte_grumier", "motif_inaptitude") %in% names(dl)),
  "COMPLETUDE largeur_carrossable_m" = non_na("largeur_carrossable_m"),
  "COMPLETUDE pente_pct" = non_na("pente_pct"),
  "COMPLETUDE etat_classe" = non_na("etat_classe"),
  "COMPLETUDE etat_dessertr" = non_na("etat_dessertr"),
  "COMPLETUDE score_lidar" = non_na("score_lidar"),
  "COMPLETUDE devers" = non_na("devers"),
  "COMPLETUDE fosses" = non_na("fosses"),
  "COMPLETUDE rayon_courbure_p05" = non_na("rayon_courbure_p05"),
  "COMPLETUDE apte_grumier" = non_na("apte_grumier"),
  "nrow preserve" = nrow(dl) == nrow(desserte),
  "moteur = dessertr" = identical(attr(dl, "moteur"), "dessertr"),
  "NDP 1" = identical(attr(dl, "ndp"), 1L),
  "au moins un troncon mesure" = nrow(mesures) > 0,
  "largeurs plausibles (0-15 m)" = all(is.na(mesures$largeur_carrossable_m) |
    (mesures$largeur_carrossable_m > 0 & mesures$largeur_carrossable_m < 15)),
  "carrossable <= plateforme" = all(is.na(mesures$largeur_carrossable_m) |
    is.na(mesures$largeur_plateforme_m) |
    mesures$largeur_carrossable_m <= mesures$largeur_plateforme_m + 1e-6),
  "etat_classe dans 1:4" = all(is.na(dl$etat_classe) | dl$etat_classe %in% 1:4),
  "etat_dessertr = libelles dessertR" = all(is.na(dl$etat_dessertr) |
    dl$etat_dessertr %in% c("en_service", "abandonnee", "trouee_sans_route",
      "hors_route")),
  "apte_grumier logique" = is.logical(dl$apte_grumier),
  "score_lidar >= 0" = all(is.na(dl$score_lidar) | dl$score_lidar >= 0)
)
# Matrice de confusion d'etat x classe de desserte (livrable Phase B, spec 023).
cat("\n--- etat_classe x classe de desserte ---\n")
print(table(etat = dl$etat_dessertr, classe = dl$classe, useNA = "ifany"))
for (n in names(inv)) cat(sprintf("  [%s] %s\n", ifelse(inv[[n]], "OK", "KO"), n))
cat("\n", sum(inv), "/", length(inv), " invariants verts\n", sep = "")

saveRDS(dl, file.path(RACINE, "phaseB", paste0("dessertr_", SUFFIXE, ".rds")))
st_write(dl, file.path(RACINE, "phaseB", paste0("dessertr_", SUFFIXE, ".gpkg")),
  delete_dsn = TRUE, quiet = TRUE)
cat("\nsorties : ", file.path(RACINE, "phaseB"), "\n")
