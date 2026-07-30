# Diagnostic : quel parametre du porteur porte les 29,7 ha de flips vs ACCESSFOR ?
#
# CE QUI EST DEJA ECARTE :
#   * le MNT -- le remplacer par les dalles RGE Alti d'ACCESSFOR ne deplace que
#     12,1 ha dans le bon sens, et rend notre porteur PLUS permissif de 13,7 ha
#     au total. Il ne peut pas expliquer un exces de conservatisme.
#     (data-raw/diag_residu_mnt.R, FA_MOTEUR=porteur)
#   * le reseau -- aucune infraction d'integrite dans l'AOI stricte (spec 025).
#   * l'implementation -- oracle_compare rend 99,14 % d'accord porteur contre
#     Sylvaccess sur cette meme AOI. Nos deux moteurs concordent presque
#     parfaitement. Si nous divergeons d'ACCESSFOR mais pas de Sylvaccess, c'est
#     qu'ACCESSFOR n'a pas execute le porteur avec NOS parametres -- ou pas avec
#     ceux que sa notice annonce (rapport p.12).
#
# PROTOCOLE : partir de notre configuration, RELACHER un parametre a la fois, et
# mesurer combien de foret bascule d'inaccessible a accessible. Le parametre
# capable de produire ~29,7 ha est le candidat. Un parametre qui n'en produit que
# 2 ou 3 est hors de cause, quelle que soit l'intuition qu'on en avait.
#
# Usage : FA_DFCI=0 Rscript data-raw/diag_sensibilite_porteur.R
.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressPackageStartupMessages({
  library(sf)
  library(terra)
  pkgload::load_all(quiet = TRUE)
})

AOI <- st_read("data-raw/aoi.gpkg", quiet = TRUE)
CACHE <- Sys.getenv("ACCESSFOR_CACHE", "/tmp/accessfor-cache")
DFCI <- !identical(Sys.getenv("FA_DFCI"), "0")

inp <- acquire_inputs(st_buffer(AOI, 100), sources = c("mnt", "desserte", "foret"),
  cache_dir = CACHE, res_m = 5, buffer_m = 0, dfci = DFCI)
mnt <- rast(inp$mnt)
pre <- preprocess(mnt, inp$desserte, inp$foret)
mfor <- !is.na(values(pre$foret_mask, mat = FALSE)) &
  values(pre$foret_mask, mat = FALSE) == 1
cell_ha <- prod(res(mnt)) / 1e4

acc <- function(po) {
  r <- po$accessibilite
  lev <- try(levels(r)[[1]], silent = TRUE)
  v <- values(r, mat = FALSE)
  if (inherits(lev, "data.frame") && ncol(lev) >= 2) {
    # APPARIEMENT EXACT, pas grepl() : les niveaux sont `parcourable`,
    # `accessible`, `non_accessible`, `hors_foret` -- et « non_accessible »
    # CONTIENT « accessible ». Un grep comptait donc l'accessible PLUS
    # l'inaccessible, ce qui a produit des surfaces de 476 ha la ou Sylvaccess
    # en mesure 134, et une fausse non-monotonie du porteur (2026-07-30).
    # DEFINITION DU HARNAIS VALIDE (data-raw/oracle_compare.R:165) :
    # `parcourable` (la machine y roule) ET `accessible` (atteint par la grue ou
    # le regime de pente) comptent tous deux pour de la foret accessible.
    #
    # Deux erreurs successives ici le 2026-07-30, a ne pas refaire :
    #   grepl("accessible")            -> attrapait AUSSI `non_accessible`
    #   == "accessible" seul           -> excluait `parcourable`
    # La premiere donnait 476 ha, la seconde 23 ha, la bonne ~136 ha.
    v %in% lev[[1]][as.character(lev[[2]]) %in% c("parcourable", "accessible")]
  } else {
    !is.na(v) & v > 0
  }
}

base_cfg <- foretaccess_config()
ref <- acc(porteur(pre, base_cfg))
cat(sprintf("reference : %.1f ha accessibles\n\n", sum(ref & mfor) * cell_ha))

# Variantes : chaque parametre RELACHE seul, dans une plage plausible. On ne
# cherche pas la « bonne » valeur -- on cherche lequel a le POUVOIR de deplacer
# 29,7 ha. Un parametre sans levier est hors de cause.
variantes <- list(
  list(nom = "pente travers  15 -> 20 %", p = list(pente_travers_max_pct = 20)),
  list(nom = "pente travers  15 -> 25 %", p = list(pente_travers_max_pct = 25)),
  list(nom = "pente montee   30 -> 35 %", p = list(pente_montee_max_pct = 35)),
  list(nom = "pente descente 25 -> 30 %", p = list(pente_descente_max_pct = 30)),
  list(nom = "portee grue     8 -> 10 m", p = list(portee_grue_m = 10)),
  list(nom = "hors desserte 200 -> 250 m", p = list(distance_hors_desserte_max_m = 250)),
  list(nom = "pente forte   300 -> 400 m", p = list(distance_pente_forte_max_m = 400))
)

cat(sprintf("%-28s %10s %10s\n", "parametre relache", "gagne(ha)", "perdu(ha)"))
for (v in variantes) {
  cfg <- foretaccess_config(porteur = v$p)
  a <- acc(porteur(pre, cfg))
  gagne <- sum(!ref & a & mfor) * cell_ha
  perdu <- sum(ref & !a & mfor) * cell_ha
  cat(sprintf("%-28s %10.1f %10.1f\n", v$nom, gagne, perdu))
}

cat("\nCible : 29,7 ha de flips « nous inaccessible / ACCESSFOR accessible ».\n")
cat("Un parametre qui ne deplace que quelques hectares est HORS DE CAUSE,\n")
cat("quelle que soit l'intuition qu'on en avait.\n")
