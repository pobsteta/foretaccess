#' Configuration métier de ForêtAccess (défauts Sylvaccess v3.6)
#'
#' Construit un objet de configuration validé regroupant les paramètres des
#' moteurs. Les valeurs par défaut sont celles de **Sylvaccess v3.6**
#' (RdV Experts 2026), qui diffèrent de l'article 2015 (cf. `docs/foretaccess-brief.md`
#' §6 et `docs/adr/ADR-003-configuration.md`).
#'
#' @param skidder Liste des paramètres skidder (voir *Détails*).
#' @param porteur Liste des paramètres porteur (voir *Détails*).
#' @param cable Liste des paramètres câble. Le **schéma** est posé dès le Lot 0 ;
#'   les tableaux matériels sont complétés au Lot 4 (dépendance ADR-006).
#' @param dfci Liste des paramètres du camion DFCI (beta, Lot 6 ; voir *Détails*).
#' @param desserte Liste des paramètres de conception de desserte (épic Lots
#'   14-18) ; `desserte$cout` porte le barème de coût de construction (Lot 14).
#' @param general Liste des paramètres généraux (résolution, CRS, méthode de
#'   calcul de la pente).
#'
#' @details
#' Défauts **skidder** (v3.6) : débardage amont max 50 m, aval max 100 m
#' (article : 150 m), pente de bascule amont 75 %, pente de bascule aval 20 %,
#' distance hors desserte 50 m, pente skidder max 30 % (article : 25 %), pente
#' abattage max 100 %.
#'
#' Défauts **porteur** (v3.6) : pente en travers max 15 %, pente montée max 30 %,
#' pente descente max 25 %, portée de grue 8 m, distance en pente forte 300 m,
#' distance hors desserte 200 m, pente abattage max 100 %.
#'
#' Défauts **DFCI** (`Sylvaccess_5_dfci.py`) : longueur de lance max 440 m
#' (`dfci_lmax`), pente pompier max 110 % (`dfci_slope_max`), classes de
#' défendabilité `0;120;280;440` (`dfci_class`). Sources = flag `CL_DFCI`
#' (orthogonal aux classes de desserte). Voir `specs/006-dfci.md`.
#'
#' @return Un objet de classe `foretaccess_config` (liste structurée), validé.
#' @export
#' @examples
#' cfg <- foretaccess_config()
#' cfg$skidder$debardage_aval_max_m
foretaccess_config <- function(skidder = list(),
                               porteur = list(),
                               cable = list(),
                               dfci = list(),
                               desserte = list(),
                               general = list()) {
  defaults <- .foretaccess_defaults()

  # `desserte$cout` et `desserte$trace` sont des sous-listes : `modifyList` a plat
  # ecraserait tout le bloc des qu'on surcharge un seul champ. On les fusionne a part.
  desserte_m <- utils::modifyList(defaults$desserte, desserte)
  if (!is.null(desserte$cout)) {
    desserte_m$cout <- utils::modifyList(defaults$desserte$cout, desserte$cout)
  }
  if (!is.null(desserte$trace)) {
    desserte_m$trace <- utils::modifyList(defaults$desserte$trace, desserte$trace)
  }

  cfg <- list(
    skidder  = utils::modifyList(defaults$skidder, skidder),
    porteur  = utils::modifyList(defaults$porteur, porteur),
    cable    = utils::modifyList(defaults$cable, cable),
    dfci     = utils::modifyList(defaults$dfci, dfci),
    desserte = desserte_m,
    general  = utils::modifyList(defaults$general, general)
  )
  class(cfg) <- "foretaccess_config"
  validate_config(cfg)
  cfg
}

# Défauts métier Sylvaccess v3.6 (source unique interne).
.foretaccess_defaults <- function() {
  list(
    skidder = list(
      debardage_amont_max_m        = 50,
      debardage_aval_max_m         = 100,
      pente_bascule_amont_pct      = 75,
      pente_bascule_aval_pct       = 20,
      distance_hors_desserte_max_m = 50,
      pente_skidder_max_pct        = 30,
      pente_abattage_max_pct       = 100,
      # Lot 2 : constantes lues dans sylvaccess_cython3.pyx (skid_debusq_RF),
      # ou elles sont codees en dur. Promues en parametres (ADR-003).
      hauteur_attache_treuil_m     = 10,
      hauteur_degagement_max_m     = 30,
      surcout_obstacle_complet     = 1000,
      # Ce que vaut un metre de piste, en metres de foret, dans les deux decisions
      # du trainage. Sylvaccess les code en dur, avec DEUX valeurs distinctes :
      #  * 0,5 pour CHOISIR ENTRE DEUX PISTES (`Dfwd_flat_forest_tracks`,
      #    sylvaccess_cython3.pyx:3715 -- le test, normalise, minimise
      #    `d_foret + 0,5 x d_piste`) ;
      #  * 0,1 pour RENONCER A LA PISTE AU PROFIT DE LA ROUTE (`skid_fill_opt1`,
      #    pyx:4283) -- soit un fort biais en faveur de la piste : il faut que la
      #    route soit vraiment meilleure pour qu'on quitte la piste.
      # Promus en parametres (ADR-003).
      ponderation_piste_propagation = 0.5,
      ponderation_piste_arbitrage   = 0.1,
      # 1 = privilegier le treuillage (limiter l'impact sur le sol, defaut v3.6) ;
      # 2 = privilegier le debusquage. Seule l'option 1 est implementee.
      option_modelisation          = 1L,
      classes_distance_m           = c(0, 250, 500, 1000, 1500, 2000)
    ),
    porteur = list(
      pente_travers_max_pct        = 15,  # f_slope_lat
      pente_montee_max_pct         = 30,  # f_slope_up
      # f_slope_down : le defaut v3.6 vaut 40, pas 25. Le 25 vient du *scenario* de
      # test ColduPre (`Tab_Param_test.csv`), que nous avions pris pour le defaut.
      pente_descente_max_pct       = 40,  # f_slope_down
      portee_grue_m                = 8,   # f_reach
      distance_pente_forte_max_m   = 300, # f_slope_dmax
      distance_hors_desserte_max_m = 200, # f_dmax_outfor
      pente_abattage_max_pct       = 100  # g_slope_mharv
    ),
    cable = list(
      # Gardes au sol du cable porteur (v3.6 : c_h_min / c_h_max).
      hauteur_cable_min_m = 3.5,
      hauteur_cable_max_m = 50,
      pas_angulaire_deg   = 1,
      # Geometrie de la ligne (v3.6).
      longueur_max_m             = 750,   # c_lmax
      longueur_min_m             = 150,   # c_lmin
      hauteur_mat_m              = 10.5,  # c_htower (support de depart)
      hauteur_support_terminal_m = 12,    # c_h_end
      distance_laterale_max_m    = 40,    # c_l_hor (pechage lateral)
      nb_supports_max            = 3,     # c_sup
      hauteur_support_inter_m    = 12,    # c_h_sup
      longueur_min_travee_m      = 50,    # c_l_span

      # Methode de placement des supports (spec 013). "sylvaccess" (defaut,
      # `OptPyl_NoH`, fidelite ColduPre garantie) ou "seilaplan" (graphe + Dijkstra
      # a la Bont & Heinimann : optimise position ET hauteur des supports, sans la
      # gymnastique machine-en-haut/bas). Voir docs/comparaison-cable-seilaplan.md.
      methode_supports           = "sylvaccess",
      # Reglages du graphe SEILAPLAN (ignores si methode_supports = "sylvaccess") :
      # niveaux de hauteur des supports intermediaires `min..max` au pas `delta`,
      # espacement minimal entre supports, et finesse du balayage de pre-tension.
      # Valeurs confrontees a ColduPre (16/07) : couverture +3619 vs `_NoH`,
      # perf ~2,8x (cf. PLAN.md). Un pas de hauteur plus fin ou des supports plus
      # rapproches couvrent marginalement plus mais coutent quadratiquement.
      hauteur_support_min_m      = 4,     # min_HM
      hauteur_support_max_m      = 12,    # max_HM
      pas_hauteur_support_m      = 4,     # Abstufung_HM (delta h) -> 4, 8, 12 m
      distance_min_support_m     = 40,    # Min_Dist_Mast
      nb_pas_pretension          = 12,    # balayage de pre-tension (n_sk)

      # Validite geometrique de la ligne (`check_line`) : elle doit finir en foret, ne
      # pas traverser trop de non-foret d'affilee, et ne pas courir en travers d'un
      # versant raide. Sans ces bornes, les lignes filent jusqu'a `longueur_max_m` a
      # travers n'importe quel terrain (mesure sur ColduPre : 10 % de foret declaree
      # accessible a tort).
      angle_transversal_deg      = 60,    # c_angle_transv (angle min a la courbe de niveau)
      pente_transversale_max_pct = 30,    # c_slope_trans
      distance_transversale_max_m = 75,   # c_l_slope
      proportion_transversale_max = 0.15, # c_prop_slope
      # Longueur max traversee sans foret. Sylvaccess la DERIVE (`min(c_lmax * 0,1,
      # c_lmin)`) sauf si `c_l_without_forest` est fourni : `NA` reprend la derivation.
      longueur_sans_foret_max_m  = NA_real_,  # c_l_without_forest
      # Precision du balayage (c_precision). Elle ne regle pas le modele mais son
      # echantillonnage, et Sylvaccess en derive TROIS choses a la fois
      # (`get_dep_config`) : le pas angulaire, le pas entre cellules de depart, et la
      # largeur du faisceau de placement des supports. Cf. `precision_cable()`.
      #   1 = fine      : azimuts 1 deg, tous les departs, faisceau 5
      #   2 = moyenne   : azimuts 2 deg, tous les departs, faisceau 5
      #   3 = grossiere : azimuts 2 deg, un depart sur deux, faisceau 1  <- defaut v3.6
      # On garde 3 pour etre confrontable a l'oracle par defaut. Un balayage plus fin
      # trouve des lignes que Sylvaccess manque par simple sous-echantillonnage : c'est
      # plus juste, mais ce n'est plus le meme modele -- que l'utilisateur le demande.
      precision                  = 3L,    # c_precision
      # Materiel cable (v3.6). c_q2/c_q3 (traction/retour), c_E (module de Young),
      # c_angle et c_safe ne sont pas dans `Tab_Param_cable.csv` -- mais ils sont
      # dans `dic_AllParam.json` (champ `def_value`), que la spec 004 (Q7) croyait
      # introuvable et dont elle avait devine les valeurs. Ce sont ces defauts-la.
      masse_lineaire_porteur_kg_m  = 1.85,   # c_q1
      masse_lineaire_traction_kg_m = 0.5,    # c_q2
      masse_lineaire_retour_kg_m   = 0.5,    # c_q3
      diametre_mm                  = 18,     # c_d
      tension_rupture_kgf          = 35000,  # c_rupt_res
      coeff_securite               = 2.5,    # c_safe
      charge_max_kg                = 2500,   # c_load_max
      poids_chariot_kg             = 400,    # c_car_w
      module_young_n_mm2           = 100000, # c_E
      angle_intersupport_deg       = 30,     # c_angle
      # Bornes de pente de la ligne : Sylvaccess ne les prend PAS en parametre, il
      # les DERIVE du materiel et du sens de debardage (`get_cable_configs`). Elles
      # sont donc calculees par `bornes_pente_cable()` a partir de ce qui suit --
      # et non posees a la main. Notre ancien defaut `+/- 1,4 rad` autorisait des
      # lignes montant a 55 deg : pour un chariot classique, Sylvaccess plafonne la
      # ligne « machine en haut » a +0,1 rad. Le cable doit descendre.
      type_chariot   = 0L,  # c_car_type : 0 = classique sur mat-cable, 1 = winch-liner
      type_cable     = 1L,  # c_type : 0 mat sur tracteur, 1 remorque, 2 camion, 3 cable long
      sens_debardage = 0L,  # Skid_direction : 0 = les deux sens, 1 = amont seul, 2 = aval seul
      pente_gravite_pct          = 15,   # c_slope_grav
      pente_winchliner_amont_pct = 15,   # c_slope_wliner_up
      pente_winchliner_aval_pct  = 100,  # c_slope_wliner_down
      # Selection multicritere des lignes (Lot 5, EF-7). Poids par critere (0 =
      # ignore) ; limites min/max ; sens prefere (0 aucun, 1 aval, -1 amont) ;
      # contribution minimale de surface nouvelle pour retenir une ligne.
      selection = list(
        poids = list(surface = 1, supports = 0, longueur = 0, volume = 0, ipc = 0),
        limites = list(
          surface_min = 0, supports_max = Inf, longueur_min = 0,
          longueur_max = Inf, volume_min = 0, ipc_min = 0
        ),
        sens_prefere = 0,
        contribution_min = 0.6
      )
    ),
    # Camion DFCI (Lot 12a.4, EF-8). Transcription de `Sylvaccess_5_dfci.py` :
    # balayage RADIAL de la lance (`debusq_dfci`), pas un plus court chemin pondere.
    # Les sources sont le flag `CL_DFCI` (orthogonal aux classes route/piste/public),
    # porte par `preprocess()` dans `pre$dfci_source_mask`. Les seuils sont ceux de
    # Sylvaccess (dic_AllParam.json).
    dfci = list(
      # Longueur maximale de lance (m). La spec 006 initiale posait 100 m en croyant
      # Sylvaccess depourvu de module DFCI : il en a un, et il porte a 440 m.
      distance_defense_max_m = 440,  # dfci_lmax
      # Pente au-dela de laquelle le terrain est infranchissable par les pompiers (%).
      # La spec 006 posait 40 %, Sylvaccess admet 110 %.
      pente_defense_max_pct  = 110,  # dfci_slope_max
      # Bornes des classes de defendabilite (m) : bandes [0,120[, [120,280[,
      # [280,440] de longueur de lance (derniere borne inclusive).
      classes_distance_m     = c(0, 120, 280, 440),  # dfci_class
      # --- Alimentation du flag `dfci` (CL_DFCI) sur la desserte (`flag_dfci`) ---
      # Ces seuils ne viennent PAS de Sylvaccess (qui suppose le flag deja porte par
      # la donnee) : ils pilotent l'acquisition de la source DFCI (spec 010 §10.2).
      # Tolerance d'appariement desserte <-> reseau DFCI OSM `ref:FR:DFCI` (m).
      tol_appariement_m      = 10,
      # Repli geometrique : emprise minimale d'une piste DFCI traversante (m).
      emprise_min_m          = 10,
      # Repli geometrique : distance max bout d'impasse <-> aire de retournement (m).
      rayon_retournement_m   = 20
    ),
    # --- Conception de desserte (epic Lots 14-18, spec 014) ------------------
    # Barème de coût de CONSTRUCTION d'une nouvelle desserte (structure additive,
    # inspirée du « Cost Raster Creator » de ForestRoadNetwork, GPL v3). Unité
    # monétaire (EUR/m projeté). Le solveur de tracé (Lot 15) propage ce coût.
    desserte = list(
      cout = list(
        # Coût de base (EUR/m) : plus petite catégorie de desserte, terrain plat,
        # meilleur sol. **Seul paramètre obligatoire** ; sans les couches
        # optionnelles, le coût vaut cette base partout.
        cout_base_m = 20,
        # Surcoût de pente (EUR/m) par classe de pente du terrain (%). `[min, max)`
        # -> `surcout`. `Inf` en surcoût = pente non constructible (cellule NA dans
        # `franchissable`). Bornes croissantes, surcoûts >= 0 et croissants.
        bareme_pente = data.frame(
          min     = c(0, 15, 35, 60),
          max     = c(15, 35, 60, Inf),
          surcout = c(0, 25, 90, Inf)
        ),
        # Franchissements ponctuels, ramenés au mètre de traversée de la cellule.
        cout_pont_m = 400, # surcoût sur une cellule de plan d'eau (ouvrage d'art)
        cout_buse_m = 120, # surcoût maximal par densité de cours d'eau (cellule pleine)
        # Surcoût de sol : table nommée `classe (chr) -> surcout (EUR/m)`. `NULL`
        # = aucun (couche de sol ignorée).
        bareme_sol = NULL
      ),
      # Paramètres du solveur de tracé A* (Lot 15, portage SylvaRoad ;
      # défauts de `SylvaRoaD_0_param.py`). Le tracé minimise sa longueur sous
      # contraintes de géométrie routière.
      trace = list(
        pente_long_min = 2,        # min_slope (%) : pente en long minimale de la route
        pente_long_max = 12,       # max_slope (%) : pente en long maximale
        penalty_xy = 150,          # pénalité de virage (m / 180°)
        penalty_z = 80,            # pénalité de changement de pente (« vague »)
        d_neighborhood_m = 42,     # rayon du voisinage disque (m)
        max_diff_z_m = 3,          # écart altitude route/terrain maximal (m)
        angle_epingle = 110,       # angle_hairpin (°) : seuil de détection d'épingle
        trans_slope_all = 90,      # dévers maximal hors épingle (%)
        trans_slope_hairpin = 55,  # dévers maximal à l'épingle (%)
        lmax_devers_m = 40,        # Lmax_ab_sl (m) : longueur max en dévers excessif
        rayon_braquage_m = 8,      # Radius (m) : rayon de braquage des camions
        prop_devers_max = 0.25,    # prop_sl_max : fraction locale de fort dévers à l'épingle
        max_slope_hairpin = 10,    # réglage de l'angle limite d'épingle
        tal = 1.5,                 # réglage de l'angle limite d'épingle
        modhair = 1.5,             # réglage de l'espacement minimal entre épingles
        buffer_arrivee_m = 0       # bufgoal (m) : tolérance de finition à la cible
      )
    ),
    general = list(
      resolution_m  = 5,
      crs_epsg      = NA_integer_,
      # Methode de calcul de la pente/exposition (Lot 1) : Horn (8 voisins) ou
      # Evans (4 voisins). Configurable pour reconcilier avec l'oracle v3.6.
      methode_pente = "Horn",
      # Tuilage (Lot 7). La tuile vaut quatre fois le halo initial : le halo n'y
      # coute alors que 125 % de surface calculee en trop. Le halo double tant que
      # des cellules restent non certifiees ; `halo_max_m` borne le pire cas, a
      # l'ordre de grandeur du trainage sur piste observe sur donnees reelles.
      tuile_m        = 2000,
      halo_initial_m = 500,
      halo_max_m     = 4000,
      workers        = 1L
    )
  )
}

#' Valide un objet de configuration ForêtAccess
#'
#' Vérifie types, bornes et cohérence via \pkg{checkmate}. Lève une erreur
#' ciblée au premier manquement.
#'
#' @param cfg Objet `foretaccess_config`.
#' @return `cfg` de façon invisible si valide ; sinon une erreur.
#' @export
validate_config <- function(cfg) {
  checkmate::assert_class(cfg, "foretaccess_config")

  sk <- cfg$skidder
  checkmate::assert_number(sk$debardage_amont_max_m, lower = 0, finite = TRUE)
  checkmate::assert_number(sk$debardage_aval_max_m, lower = 0, finite = TRUE)
  checkmate::assert_number(sk$pente_bascule_amont_pct, lower = 0)
  checkmate::assert_number(sk$pente_bascule_aval_pct, lower = 0)
  checkmate::assert_number(sk$distance_hors_desserte_max_m, lower = 0, finite = TRUE)
  checkmate::assert_number(sk$pente_skidder_max_pct, lower = 0)
  checkmate::assert_number(sk$pente_abattage_max_pct, lower = 0)
  checkmate::assert_number(sk$hauteur_attache_treuil_m, lower = 0, finite = TRUE)
  checkmate::assert_number(sk$hauteur_degagement_max_m, lower = 0, finite = TRUE)
  if (sk$hauteur_degagement_max_m <= sk$hauteur_attache_treuil_m) {
    cli::cli_abort(c(
      "Configuration skidder incoherente.",
      "x" = "{.field hauteur_degagement_max_m} ({sk$hauteur_degagement_max_m}) doit etre > \\
             {.field hauteur_attache_treuil_m} ({sk$hauteur_attache_treuil_m})."
    ))
  }
  checkmate::assert_number(sk$surcout_obstacle_complet, lower = 0, finite = TRUE)
  # Une ponderation negative rendrait le cout initial du Dijkstra negatif -- donc
  # l'etiquette non monotone, et le plus court chemin faux (cf. `.cout_initial()`).
  checkmate::assert_number(sk$ponderation_piste_propagation, lower = 0, finite = TRUE)
  checkmate::assert_number(sk$ponderation_piste_arbitrage, lower = 0, finite = TRUE)
  checkmate::assert_choice(as.integer(sk$option_modelisation), c(1L, 2L))
  checkmate::assert_numeric(sk$classes_distance_m, lower = 0, min.len = 2,
                            any.missing = FALSE, sorted = TRUE, unique = TRUE)

  po <- cfg$porteur
  checkmate::assert_number(po$pente_travers_max_pct, lower = 0)
  checkmate::assert_number(po$pente_montee_max_pct, lower = 0)
  checkmate::assert_number(po$pente_descente_max_pct, lower = 0)
  checkmate::assert_number(po$portee_grue_m, lower = 0, finite = TRUE)
  checkmate::assert_number(po$distance_pente_forte_max_m, lower = 0, finite = TRUE)
  checkmate::assert_number(po$distance_hors_desserte_max_m, lower = 0, finite = TRUE)
  checkmate::assert_number(po$pente_abattage_max_pct, lower = 0)

  ca <- cfg$cable
  checkmate::assert_number(ca$hauteur_cable_min_m, lower = 0, finite = TRUE)
  checkmate::assert_number(ca$hauteur_cable_max_m, lower = 0, finite = TRUE)
  if (ca$hauteur_cable_max_m <= ca$hauteur_cable_min_m) {
    cli::cli_abort(c(
      "Configuration cable incoherente.",
      "x" = "{.field hauteur_cable_max_m} ({ca$hauteur_cable_max_m}) doit etre > \\
             {.field hauteur_cable_min_m} ({ca$hauteur_cable_min_m})."
    ))
  }
  checkmate::assert_number(ca$pas_angulaire_deg, lower = 0, upper = 360)
  # Materiel et geometrie (v3.6), completes au Lot 4.
  checkmate::assert_number(ca$longueur_max_m, lower = 0, finite = TRUE)
  checkmate::assert_number(ca$longueur_min_m, lower = 0, finite = TRUE)
  checkmate::assert_number(ca$diametre_mm, lower = 0, finite = TRUE)
  checkmate::assert_number(ca$tension_rupture_kgf, lower = 0, finite = TRUE)
  checkmate::assert_number(ca$coeff_securite, lower = 0, finite = TRUE)
  checkmate::assert_number(ca$module_young_n_mm2, lower = 0, finite = TRUE)
  checkmate::assert_int(ca$nb_supports_max, lower = 0)
  checkmate::assert_number(ca$hauteur_support_inter_m, lower = 0, finite = TRUE)
  checkmate::assert_number(ca$longueur_min_travee_m, lower = 0, finite = TRUE)
  checkmate::assert_choice(ca$methode_supports, c("sylvaccess", "seilaplan"))
  checkmate::assert_number(ca$hauteur_support_min_m, lower = 0, finite = TRUE)
  checkmate::assert_number(ca$hauteur_support_max_m,
                           lower = ca$hauteur_support_min_m, finite = TRUE)
  checkmate::assert_number(ca$pas_hauteur_support_m, lower = 0.1, finite = TRUE)
  checkmate::assert_number(ca$distance_min_support_m, lower = 0, finite = TRUE)
  checkmate::assert_int(as.integer(ca$nb_pas_pretension), lower = 1)
  checkmate::assert_number(ca$angle_transversal_deg, lower = 0, upper = 90)
  checkmate::assert_number(ca$pente_transversale_max_pct, lower = 0, finite = TRUE)
  checkmate::assert_number(ca$distance_transversale_max_m, lower = 0, finite = TRUE)
  checkmate::assert_number(ca$proportion_transversale_max, lower = 0, upper = 1)
  checkmate::assert_number(ca$longueur_sans_foret_max_m, lower = 0, na.ok = TRUE)
  checkmate::assert_int(ca$precision, lower = 1, upper = 3)
  checkmate::assert_int(ca$type_chariot, lower = 0, upper = 1)
  checkmate::assert_int(ca$type_cable, lower = 0, upper = 3)
  checkmate::assert_int(ca$sens_debardage, lower = 0, upper = 2)
  checkmate::assert_number(ca$pente_gravite_pct, lower = 0, finite = TRUE)
  checkmate::assert_number(ca$pente_winchliner_amont_pct, lower = 0, finite = TRUE)
  checkmate::assert_number(ca$pente_winchliner_aval_pct, lower = 0, finite = TRUE)
  if (ca$longueur_max_m <= ca$longueur_min_m) {
    cli::cli_abort(c(
      "Configuration cable incoherente.",
      "x" = "{.field longueur_max_m} ({ca$longueur_max_m}) doit etre > \\
             {.field longueur_min_m} ({ca$longueur_min_m})."
    ))
  }

  df <- cfg$dfci
  checkmate::assert_number(df$distance_defense_max_m, lower = 0, finite = TRUE)
  checkmate::assert_number(df$pente_defense_max_pct, lower = 0)
  checkmate::assert_numeric(df$classes_distance_m, lower = 0, min.len = 2,
    any.missing = FALSE, sorted = TRUE)
  checkmate::assert_number(df$tol_appariement_m, lower = 0, finite = TRUE)
  checkmate::assert_number(df$emprise_min_m, lower = 0, finite = TRUE)
  checkmate::assert_number(df$rayon_retournement_m, lower = 0, finite = TRUE)

  ge <- cfg$general
  checkmate::assert_number(ge$resolution_m, lower = 0, finite = TRUE)
  checkmate::assert_int(ge$crs_epsg, na.ok = TRUE)
  checkmate::assert_choice(ge$methode_pente, .methodes_terrain())
  checkmate::assert_number(ge$tuile_m, lower = 0, finite = TRUE)
  checkmate::assert_number(ge$halo_initial_m, lower = 0, finite = TRUE)
  checkmate::assert_number(ge$halo_max_m, lower = 0, finite = TRUE)
  if (ge$halo_max_m < ge$halo_initial_m) {
    cli::cli_abort(c(
      "Configuration de tuilage incoherente.",
      "x" = "{.field halo_max_m} ({ge$halo_max_m}) doit etre >= \\
             {.field halo_initial_m} ({ge$halo_initial_m})."
    ))
  }
  checkmate::assert_int(ge$workers, lower = 1)

  # --- Desserte : barème de coût de construction (Lot 14, CA-14.6) ------------
  co <- cfg$desserte$cout
  checkmate::assert_number(co$cout_base_m, lower = 0, finite = TRUE)
  checkmate::assert_number(co$cout_pont_m, lower = 0, finite = TRUE)
  checkmate::assert_number(co$cout_buse_m, lower = 0, finite = TRUE)
  checkmate::assert_data_frame(co$bareme_pente, min.rows = 1)
  checkmate::assert_names(names(co$bareme_pente), must.include = c("min", "max", "surcout"))
  checkmate::assert_numeric(co$bareme_pente$min, lower = 0, any.missing = FALSE, sorted = TRUE)
  checkmate::assert_numeric(co$bareme_pente$max, any.missing = FALSE, sorted = TRUE)
  # `surcout` peut valoir `Inf` (pente non constructible) mais jamais negatif ;
  # croissant, pour que le barème reste monotone (CA-14.4).
  checkmate::assert_numeric(co$bareme_pente$surcout, lower = 0, any.missing = FALSE, sorted = TRUE)
  # Classes contiguës et couvrantes : chaque `max` est le `min` suivant, la
  # première borne est 0, la dernière `Inf`.
  bp <- co$bareme_pente
  if (bp$min[1] != 0 || !is.infinite(bp$max[nrow(bp)]) ||
        !isTRUE(all.equal(bp$max[-nrow(bp)], bp$min[-1]))) {
    cli::cli_abort(c(
      "Bareme de pente de desserte incoherent.",
      "x" = "Les classes doivent etre contigues et couvrantes : \\
             {.field min}[1] = 0, {.field max} final = Inf, {.field max}[i] = {.field min}[i+1]."
    ))
  }
  if (!is.null(co$bareme_sol)) {
    checkmate::assert_numeric(unlist(co$bareme_sol), lower = 0, any.missing = FALSE)
  }

  # --- Desserte : solveur de tracé (Lot 15) -----------------------------------
  tr <- cfg$desserte$trace
  checkmate::assert_number(tr$pente_long_min, lower = 0, finite = TRUE)
  checkmate::assert_number(tr$pente_long_max, lower = 0, finite = TRUE)
  if (tr$pente_long_max < tr$pente_long_min) {
    cli::cli_abort(c(
      "Pente en long de desserte incoherente.",
      "x" = "{.field pente_long_max} ({tr$pente_long_max}) doit etre >= \\
             {.field pente_long_min} ({tr$pente_long_min})."
    ))
  }
  for (champ in c("penalty_xy", "penalty_z", "max_diff_z_m", "lmax_devers_m",
                  "buffer_arrivee_m", "prop_devers_max", "modhair", "tal")) {
    checkmate::assert_number(tr[[champ]], lower = 0, finite = TRUE, .var.name = champ)
  }
  checkmate::assert_number(tr$d_neighborhood_m, lower = 0, finite = TRUE)
  checkmate::assert_number(tr$rayon_braquage_m, lower = 0, finite = TRUE)
  checkmate::assert_number(tr$angle_epingle, lower = 0, upper = 180)
  checkmate::assert_number(tr$trans_slope_all, lower = 0, finite = TRUE)
  checkmate::assert_number(tr$trans_slope_hairpin, lower = 0, finite = TRUE)
  checkmate::assert_number(tr$max_slope_hairpin, lower = 0, finite = TRUE)

  invisible(cfg)
}

#' Lit une configuration depuis un fichier YAML
#'
#' Les clés absentes du YAML gardent leur défaut v3.6. Le résultat est validé.
#'
#' @param path Chemin d'un fichier YAML.
#' @return Un objet `foretaccess_config` validé.
#' @export
read_config <- function(path) {
  checkmate::assert_file_exists(path, access = "r")
  raw <- yaml::read_yaml(path)
  raw <- if (is.null(raw)) list() else raw
  foretaccess_config(
    skidder = raw$skidder %||% list(),
    porteur = raw$porteur %||% list(),
    cable   = raw$cable %||% list(),
    dfci    = raw$dfci %||% list(),
    general = raw$general %||% list()
  )
}

#' Écrit une configuration au format YAML
#'
#' @param cfg Objet `foretaccess_config`.
#' @param path Chemin de sortie.
#' @return `path` de façon invisible.
#' @export
write_config <- function(cfg, path) {
  validate_config(cfg)
  yaml::write_yaml(unclass(cfg), path)
  invisible(path)
}

# Opérateur "coalesce" interne (évite une dépendance à rlang au Lot 0).
`%||%` <- function(x, y) if (is.null(x)) y else x
