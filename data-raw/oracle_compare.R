# Harnais de confrontation ForetAccess <-> Sylvaccess v3.6.
#
# Compare cellule a cellule, sur la meme grille, les sorties des deux moteurs.
# L'objectif n'est pas un score mais un diagnostic : OU et COMMENT on diverge.
# Pour chaque couche on produit l'accord binaire, la matrice de confusion des
# classes, et pour les distances continues la distribution des ecarts.
#
#   Rscript data-raw/oracle_compare.R [chemin_resultats_sylvaccess]

.libPaths(c(.libPaths(), "~/R/x86_64-pc-linux-gnu-library/4.6"))
suppressPackageStartupMessages({
  library(terra)
  library(sf)
})

# Usage : Rscript data-raw/oracle_compare.R [dir_sylvaccess] [dir_foretaccess] [run]
#   run : suffixe des dossiers Sylvaccess (`Skidder_<run>`, ...). Defaut "last".
#
# Sylvaccess N'ECRASE PAS ses sorties : il INCREMENTE. Relancer sur le meme banc
# cree Skidder_2, Skidder_3... et le `_1` reste la toute premiere execution --
# potentiellement tres ancienne, sur des entrees qui n'ont plus cours. Comparer
# le `_1` par defaut, c'est confronter nos moteurs a un oracle perime sans que
# rien ne le signale. D'ou "last" en defaut, et un suffixe explicite possible.
args <- commandArgs(trailingOnly = TRUE)
SYLVA <- if (length(args) >= 1) args[1] else "~/dev/sylvaccess-upstream/test/ColduPre/Results"
FA <- if (length(args) >= 2) args[2] else "data-raw/oracle/coldupre/foretaccess"
RUN <- if (length(args) >= 3) args[3] else "last"
SYLVA <- path.expand(SYLVA)

# Dossier d'un module Sylvaccess pour le run demande. `run = "last"` prend le
# suffixe NUMERIQUE le plus eleve present pour CE module -- les modules peuvent
# avoir ete relances un nombre different de fois.
dir_run <- function(sylva, module, run = RUN) {
  if (!identical(run, "last")) {
    return(file.path(sylva, paste0(module, "_", run)))
  }
  cands <- list.dirs(sylva, recursive = FALSE, full.names = FALSE)
  n <- suppressWarnings(as.integer(sub(paste0("^", module, "_"), "", cands)))
  ok <- grepl(paste0("^", module, "_\\d+$"), cands) & !is.na(n)
  if (!any(ok)) {
    return(file.path(sylva, paste0(module, "_1"))) # absent : laisse echouer en aval
  }
  file.path(sylva, cands[ok][which.max(n[ok])])
}

cat("Oracle Sylvaccess :", SYLVA, "| run :", RUN, "\n")
for (m in c("Skidder", "Porteur", "Cable", "DFCI")) {
  d <- dir_run(SYLVA, m)
  if (dir.exists(d)) cat(sprintf("  %-8s -> %s\n", m, basename(d)))
}

# PIEGE : Foret_accessible.tif vaut 1 sur les accessibles et NoData (0) ailleurs,
# idem pour Foret_inaccessible.tif. Lues telles quelles, les cellules
# inaccessibles arrivent en NA et disparaissent de toute comparaison : on ne
# mesurerait alors que l'accord sur les cellules que Sylvaccess juge deja
# accessibles, et l'on ne pourrait JAMAIS se voir trop optimiste. D'ou la
# binarisation explicite, NA -> FALSE.
# Le code positif n'est pas le meme partout : `Foret_accessible.tif` vaut 1,
# `Zone_accessible.tif` (cable) vaut 2. On teste donc "non-NA et > 0", jamais
# "== 1" -- sinon la couche entiere passe a FALSE et l'on ne peut plus JAMAIS se
# voir trop conservateur.
vrai_ou_faux <- function(r) {
  v <- !is.na(r) & (r > 0)
  v[is.na(v)] <- FALSE
  v
}

# La forêt borne toute comparaison : hors forêt, les deux moteurs ne repondent
# pas a la meme question. Elle est l'union accessible U inaccessible.
masque_foret <- function(r_sylva_acc, r_sylva_inacc) {
  vrai_ou_faux(r_sylva_acc) | vrai_ou_faux(r_sylva_inacc)
}

# --- Accord sur une couche binaire ------------------------------------------
# `nous` et `eux` sont des rasters logiques deja binarises (NA -> FALSE).
accord_binaire <- function(nous, eux, dans, nom) {
  dedans <- terra::values(dans)
  n <- terra::values(nous)[dedans]
  e <- terra::values(eux)[dedans]
  n[is.na(n)] <- FALSE
  e[is.na(e)] <- FALSE
  n <- n > 0
  e <- e > 0
  tab <- table(foretaccess = n, sylvaccess = e)
  accord <- sum(n == e) / length(n)
  cat(sprintf("\n== %s ==\n", nom))
  cat(sprintf("  accord      : %.2f %% (%d / %d cellules forestieres)\n",
              100 * accord, sum(n == e), length(n)))
  faux_pos <- sum(n & !e)
  faux_neg <- sum(!n & e)
  cat(sprintf("  nous OUI / eux NON : %6d cellules (%.2f %%)  <- trop optimiste\n",
              faux_pos, 100 * faux_pos / length(n)))
  cat(sprintf("  nous NON / eux OUI : %6d cellules (%.2f %%)  <- trop conservateur\n",
              faux_neg, 100 * faux_neg / length(n)))

  # JACCARD sur la classe POSITIVE : intersection / union des « accessible ».
  #
  # L'accord brut ci-dessus compte TOUTES les cellules forestieres, y compris
  # celles ou les deux moteurs disent non. Sur une classe rare il est
  # structurellement optimiste et peut masquer une degradation. Mesure du
  # 2026-07-30 sur le cable : 98,36 % d'accord brut sur ColduPre (5,9 % de foret
  # accessible) contre 93,65 % sur l'AOI (67 % accessible) -- d'ou j'avais
  # conclu a tort a un sur-ajustement au banc de calibrage. En Jaccard le
  # classement s'INVERSE : 79,5 % sur ColduPre contre 90,9 % sur l'AOI.
  #
  # Meme piege que les invariants de la Phase B qui passaient a vide sur du
  # tout-NA : une metrique qui ne peut pas mal se comporter ne mesure rien.
  union_pos <- sum(n | e)
  jaccard <- if (union_pos > 0) sum(n & e) / union_pos else NA_real_
  cat(sprintf("  Jaccard (classe accessible) : %.1f %%  [%d communs / %d union]",
              100 * jaccard, sum(n & e), union_pos))
  cat(sprintf("   -- part accessible : nous %.1f %%, eux %.1f %%\n",
              100 * mean(n), 100 * mean(e)))
  print(tab)
  invisible(list(accord = accord, jaccard = jaccard, faux_pos = faux_pos,
                 faux_neg = faux_neg, table = tab))
}

# --- Ecart sur une couche continue ------------------------------------------
ecart_continu <- function(nous, eux, dans, nom, nodata = c(-9999, 0)) {
  n <- terra::values(nous)[terra::values(dans)]
  e <- terra::values(eux)[terra::values(dans)]
  e[e %in% nodata] <- NA
  ok <- !is.na(n) & !is.na(e)
  n <- n[ok]; e <- e[ok]
  if (!length(n)) { cat(sprintf("\n== %s == (aucune cellule comparable)\n", nom)); return(invisible(NULL)) }
  d <- n - e
  cat(sprintf("\n== %s == (%d cellules)\n", nom, length(n)))
  cat(sprintf("  nous   : mediane %8.1f  moyenne %8.1f  max %9.1f\n",
              stats::median(n), mean(n), max(n)))
  cat(sprintf("  eux    : mediane %8.1f  moyenne %8.1f  max %9.1f\n",
              stats::median(e), mean(e), max(e)))
  cat(sprintf("  ecart  : mediane %8.1f  moyenne %8.1f  |ecart| p95 %8.1f\n",
              stats::median(d), mean(d), stats::quantile(abs(d), 0.95)))
  cat(sprintf("  identique a 1 m pres : %.2f %%\n", 100 * mean(abs(d) < 1)))
  invisible(list(ecart = d))
}

# PIEGE : Sylvaccess n'ecrit pas toutes ses sorties sur la meme grille. Le moteur
# cable travaille sur une fenetre bufferisee autour des lignes de depart
# (`buff_ar`) : `Cable_1/Zone_accessible.tif` fait 405 x 380 la ou le skidder fait
# 1034 x 894. Compares tels quels, `terra::values()` rend deux vecteurs de
# longueurs differentes que R RECYCLE en silence -- on obtient alors un taux
# d'accord parfaitement plausible et parfaitement faux. Toute couche est donc
# realignee sur la grille de reference, les cellules hors fenetre valant "non
# accessible" (Sylvaccess ne les a pas calculees).
GRILLE <- NULL

lire <- function(...) {
  f <- file.path(...)
  if (!file.exists(f)) return(NULL)
  r <- terra::rast(f)
  if (is.null(GRILLE)) return(r)
  # Emprise et resolution seules : `compareGeom()` regarde aussi des attributs
  # (CRS textuel, niveaux de facteur) qui different sans que la grille bouge, et
  # rejouer un `resample()` sur un raster categoriel lui coute ses niveaux.
  meme_grille <- isTRUE(all.equal(as.vector(terra::ext(r)), as.vector(terra::ext(GRILLE)))) &&
    isTRUE(all.equal(terra::res(r), terra::res(GRILLE)))
  if (meme_grille) return(r)
  cat(sprintf("  [realigne] %s : %d x %d -> %d x %d\n", basename(f),
              nrow(r), ncol(r), nrow(GRILLE), ncol(GRILLE)))
  terra::resample(r, GRILLE, method = "near")
}

# --- SKIDDER ----------------------------------------------------------------
s_dir <- dir_run(SYLVA, "Skidder")
acc_s <- lire(s_dir, "Foret_accessible.tif")
inacc_s <- lire(s_dir, "Foret_inaccessible.tif")

if (is.null(acc_s)) stop("Sorties Sylvaccess introuvables sous ", s_dir)

# La grille du skidder fait reference : toutes les autres couches s'y realignent.
GRILLE <- terra::rast(acc_s)

foret <- masque_foret(acc_s, inacc_s)
cat(sprintf("Grille : %d x %d | cellules forestieres : %d\n",
            nrow(acc_s), ncol(acc_s), sum(terra::values(foret))))

acc_f <- lire(FA, "skidder", "accessibilite.tif")
if (is.null(acc_f)) stop("Sorties ForetAccess introuvables sous ", file.path(FA, "skidder"))

# Notre accessibilite est categorielle ; chez Sylvaccess "accessible" = roulable
# OU treuille. On ramene donc parcourable + accessible a leur "1".
lev <- terra::levels(acc_f)[[1]]
codes_acc <- lev$value[lev[[2]] %in% c("parcourable", "accessible")]
acc_f_bin <- acc_f %in% codes_acc

cat("\n#############  SKIDDER  #############\n")
r_sk <- accord_binaire(acc_f_bin, vrai_ou_faux(acc_s), foret, "Foret accessible (skidder)")

for (p in list(
  c("distance_treuillage.tif",     "Distance_debusquage.tif",                    "Distance de debusquage"),
  c("distance_trainage_foret.tif", "Distance_trainage_foret.tif",                "Trainage en foret"),
  c("distance_trainage_piste.tif", "Distance_trainage_piste.tif",                "Trainage sur piste"),
  c("distance_debardage.tif",      "Distance_totale_foret_route_forestiere.tif", "Distance totale")
)) {
  n <- lire(FA, "skidder", p[1]); e <- lire(s_dir, p[2])
  if (!is.null(n) && !is.null(e)) ecart_continu(n, e, foret, p[3])
}

# --- PORTEUR ----------------------------------------------------------------
f_dir <- dir_run(SYLVA, "Porteur")
acc_ps <- lire(f_dir, "Foret_accessible.tif")
acc_pf <- lire(FA, "porteur", "accessibilite.tif")
if (!is.null(acc_ps) && !is.null(acc_pf)) {
  cat("\n\n#############  PORTEUR  #############\n")
  lev <- terra::levels(acc_pf)[[1]]
  codes <- lev$value[lev[[2]] %in% c("parcourable", "accessible")]
  accord_binaire(acc_pf %in% codes, vrai_ou_faux(acc_ps), foret, "Foret accessible (porteur)")

  # Distances (angle mort ferme en 12a.2). Sylvaccess n'expose que DEUX composantes
  # -- Dpiste et Dforet -- la ou nous en avons trois : piste, conduite, grappin.
  # Sylvaccess fond le grappin dans la foret (`fwd_fill_hoist`, pyx:4668) : on
  # apparie donc `Distance_dans_foret` a `distance_conduite + distance_grappin`.
  d_pis_f <- lire(FA, "porteur", "distance_trainage_piste.tif")
  d_pis_s <- lire(f_dir, "Distance_sur_piste.tif")
  if (!is.null(d_pis_f) && !is.null(d_pis_s)) {
    ecart_continu(d_pis_f, d_pis_s, foret, "Distance sur piste")
  }

  d_cond <- lire(FA, "porteur", "distance_conduite.tif")
  d_grap <- lire(FA, "porteur", "distance_grappin.tif")
  d_for_s <- lire(f_dir, "Distance_dans_foret.tif")
  if (!is.null(d_cond) && !is.null(d_grap) && !is.null(d_for_s)) {
    d_for_f <- d_cond + d_grap
    ecart_continu(d_for_f, d_for_s, foret, "Distance dans foret (conduite + grappin)")
  }

  d_tot_f <- lire(FA, "porteur", "distance_debardage.tif")
  d_tot_s <- lire(f_dir, "Distance_totale_foret_route_forestiere.tif")
  if (!is.null(d_tot_f) && !is.null(d_tot_s)) {
    ecart_continu(d_tot_f, d_tot_s, foret, "Distance totale")
  }
}

# --- CABLE ------------------------------------------------------------------
c_dir <- dir_run(SYLVA, "Cable")
acc_cs <- lire(c_dir, "Zone_accessible.tif")
acc_cf <- lire(FA, "cable", "accessibilite.tif")
if (!is.null(acc_cs) && !is.null(acc_cf)) {
  cat("\n\n#############  CABLE  #############\n")
  cat("(c_sup = 3 supports intermediaires des deux cotes, depuis le Lot 4d.)\n")
  lev <- terra::levels(acc_cf)[[1]]
  codes <- lev$value[lev[[2]] == "accessible_cable"]
  accord_binaire(acc_cf %in% codes, vrai_ou_faux(acc_cs), foret, "Zone accessible (cable)")
}

# --- DFCI -------------------------------------------------------------------
# L'oracle DFCI n'est pas dans le lanceur standard (g_do_dfci defaut false) : le
# bloc se saute si `DFCI_1/` est absent.
d_dir <- dir_run(SYLVA, "DFCI")
acc_ds <- lire(d_dir, "Foret_accessible.tif")
acc_df <- lire(FA, "dfci", "accessibilite.tif")
if (!is.null(acc_ds) && !is.null(acc_df)) {
  cat("\n\n#############  DFCI  #############\n")
  cat("(balayage radial de la lance, sources CL_DFCI ; Lot 12a.4.)\n")
  lev <- terra::levels(acc_df)[[1]]
  codes <- lev$value[grepl("^defendable", lev[[2]])]
  accord_binaire(acc_df %in% codes, vrai_ou_faux(acc_ds), foret, "Zone defendable (dfci)")

  # Longueur de lance (m) : ecart sur les cellules defendables des deux cotes.
  lance_s <- lire(d_dir, "Longueur_lance.tif")
  lance_f <- lire(FA, "dfci", "longueur_lance.tif")
  if (!is.null(lance_s) && !is.null(lance_f)) {
    ecart_continu(lance_f, lance_s, foret, "Longueur de lance (dfci)")
  }
}

cat("\n")
