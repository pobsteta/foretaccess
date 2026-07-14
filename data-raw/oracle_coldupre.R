# Confrontation a l'oracle Sylvaccess v3.6 sur le jeu de test officiel ColduPre.
#
# Fait tourner ForetAccess sur EXACTEMENT les entrees de
# sylvaccess-upstream/test/ColduPre/Input/, avec les parametres du scenario
# officiel (ressource/Tab_Param_test.csv), puis chronometre chaque moteur.
# La comparaison cellule a cellule aux sorties Sylvaccess vit dans
# oracle_compare.R.
#
# Prerequis : le depot Sylvaccess clone et son run de reference execute.
#   SYLVA=~/dev/sylvaccess-upstream Rscript data-raw/oracle_coldupre.R

# devtools vit dans la bibliotheque globale, hors du renv du projet.
.libPaths(c(.libPaths(), "~/R/x86_64-pc-linux-gnu-library/4.6"))
suppressPackageStartupMessages({
  library(terra)
  library(sf)
})
devtools::load_all(quiet = TRUE)

SYLVA <- Sys.getenv("SYLVA", "~/dev/sylvaccess-upstream")
IN <- file.path(path.expand(SYLVA), "test", "ColduPre", "Input")
OUT <- file.path("data-raw", "oracle", "coldupre", "foretaccess")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# --- Entrees -----------------------------------------------------------------
# CL_SVAC : 1 = piste forestiere, 2 = route forestiere, 3 = reseau public.
# Le reseau public est une BARRIERE (ni source, ni traversable) : c'est le point
# de chargement du camion, pas une place de depot. Cf. .classes_desserte().
mnt <- terra::rast(file.path(IN, "mnt.tif"))

desserte <- sf::st_read(file.path(IN, "forest_roadnetwork.gpkg"), quiet = TRUE)
desserte$classe <- c("piste", "route", "reseau_public")[desserte$CL_SVAC]

foret <- sf::st_read(file.path(IN, "forest_area.gpkg"), quiet = TRUE)

# Obstacles complets du skidder : le repertoire Obstacles_skidder/ (shapefiles).
# Couche heterogene : bati et reservoirs en polygones, cours d'eau et reseau
# public en lignes. On conserve les deux (cf. .masque_vecteur).
shp <- list.files(file.path(IN, "Obstacles_skidder"), pattern = "\\.shp$", full.names = TRUE)
obstacles <- sf::st_sf(geometry = do.call(c, lapply(shp, function(f) {
  sf::st_zm(sf::st_geometry(sf::st_read(f, quiet = TRUE)), drop = TRUE)
})))

volume <- terra::rast(file.path(IN, "vol_ha.tif"))

# --- Config : les valeurs du scenario officiel Tab_Param_test.csv ------------
# On aligne sur le SCENARIO, pas sur nos defauts : c'est ce que l'oracle a
# execute. Les ecarts de defauts (c_E, c_q2/q3, c_angle, c_safe) sont traites
# a part.
cfg <- foretaccess_config(
  general = list(resolution_m = terra::res(mnt)[1], workers = 1L),
  skidder = list(
    debardage_amont_max_m        = 50,    # s_dwinch_up
    debardage_aval_max_m         = 100,   # s_dwinch_down
    distance_hors_desserte_max_m = 50,    # s_dmax_outfor
    pente_skidder_max_pct        = 30,    # s_slope_max
    pente_bascule_amont_pct      = 75,    # s_smax_up
    pente_bascule_aval_pct       = 20,    # s_smax_down
    pente_abattage_max_pct       = 100,   # g_slope_mharv
    option_modelisation          = 1L,    # s_option
    classes_distance_m           = c(0, 250, 500, 1000, 1500, 2000)
  ),
  porteur = list(
    pente_travers_max_pct        = 15,    # f_slope_lat
    pente_montee_max_pct         = 30,    # f_slope_up
    pente_descente_max_pct       = 25,    # f_slope_down
    portee_grue_m                = 8,     # f_reach
    distance_pente_forte_max_m   = 300,   # f_slope_dmax
    distance_hors_desserte_max_m = 200,   # f_dmax_outfor
    pente_abattage_max_pct       = 100
  ),
  cable = list(
    longueur_max_m               = 750,    # c_lmax
    longueur_min_m               = 150,    # c_lmin
    hauteur_mat_m                = 10.5,   # c_htower
    hauteur_support_terminal_m   = 12,     # c_h_end
    distance_laterale_max_m      = 40,     # c_l_hor
    hauteur_cable_min_m          = 3.5,    # c_h_min
    hauteur_cable_max_m          = 50,     # c_h_max
    masse_lineaire_porteur_kg_m  = 1.85,   # c_q1
    masse_lineaire_traction_kg_m = 0.5,    # c_q2  (defaut reel v3.6)
    masse_lineaire_retour_kg_m   = 0.5,    # c_q3  (defaut reel v3.6)
    module_young_n_mm2           = 100000, # c_E   (defaut reel v3.6)
    angle_intersupport_deg       = 30,     # c_angle (defaut reel v3.6)
    diametre_mm                  = 18,     # c_d
    tension_rupture_kgf          = 35000,  # c_rupt_res
    coeff_securite               = 2,      # c_safe (scenario ColduPre)
    charge_max_kg                = 2500,   # c_load_max
    poids_chariot_kg             = 400,    # c_car_w
    nb_supports_max              = 3L,     # c_sup (Lot 4d : placement porte)
    hauteur_support_inter_m      = 12,     # c_h_sup
    longueur_min_travee_m        = 50      # c_l_span
  )
)

chrono <- list()
tic <- function(nom, expr) {
  t <- system.time(res <- force(expr))
  chrono[[nom]] <<- t
  message(sprintf("  %-12s CPU %6.1f s | ecoule %6.1f s", nom, t[["user.self"]], t[["elapsed"]]))
  res
}

message("ForetAccess sur ColduPre (", paste(dim(mnt)[1:2], collapse = " x "), " cellules)")

pre <- tic("preprocess", preprocess(
  mnt = mnt, desserte = desserte, foret = foret,
  obstacles_complets = obstacles, volume = volume, config = cfg
))

res_skidder <- tic("skidder", skidder(pre, config = cfg, write_dir = file.path(OUT, "skidder")))
res_porteur <- tic("porteur", porteur(pre, config = cfg, write_dir = file.path(OUT, "porteur")))

# Places de depot : Sylvaccess ne lance ses lignes que depuis `c_file_departure`
# filtre sur l'attribut CABLE. A ColduPre, c'est la desserte elle-meme, dont
# 2 troncons sur 125 portent CABLE != 0.
departs <- sf::st_read(file.path(IN, "forest_roadnetwork.gpkg"), quiet = TRUE)
departs$cable <- departs$CABLE
message("  places de depot : ", sum(departs$cable != 0), " troncons sur ", nrow(departs))

if (!identical(Sys.getenv("FA_CABLE"), "0")) {
  res_cable <- tic("cable", potentiel_cable(
    pre, config = cfg, departs = departs, write_dir = file.path(OUT, "cable")
  ))
} else {
  message("  cable        SAUTE (FA_CABLE=0)")
}

saveRDS(chrono, file.path(OUT, "chrono.rds"))
message("\nSorties ForetAccess : ", OUT)
