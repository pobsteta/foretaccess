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

args <- commandArgs(trailingOnly = TRUE)
SYLVA <- if (length(args) >= 1) args[1] else "~/dev/sylvaccess-upstream/test/ColduPre/Results"
FA <- if (length(args) >= 2) args[2] else "data-raw/oracle/coldupre/foretaccess"
SYLVA <- path.expand(SYLVA)

# PIEGE : Foret_accessible.tif vaut 1 sur les accessibles et NoData (0) ailleurs,
# idem pour Foret_inaccessible.tif. Lues telles quelles, les cellules
# inaccessibles arrivent en NA et disparaissent de toute comparaison : on ne
# mesurerait alors que l'accord sur les cellules que Sylvaccess juge deja
# accessibles, et l'on ne pourrait JAMAIS se voir trop optimiste. D'ou la
# binarisation explicite, NA -> FALSE.
vrai_ou_faux <- function(r) {
  v <- !is.na(r) & (r == 1)
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
  print(tab)
  invisible(list(accord = accord, faux_pos = faux_pos, faux_neg = faux_neg, table = tab))
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

lire <- function(...) {
  f <- file.path(...)
  if (!file.exists(f)) return(NULL)
  terra::rast(f)
}

# --- SKIDDER ----------------------------------------------------------------
s_dir <- file.path(SYLVA, "Skidder_1")
acc_s <- lire(s_dir, "Foret_accessible.tif")
inacc_s <- lire(s_dir, "Foret_inaccessible.tif")

if (is.null(acc_s)) stop("Sorties Sylvaccess introuvables sous ", s_dir)

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
f_dir <- file.path(SYLVA, "Porteur_1")
acc_ps <- lire(f_dir, "Foret_accessible.tif")
acc_pf <- lire(FA, "porteur", "accessibilite.tif")
if (!is.null(acc_ps) && !is.null(acc_pf)) {
  cat("\n\n#############  PORTEUR  #############\n")
  lev <- terra::levels(acc_pf)[[1]]
  codes <- lev$value[lev[[2]] %in% c("parcourable", "accessible")]
  accord_binaire(acc_pf %in% codes, vrai_ou_faux(acc_ps), foret, "Foret accessible (porteur)")
}

# --- CABLE ------------------------------------------------------------------
c_dir <- file.path(SYLVA, "Cable_1")
acc_cs <- lire(c_dir, "Zone_accessible.tif")
acc_cf <- lire(FA, "cable", "accessibilite.tif")
if (!is.null(acc_cs) && !is.null(acc_cf)) {
  cat("\n\n#############  CABLE  #############\n")
  cat("(Sylvaccess tourne a c_sup = 3 supports ; notre noyau est a 0 -> on\n")
  cat(" s'attend a etre plus conservateur. C'est la dette du Lot 4, pas un bug.)\n")
  lev <- terra::levels(acc_cf)[[1]]
  codes <- if (is.null(lev)) NULL else lev$value[lev[[2]] %in% c("accessible", "couvert")]
  bin <- if (is.null(codes)) acc_cf > 0 else acc_cf %in% codes
  accord_binaire(bin, vrai_ou_faux(acc_cs), foret, "Zone accessible (cable)")
}

cat("\n")
