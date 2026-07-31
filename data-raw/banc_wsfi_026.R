# Banc `wsfi` -- CA-26.5 de la spec 026 (desserte DETECTEE sur le MNT).
#
# POURQUOI CE BANC EXISTE. Le CA-26.5 n'est pas exercable sur l'AOI oracle
# (Chastel-Nouvel) : son MNT est a 5 m, et `detecter_desserte()` avertit lui-meme
# au-dela de 1,5 m que « le micro-relief d'une plateforme ancienne ne survit pas
# a cette resolution ». Le balayage y a tourne a 3,3 fois le seuil de son propre
# garde-fou et rendu 3 lineaires a 0,4 puis zero -- exactement le motif du faux
# negatif ALSroads (0/22 a 5 m, 22/22 a 1 m). Le bloc `wsfi` porte un MNT a
# 0,50 m et 4 dalles LiDAR classees : c'est le premier site ou l'exigence de
# resolution de la spec est effectivement satisfaite.
#
# BIAIS A DECLARER, ET A NE JAMAIS TAIRE DANS UN COMPTE RENDU. `wsfi` est le jeu
# sur lequel dessertR a ete calibre. Ce banc mesure donc l'INTEGRATION, pas la
# generalisation. Le constat dessertR du 2026-07-28 y est defavorable :
# « repositionnement sur sigma_geo SEUL n'aide pas, le pathfinder accroche des
# lineaires paralleles (fosses, traces fossiles) » -- le piege du sec. 4 de la
# spec. C'est pourquoi le canal de surface est OBLIGATOIRE ici (voir plus bas).
#
# REGLE 6 (stricte) : le repertoire `wsfi` appartient a nemeton. LECTURE SEULE.
# Aucune ecriture, aucun git, aucune purge de cache n'y est faite. Toute sortie
# va dans data-raw/oracle/wsfi/ (gitignore).
#
# Usage : Rscript data-raw/banc_wsfi_026.R [seuils]
#   seuils : liste separee par des virgules. Defaut "0.4,0.5,0.6,0.7,0.8"
#            (plage prescrite par la spec 026 sec.7.1). Passer un seuil unique
#            pour un run de chronometrage : le balayage RECALCULE toute la pile
#            morphometrique et le canal de surface a chaque seuil.
.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressPackageStartupMessages({
  library(sf)
  library(terra)
  pkgload::load_all(quiet = TRUE)
})

stopifnot(requireNamespace("dessertR", quietly = TRUE))
cat("dessertR", as.character(packageVersion("dessertR")), "\n")

ARGS <- commandArgs(trailingOnly = TRUE)
SEUILS <- if (length(ARGS)) {
  as.numeric(strsplit(ARGS[[1]], ",")[[1]])
} else {
  seq(0.4, 0.8, by = 0.1)
}
stopifnot(all(is.finite(SEUILS)), all(SEUILS > 0 & SEUILS < 1))

# Le chemin est lu dans l'environnement pour que le banc reste rejouable
# ailleurs ; le defaut documente le bloc designe le 2026-07-31.
WSFI <- Sys.getenv("FA_WSFI",
  "/home/pascal/.local/share/nemeton/projects/20260717_101641_wsfi/cache/layers")
stopifnot(dir.exists(WSFI))
MNT <- file.path(WSFI, "lidar_mnt_mosaic.tif")
LAZ <- file.path(WSFI, "lidar_nuage")
stopifnot(file.exists(MNT), dir.exists(LAZ))

SORTIE <- normalizePath("data-raw/oracle/wsfi", mustWork = FALSE)
CACHE <- file.path(SORTIE, "cache")
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)

# --- 1. Emprise et MNT ------------------------------------------------------
r <- rast(MNT)
res_mnt <- max(res(r))
emprise <- st_as_sf(st_as_sfc(st_bbox(r)))
aire_km2 <- as.numeric(st_area(emprise)) / 1e6
cat(sprintf("MNT : %s m | emprise %.2f km2 | %d x %d\n",
  format(res_mnt), aire_km2, nrow(r), ncol(r)))
# La raison d'etre du banc : sans cette ligne verte, la mesure ne vaut rien.
if (res_mnt > 1.5) {
  stop("MNT a ", res_mnt, " m : ce banc EXISTE parce que 5 m ne convient pas.")
}

# --- 2. Reference BD TOPO (spec 024) ----------------------------------------
# `echouer` : decision 2 du sec.7 de la spec 027. Un banc publie des chiffres ;
# un cache perime y est plus grave qu'ailleurs. Un cache absent ne declenche
# rien (le controle ne s'applique qu'a un fichier existant).
desserte <- acquire_desserte(emprise, cache_dir = CACHE,
  politique_cache = "echouer")
km_ref <- sum(as.numeric(st_length(desserte))) / 1000
cat(sprintf("reference : %d objets | %.2f km | %.2f km/km2\n",
  nrow(desserte), km_ref, km_ref / aire_km2))
print(table(desserte$classe, useNA = "ifany"))
if ("nature" %in% names(desserte)) print(table(desserte$nature, useNA = "ifany"))

# --- 3. Surface reellement explorable ---------------------------------------
# Le controle qui a REFUTE l'explication « la dalle est saturee » sur
# Chastel-Nouvel : hors du corridor de 15 m il y restait 83,7 % de l'emprise.
# On le publie ici aussi, pour que le denominateur du CA-26.5 soit explicite.
BUFFER_REF <- 15
corridor <- st_union(st_buffer(st_geometry(desserte), BUFFER_REF))
hors <- st_difference(st_geometry(emprise), corridor)
km2_hors <- as.numeric(st_area(hors)) / 1e6
cat(sprintf("hors corridor %d m : %.2f km2 sur %.2f (%.1f %%)\n",
  BUFFER_REF, km2_hors, aire_km2, 100 * km2_hors / aire_km2))

# --- 4. Objets connus : le recoupement vaut faux positif --------------------
# Hydrographie SANS filtre de persistance (contrairement aux obstacles) : ce
# sont precisement les ecoulements INTERMITTENTS -- fosses, drains -- que le
# micro-relief confond avec une plateforme. Les filtrer viderait la mesure de
# son objet. Limites parcellaires : meme raison.
objets <- list()
hydro <- tryCatch(
  foretaccess:::.fetch_wfs(emprise, "BDTOPO_V3:troncon_hydrographique"),
  error = function(e) {
    cat("hydro indisponible :", conditionMessage(e), "\n")
    NULL
  })
if (!is.null(hydro) && nrow(hydro)) {
  objets$hydro <- st_geometry(st_transform(hydro, st_crs(emprise)))
}
cad <- tryCatch(
  acquire_cadastre(emprise, cache_dir = CACHE, politique_cache = "echouer"),
  error = function(e) {
    cat("cadastre indisponible :", conditionMessage(e), "\n")
    NULL
  })
if (!is.null(cad) && nrow(cad)) {
  objets$limites <- st_geometry(st_cast(st_boundary(st_geometry(cad)),
    "MULTILINESTRING"))
}
connus <- if (length(objets)) {
  st_sf(objet = rep(names(objets), lengths(objets)),
    geometry = do.call(c, unname(objets)))
} else {
  NULL
}
cat("objets connus :", if (is.null(connus)) 0 else nrow(connus), "\n")
if (!is.null(connus)) print(table(connus$objet))

# --- 5. Balayage, et export des couches pour l'annotation -------------------
# `las_source` NON NULL : sans canal de surface dessertR annonce une detection
# « nettement moins sure », et c'est le canal qu'il pondere DOUBLE. Sur un jeu
# ou le pathfinder accroche deja des fosses, s'en passer serait mesurer le
# piege plutot que la detection.
#
# POURQUOI PAS `detecter_desserte_balayage()` ICI. Il rend les CHIFFRES et jette
# les geometries ; or le CA-26.5 n'est pas satisfait sans la part ANNOTEE sur
# orthophoto -- le recoupement automatique la reduit, il ne la remplace pas. Il
# faudrait donc appeler le balayage PUIS re-detecter seuil par seuil pour
# exporter : deux fois la pile morphometrique et deux fois le canal de surface,
# a 0,5 m sur 4 km2. On fait la boucle une fois, avec la meme formule de
# recoupement que la fonction exportee (dont les tests sont ailleurs).
corr <- if (!is.null(connus)) {
  st_union(st_buffer(st_geometry(connus), 10))
} else {
  NULL
}
cat("\n=== balayage :", paste(SEUILS, collapse = ", "), "===\n")
t0 <- proc.time()[["elapsed"]]
canal <- rep(NA, length(SEUILS))
lignes <- lapply(seq_along(SEUILS), function(i) {
  s <- SEUILS[[i]]
  ts <- proc.time()[["elapsed"]]
  d <- detecter_desserte(MNT, reference = desserte, las_source = LAZ,
    seuil = s, buffer_ref = BUFFER_REF, long_min = 30, emprise = NULL,
    dtm_res = 1)
  canal[[i]] <<- isTRUE(attr(d, "canal_surface"))
  km <- if (nrow(d)) sum(as.numeric(st_length(d))) / 1000 else 0
  km_rec <- if (nrow(d) && !is.null(corr)) {
    g <- st_intersection(st_geometry(d), corr)
    if (length(g)) sum(as.numeric(st_length(g))) / 1000 else 0
  } else {
    NA_real_
  }
  f <- file.path(SORTIE, sprintf("detectee_s%s.gpkg", sub("\\.", "p", s)))
  if (nrow(d)) st_write(d, f, delete_dsn = TRUE, quiet = TRUE)
  cat(sprintf("  seuil %.1f : %d lineaires | %.3f km | %.1f min\n", s, nrow(d),
    km, (proc.time()[["elapsed"]] - ts) / 60))
  data.frame(seuil = s, n = nrow(d), km = km, km_recoupe = km_rec,
    pct_recoupe = if (km > 0) 100 * km_rec / km else NA_real_)
})
bal <- do.call(rbind, lignes)
duree <- proc.time()[["elapsed"]] - t0
cat("\n--- balayage (", round(duree / 60, 1), " min ) ---\n", sep = "")
print(bal)

# --- 7. Invariants ----------------------------------------------------------
# Un banc qui n'imprime que des chiffres laisse le lecteur decider s'ils sont
# bons. On enonce donc ce qui doit tenir, y compris l'invariant de MONOTONIE :
# un seuil plus haut ne peut pas detecter PLUS.
cat("\n--- invariants ---\n")
inv <- c(
  "MNT a 1,5 m ou plus fin" = res_mnt <= 1.5,
  # CONSOMME, pas « fourni ». La premiere redaction verifiait que des .laz
  # existaient sur le disque -- un invariant qui passe A VIDE : les fichiers
  # peuvent etre la et le canal absent (lecture echouee, `dsr_sigma_surf` en
  # erreur, catalogue sans colonne `laz`), chacun etant un repli SILENCIEUX de
  # `.dsr_canaux_dalles()`. On lit desormais l'attribut que la detection pose
  # elle-meme. Meme lecon qu'en Phase B : un invariant de domaine passe a vide
  # sur du tout-NA.
  "canal de surface CONSOMME" = all(canal),
  "regime complet (emprise NULL)" = TRUE,
  "reference non vide" = nrow(desserte) > 0,
  "surface explorable > 50 %" = km2_hors / aire_km2 > 0.5,
  "objets connus mesures" = !is.null(connus) && nrow(connus) > 0,
  "km decroissant avec le seuil" = all(diff(bal$km) <= 1e-9),
  "detection non vide au seuil bas" = bal$km[[1]] > 0
)
for (n in names(inv)) cat(sprintf("  [%s] %s\n", ifelse(inv[[n]], "OK", "KO"), n))
cat("\n", sum(inv), "/", length(inv), " invariants verts\n", sep = "")

saveRDS(list(balayage = bal, res_mnt = res_mnt, aire_km2 = aire_km2,
  km2_hors = km2_hors, km_ref = km_ref, n_ref = nrow(desserte),
  duree_s = duree, invariants = inv),
  file.path(SORTIE, "banc_wsfi_026.rds"))
write.csv(bal, file.path(SORTIE, "balayage.csv"), row.names = FALSE)
cat("\nsorties :", SORTIE, "\n")
