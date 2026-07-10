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
#' @return Un objet de classe `foretaccess_config` (liste structurée), validé.
#' @export
#' @examples
#' cfg <- foretaccess_config()
#' cfg$skidder$debardage_aval_max_m
foretaccess_config <- function(skidder = list(),
                               porteur = list(),
                               cable = list(),
                               general = list()) {
  defaults <- .foretaccess_defaults()

  cfg <- list(
    skidder = utils::modifyList(defaults$skidder, skidder),
    porteur = utils::modifyList(defaults$porteur, porteur),
    cable   = utils::modifyList(defaults$cable, cable),
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
      hauteur_cable_min_m = 4,
      hauteur_cable_max_m = 30,
      pas_angulaire_deg   = 1,
      # Tableaux matériels (mât, longueur/diamètre/masse linéaire/tension de
      # rupture du porteur, nb max supports, coeff. sécurité) : complétés au
      # Lot 4 depuis l'article + le .pyx (ADR-006). Liste vide = non renseigné.
      materiels           = list()
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
  checkmate::assert_list(ca$materiels)

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
