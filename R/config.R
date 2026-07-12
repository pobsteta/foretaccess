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
#' Défauts **DFCI** (beta) : portée de défense 100 m, pente d'intervention max
#' 40 %, dessertes-source `"dfci"`. Ce sont des hypothèses de travail, non des
#' valeurs Sylvaccess : le module DFCI est une sortie **beta** (voir
#' `specs/006-dfci.md`).
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
                               general = list()) {
  defaults <- .foretaccess_defaults()

  cfg <- list(
    skidder = utils::modifyList(defaults$skidder, skidder),
    porteur = utils::modifyList(defaults$porteur, porteur),
    cable   = utils::modifyList(defaults$cable, cable),
    dfci    = utils::modifyList(defaults$dfci, dfci),
    general = utils::modifyList(defaults$general, general)
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
      # 1 = privilegier le treuillage (limiter l'impact sur le sol, defaut v3.6) ;
      # 2 = privilegier le debusquage. Seule l'option 1 est implementee.
      option_modelisation          = 1L,
      classes_distance_m           = c(0, 250, 500, 1000, 1500, 2000)
    ),
    porteur = list(
      pente_travers_max_pct        = 15,
      pente_montee_max_pct         = 30,
      pente_descente_max_pct       = 25,
      portee_grue_m                = 8,
      distance_pente_forte_max_m   = 300,
      distance_hors_desserte_max_m = 200,
      pente_abattage_max_pct       = 100
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
      # Materiel cable (v3.6). c_q2/c_q3 (traction/retour), c_E (module de Young)
      # et c_angle ne sont PAS dans Tab_Param_cable.csv : defauts documentes
      # (viennent du paramdict global de Sylvaccess). Cf. specs/004 Q7.
      masse_lineaire_porteur_kg_m  = 1.85,   # c_q1
      masse_lineaire_traction_kg_m = 0.9,    # c_q2 (defaut)
      masse_lineaire_retour_kg_m   = 0.9,    # c_q3 (defaut)
      diametre_mm                  = 18,     # c_d
      tension_rupture_kgf          = 35000,  # c_rupt_res
      coeff_securite               = 2,      # c_safe
      charge_max_kg                = 2500,   # c_load_max
      poids_chariot_kg             = 400,    # c_car_w
      module_young_n_mm2           = 160000, # c_E (defaut)
      angle_intersupport_deg       = 20,     # c_angle (defaut)
      # Bornes de pente de la ligne (rad). Larges par defaut : la tension et la
      # garde au sol sont les vraies contraintes. Raffinement (pente min de
      # descente par gravite pour chariot classique) : travail futur.
      pente_min_rad = -1.4,
      pente_max_rad = 1.4,
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
    # Camion DFCI (beta, Lot 6, EF-8). Modele volontairement simple : zone
    # defendable = tampon au terrain (plus court chemin pondere par la pente,
    # comme le skidder) depuis les dessertes DFCI, plafonne a la portee de
    # defense et coupe au-dela d'une pente d'intervention. Limites documentees
    # dans specs/006 : ni modele de combustible, ni vent, ni physique de lance.
    dfci = list(
      # Portee laterale de defense depuis une desserte carrossable (m).
      distance_defense_max_m = 100,
      # Pente au-dela de laquelle le terrain est repute non defendable (%).
      pente_defense_max_pct  = 40,
      # Classes de desserte servant de base au camion (sous-ensemble de
      # route / piste / dfci). Defaut : les seules dessertes DFCI.
      classes_source         = "dfci"
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
  checkmate::assert_subset(df$classes_source, .classes_desserte(), empty.ok = FALSE)

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
