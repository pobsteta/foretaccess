# Diagnostic : les 22,3 ha ou NOUS disons `inaccessible` et ACCESSFOR `500-1000 m`
# (skidder, AOI Chastel-Nouvel, comparaison du 2026-07-29, spec 024 CA-24.5).
#
# HYPOTHESE testee : ce sont des composantes de desserte ORPHELINES chez nous --
# des pistes (CL_SVAC=1) dont la composante connexe ne contient ni route
# forestiere (2) ni reseau public (3). ACCESSFOR a fait respecter les contraintes
# de connectivite de l'annexe p.51 par script FME PLUS des retouches manuelles :
# une piste raccrochee a la main chez eux devient desservie, alors qu'elle reste
# inaccessible chez nous. Si l'hypothese tient, c'est la spec 025 qui reglera ce
# residu, pas un ajustement de classification.
#
# Consomme `dsr_reseau()` (dessertR + igraph, hors renv) -- premiere mise en
# oeuvre du diagnostic propose en spec 025 sec.3.
#
# Usage : FA_DFCI=0 Rscript data-raw/diag_orphelines.R
.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressPackageStartupMessages({
  library(sf)
  library(terra)
  pkgload::load_all(quiet = TRUE)
})

stopifnot(requireNamespace("dessertR", quietly = TRUE),
          requireNamespace("igraph", quietly = TRUE))

CACHE <- Sys.getenv("ACCESSFOR_CACHE", "/tmp/accessfor-cache")
aoi <- st_read("data-raw/aoi.gpkg", quiet = TRUE)
DFCI <- !identical(Sys.getenv("FA_DFCI"), "0")

inp <- acquire_inputs(aoi, sources = c("mnt", "desserte", "foret"),
  cache_dir = CACHE, res_m = 5, buffer_m = 100, dfci = DFCI)
des <- inp$desserte
cat("desserte :", nrow(des), "troncons\n"); print(table(des$classe))

# --- 1. Reseau topologique : composantes et rattachement --------------------
# `reseau_public` sert de reference de rattachement : c'est le CL_SVAC=3 de
# l'annexe, la classe a laquelle une route forestiere doit etre connectee.
pub <- des[des$classe == "reseau_public", ]
traces <- do.call(rbind, lapply(seq_len(nrow(des)), function(i) {
  g <- foretaccess:::.troncon_linestring(des[i, ])
  if (is.null(g)) NULL else g
}))
cat("\ntraces LINESTRING exploitables :", nrow(traces), "/", nrow(des), "\n")

res <- tryCatch(
  dessertR::dsr_reseau(traces, reseau_public = if (nrow(pub)) st_geometry(pub) else NULL),
  error = function(e) { cat("ERREUR dsr_reseau :", conditionMessage(e), "\n"); NULL }
)
if (is.null(res)) quit(status = 0)

ar <- res$aretes
cat("\n--- reseau ---\n"); print(res$resume)
cat("\ncomposantes :", length(unique(ar$composant)), "\n")

# --- 2. Contraintes de l'annexe p.51 ----------------------------------------
# classe 1 connectee a 2 ou 3 ; classe 2 connectee a 3.
cl <- ar$classe
comp <- ar$composant
a_route <- tapply(cl %in% c("route", "reseau_public"), comp, any)
a_public <- tapply(cl == "reseau_public", comp, any)

viole <- rep(FALSE, nrow(ar))
viole[cl == "piste"] <- !a_route[as.character(comp[cl == "piste"])]
viole[cl == "route"] <- !a_public[as.character(comp[cl == "route"])]
viole[is.na(viole)] <- FALSE

long <- as.numeric(st_length(ar))
cat("\n--- contraintes d'integrite (annexe p.51) ---\n")
cat("troncons en infraction :", sum(viole), "/", nrow(ar),
    sprintf(" (%.1f km / %.1f km)\n", sum(long[viole]) / 1000, sum(long) / 1000))
print(table(classe = cl[viole]))

cat("\ncomposantes orphelines (aucune route ni reseau public) :",
    sum(!a_route), "/", length(a_route), "\n")

# --- 3. Surface potentiellement concernee ------------------------------------
# Buffer autour des composantes orphelines, intersecte avec la foret : ordre de
# grandeur de la surface qu'une reconnexion rendrait desservie.
if (any(viole)) {
  orph <- ar[viole, ]
  # 250 m : la premiere bande de distance de debardage.
  zone <- st_union(st_buffer(st_geometry(orph), 250))
  foret_u <- st_union(st_geometry(inp$foret))
  inter <- st_intersection(zone, foret_u)
  ha <- sum(as.numeric(st_area(inter))) / 1e4
  cat(sprintf("\nforet a moins de 250 m d'un troncon en infraction : %.1f ha\n", ha))
  cat("(a confronter aux 22,3 ha du bloc `inaccessible` x `500-1000` de la\n")
  cat(" matrice skidder -- ordre de grandeur, pas une egalite attendue)\n")
  st_write(orph, "data-raw/oracle/aoi/troncons_orphelins.gpkg",
    delete_dsn = TRUE, quiet = TRUE)
  cat("\nsortie : data-raw/oracle/aoi/troncons_orphelins.gpkg\n")
} else {
  cat("\nAUCUNE infraction : l'hypothese des composantes orphelines est INFIRMEE\n")
  cat("sur cette AOI -- le residu de 22,3 ha vient d'ailleurs.\n")
}
