# Desserte DETECTEE sur le MNT (spec 026). Le gisement : pistes de debardage
# anciennes, cloisonnements, traces effaces du couvert mais toujours lisibles
# dans le micro-relief. Une plateforme deja terrassee se rouvre pour une
# FRACTION du cout d'un trace neuf -- 13 EUR/m contre 20, cf.
# `config$desserte$cout$fraction_reouverture` et spec 026 sec.7.3.
#
# On CONSOMME dessertR (regle stricte 1) : `dsr_detecter()` fusionne conductivite
# geomorphologique, canal de surface et vesselness en une carte de probabilite
# `p_desserte`, HORS du corridor du reseau de reference, puis la vectorise.
#
# CE QUE CE N'EST PAS : une desserte utilisable. On detecte des LINEAIRES CREUX,
# et le micro-relief garde aussi les drains, fosses, limites parcellaires et
# terrasses. dessertR pondere double le canal de surface precisement parce que
# les pistes se lisent dans la DISCONTINUITE DU SOUS-ETAGE, leur empreinte au sol
# etant « faible ou noyee dans les traces fossiles ». La couche rendue est
# CANDIDATE : elle doit passer `qualifier_desserte()` avant tout usage.


# Dalles LiDAR dont l'emprise intersecte la grille. Sans colonnes d'emprise
# exploitables (catalogue d'une autre convention de nommage), on rend TOUT :
# mieux vaut un calcul lent qu'un canal de surface silencieusement ampute.
.dalles_utiles <- function(dalles, grille) {
  if (is.null(dalles) || is.null(dalles$laz)) {
    return(character(0))
  }
  laz <- as.character(dalles$laz)
  bornes <- c("xmin", "ymin", "xmax", "ymax")
  if (!all(bornes %in% names(dalles))) {
    return(laz)
  }
  e <- terra::ext(grille)
  touche <- !(as.numeric(dalles$xmax) < e[1] | as.numeric(dalles$xmin) > e[2] |
              as.numeric(dalles$ymax) < e[3] | as.numeric(dalles$ymin) > e[4])
  touche[is.na(touche)] <- TRUE
  garde <- laz[touche]
  if (!length(garde)) {
    return(laz)
  }
  if (length(garde) < length(laz)) {
    cli::cli_inform("Nuage : {length(garde)}/{length(laz)} dalle{?s} retenue{?s}
                     (les autres ne touchent pas l'emprise).")
  }
  garde
}

#' Calibration de référence de la détection (spec 026)
#'
#' Specs **absolues** et `c_vessel` figés sur un jeu de référence, pour que le
#' `seuil` de [detecter_desserte()] désigne la même chose d'un site à l'autre.
#'
#' @details
#' **Pourquoi figer.** `dessertR::dsr_calibrer_specs()` calibre sur les données
#' qu'on lui donne : appelé par AOI, il rendrait des specs justes localement mais
#' **incomparables entre sites**, ce qui est précisément ce que le CA-26.5
#' interdit. On calibre donc **une fois**, sur un jeu de référence, et on fige.
#'
#' **Valeurs produites par** `data-raw/calibrer_bornes_dsr.R` contre **dessertR
#' 1.1.0**, sur la dalle `LHD_FXX_0737_6385` (Chastel-Nouvel, 1 km², 32 tronçons,
#' 7 561 m de desserte BD TOPO `piste` + `route`). Onze canaux retenus, AUC de
#' 0,826 (`taux_penetration`) à 0,572 (`svf`).
#'
#' **Ordre de calibration, qui n'est pas indifférent** : `c_vessel` est mesuré
#' **avant** la pile, et la pile construite avec — sinon les bornes seraient
#' calibrées sur une vesselness elle-même relative à l'emprise, et le défaut
#' réapparaîtrait un cran plus bas.
#'
#' **`densite_sousetage` est écarté**, bien que `dsr_calibrer_specs()` le
#' retienne (AUC 0,565). Motif : ses bornes sortent **indéterminées**
#' (`a = NA, b = NA`), les deux populations étant à zéro en médiane. Le garder le
#' ferait retomber sur la dérivation par quantiles, donc **réintroduirait la
#' dépendance à l'emprise** sur ce canal — l'inverse du but. Ce n'est pas un
#' jugement sur sa valeur : dessertR 1.1.0 note qu'il mesure un **état** et non
#' la présence d'une route, « une route recolonisée reste une route ».
#'
#' **Portée — un seul massif.** Lozère, 830–1 260 m, forêt de montagne. dessertR
#' 1.1.0 calibre sur **deux** massifs ; nous n'en avons qu'un, et il recouvre le
#' bloc `wsfi` à 54 %. Ces valeurs sont **provisoires** : elles ancrent, elles ne
#' généralisent pas. `specs = NULL` dans [detecter_desserte()] restaure les
#' défauts dessertR.
#'
#' **Constantes a LIRE, pas a afficher.** Cette fonction est exportee pour que le
#' defaut de [detecter_desserte()] soit inspectable et surchargeable, pas pour
#' etre presentee a un utilisateur : ses bornes n'ont de sens que pour qui lit
#' `dsr_appartenance()`. Une interface qui veut offrir un choix expose plutot les
#' formes de `specs` (fige / `"auto"` / `NULL`), pas leurs valeurs.
#'
#' @return Une liste : `geomorpho` (pour `dessertR::dsr_conductivite()`),
#'   `surface` (pour `dessertR::dsr_sigma_surf()`) et `c_vessel` (pour
#'   `dessertR::dsr_layers_dtm()`, une valeur par échelle).
#' @seealso [detecter_desserte()], `dessertR::dsr_calibrer_specs()`,
#'   `dessertR::dsr_c_vessel()`, `specs/026`.
#' @export
specs_desserte_calibrees <- function() {
  list(
    geomorpho = list(
      rugosite     = list(type = "croissante", a = 0.0402013732,
                          b = 0.172684016, poids = 2),
      pente        = list(type = "decroissante", a = 4.4913660574,
                          b = 20.256017850, poids = 2),
      vesselness   = list(type = "croissante", a = 0.0006361408,
                          b = 0.070831439, poids = 2),
      openness_pos = list(type = "decroissante", a = 81.4344019229,
                          b = 86.632451057, poids = 1),
      slrm         = list(type = "decroissante", a = -0.2492187500,
                          b = 0.007807821, poids = 1),
      openness_neg = list(type = "croissante", a = 86.9214112193,
                          b = 89.202206074, poids = 1),
      svf          = list(type = "croissante", a = 0.8552256750,
                          b = 0.914393904, poids = 1)
    ),
    surface = list(
      taux_penetration = list(type = "croissante", a = 0.1290322581, b = 1,
                              poids = 3),
      densite_sol      = list(type = "croissante", a = 6, b = 29, poids = 3),
      h_couvert        = list(type = "decroissante", a = 6.8340001106,
                              b = 13.803000450, poids = 2)
    ),
    # `dsr_c_vessel()` sur l'emprise de reference. Sans lui, les bornes
    # ci-dessus ne suffiraient pas : `dsr_frangi()` prend
    # `c = 0,5 * max(norme de Hessien) DU RASTER FOURNI`, en amont des
    # appartenances. Relaye par `dsr_layers_dtm(c_vessel = )` depuis la 1.1.0.
    c_vessel = c(c_1 = 0.3541673, c_2 = 0.7593123, c_4 = 1.2454072)
  )
}

#' Turn a dessertR calibration into detection specs
#'
#' `dessertR::dsr_calibrer_specs()` returns bounds calibrated **on your own
#' data**, and advises using them when the frozen ones saturate. Its `$specs` is
#' a **flat** list of channels; [detecter_desserte()] expects the **nested**
#' shape of [specs_desserte_calibrees()] (`geomorpho` / `surface` / `c_vessel`).
#' Two contracts for one word -- this bridges them.
#'
#' @details
#' The flat calibration *is* the `geomorpho` group: `$specs` is documented as
#' "directement utilisable" by `dsr_conductivite()`, which is exactly what
#' [detecter_desserte()] feeds with `specs$geomorpho`.
#'
#' **What a calibration cannot give you**, and why the other two groups keep
#' their frozen defaults:
#' * `surface` -- those channels (`taux_penetration`, `densite_sol`,
#'   `h_couvert`) come from the **point cloud**, not from the DEM stack that was
#'   calibrated. `dsr_calibrer_specs()` never sees them.
#' * `c_vessel` -- the Frangi anchor, produced by `dessertR::dsr_c_vessel()`, not
#'   by the calibration. Without it the vesselness channel is rescaled on
#'   whatever extent you pass, and `seuil` stops being comparable between sites.
#'
#' Mixing locally calibrated `geomorpho` bounds with frozen `surface` bounds is a
#' **deliberate compromise**, not an oversight: it is still better than frozen
#' bounds that saturate on your massif. Pass `surface = NULL` to opt out and let
#' dessertR derive them, at the cost of extent-relative results.
#'
#' @param calibration Either the full `dsr_calibrer_specs()` result or its
#'   `$specs` element directly. Both are accepted.
#' @param surface Bounds for the point-cloud channels. Defaults to the frozen
#'   ones; `NULL` leaves them to dessertR.
#' @param c_vessel Frangi anchor. Defaults to the frozen one; `NULL` makes the
#'   vesselness extent-relative.
#' @return A list shaped like [specs_desserte_calibrees()], usable as the `specs`
#'   argument of [detecter_desserte()].
#' @seealso [detecter_desserte()], [specs_desserte_calibrees()],
#'   `dessertR::dsr_calibrer_specs()`, `specs/026`.
#' @export
#' @examples
#' # Forme attendue, sans appeler dessertR :
#' plat <- list(rugosite = list(type = "croissante", a = 0.04, b = 0.17, poids = 2))
#' str(specs_depuis_calibration(plat)$geomorpho)
specs_depuis_calibration <- function(calibration,
                                     surface = specs_desserte_calibrees()$surface,
                                     c_vessel = specs_desserte_calibrees()$c_vessel) {
  sp <- if (is.list(calibration) && !is.null(calibration$specs)) {
    calibration$specs
  } else {
    calibration
  }
  if (!is.list(sp) || length(sp) == 0 || is.null(names(sp))) {
    cli::cli_abort(c(
      "{.arg calibration} n'a pas la forme attendue.",
      "i" = "Passer {.code dsr_calibrer_specs(...)} ou son element {.field $specs}."
    ))
  }
  if (!.specs_est_plate(sp)) {
    cli::cli_abort(c(
      "{.arg calibration} n'est pas une liste PLATE de canaux.",
      "i" = "Chaque element doit porter {.field type}, {.field a} et {.field b}.",
      "x" = "Recu : {.val {names(sp)}}."
    ))
  }
  list(geomorpho = sp, surface = surface, c_vessel = c_vessel)
}

# Une liste de canaux est PLATE si chacun de ses elements est une regle
# d'appartenance (`type`/`a`/`b`). C'est ce qui distingue la sortie de
# `dsr_calibrer_specs()` de la forme imbriquee de `specs_desserte_calibrees()`,
# dont les elements sont des GROUPES.
.specs_est_plate <- function(sp) {
  if (!is.list(sp) || length(sp) == 0) {
    return(FALSE)
  }
  all(vapply(sp, function(x) {
    is.list(x) && all(c("type", "a", "b") %in% names(x))
  }, logical(1)))
}

# Accepte les DEUX vocabulaires de specs, sans que l'appelant ait a les connaitre.
.specs_normaliser <- function(specs) {
  if (is.null(specs)) {
    return(NULL)
  }
  groupes <- c("geomorpho", "surface", "c_vessel")
  if (any(names(specs) %in% groupes)) {
    return(specs)                       # forme imbriquee, deja bonne
  }
  if (.specs_est_plate(specs)) {
    # Forme PLATE : c'est une sortie de `dsr_calibrer_specs()`. On la promeut
    # sans rien demander -- l'appelant a suivi le conseil de dessertR, il n'a pas
    # a decouvrir qu'un second vocabulaire existe.
    cli::cli_inform(c(
      "v" = "Calibration {.pkg dessertR} reconnue ({length(specs)} canau{?x}) :
             promue en {.field geomorpho}.",
      "i" = "{.field surface} et {.field c_vessel} gardent les bornes figees --
             une calibration ne les produit pas. Cf. {.fn specs_depuis_calibration}."
    ))
    return(specs_depuis_calibration(specs))
  }
  cli::cli_abort(c(
    "{.arg specs} n'a aucune des formes reconnues.",
    "i" = "Attendu : {.fn specs_desserte_calibrees} (imbriquee),
           {.code dsr_calibrer_specs(...)$specs} (plate), {.val auto} ou {.val NULL}.",
    "x" = "Recu une liste de : {.val {names(specs)}}."
  ))
}

#' Détecte la desserte absente de la référence, sur le MNT (spec 026)
#'
#' Cherche dans le **micro-relief** les linéaires que la BD TOPO ne porte pas :
#' pistes anciennes, cloisonnements, tracés effacés du couvert. Rend une couche
#' **candidate**, jamais une desserte utilisable.
#'
#' @details
#' **La sortie n'est pas de la desserte.** On détecte des linéaires creux, et le
#' micro-relief garde aussi les drains, fossés, limites parcellaires et
#' terrasses. Un tronçon détecté n'a ni largeur, ni état, ni portance mesurés :
#' il doit passer [qualifier_desserte()] avant d'entrer dans une conception de
#' réseau. Aucun chemin ne doit permettre à un candidat d'entrer dans
#' `desserte_existante` sans qualification.
#'
#' **Deux gisements disjoints.** Cette détection trouve ce qui est *effacé du
#' couvert mais lisible au sol* ; [acquire_desserte_osm()] trouve ce que
#' *quelqu'un a cartographié*. Les deux alimentent la même couche candidate, avec
#' `source` distinct.
#'
#' **Éloigne d'ACCESSFOR délibérément** : ACCESSFOR consomme la BD TOPO seule.
#' Ne jamais activer dans une comparaison ACCESSFOR.
#'
#' @section Performance:
#' **La fonction la plus couteuse du paquet.** Mesure nemetonshiny du
#' 2026-08-12 : **729 s et plus de 8 Go de pic** sur 1 855 ha, MNT LiDAR 0,5 m.
#'
#' Deux postes, qui ne se compensent pas :
#' * la **pile de couches** (`dsr_layers_dtm()`) tient toute l'emprise en memoire
#'   a la resolution du MNT -- d'ou le pic, proportionnel a la surface DIVISEE par
#'   le carre de la resolution ;
#' * le **canal de surface** relit le nuage LiDAR dalle par dalle : compter la
#'   taille du nuage en plus.
#'
#' Ne jamais cabler cette fonction sur un bouton synchrone ; prevoir un worker
#' separe. Et **borner l'emprise, pas la resolution** : passer de 0,5 m a 5 m ne
#' fait pas gagner du temps, cela fait perdre le signal -- 0 canal retenu sur 7 a
#' 5 m contre 5 sur 7 a 0,5 m (mesure nemetonshiny). Sur un poste de 31 Go
#' partage, une emprise de l'ordre de 2 000 ha est deja le plafond raisonnable.
#' @section Place dans le flux:
#' [detecter_desserte()] et [qualifier_desserte()] sont **sequentielles, pas
#' exclusives** : la premiere trouve l'ABSENT (des linéaires candidats hors du
#' réseau connu), la seconde requalifie l'EXISTANT (largeur, état, portance
#' mesurés au LiDAR). L'enchaînement naturel est
#' `acquire_desserte()` -> `detecter_desserte()` -> fusion -> `qualifier_desserte()`,
#' car la sortie de détection est **candidate** : sans largeur ni portance, elle
#' n'est pas consommable par [preprocess()]. Les enchaîner dans l'autre sens
#' qualifierait un réseau auquel il manque encore ce qu'on cherche.
#' @param mnt Modèle numérique de terrain (`SpatRaster`/chemin), **1 m ou plus
#'   fin** — le micro-relief d'une plateforme ancienne ne survit pas à 5 m.
#' @param reference Desserte connue à exclure (sortie d'[acquire_desserte()]).
#' @param las_source Nuage LiDAR pour le canal de surface. `NULL` : détection
#'   sur la seule géomorphologie, « nettement moins sûre » selon dessertR.
#' @param seuil Seuil de binarisation de `p_desserte`. Défaut 0,6 (dessertR).
#'   La spec 026 prescrit un **balayage 0,4 → 0,8** pour la validation, pas un
#'   seuil unique — voir [detecter_desserte_balayage()].
#' @param buffer_ref Demi-largeur (m) du corridor de référence exclu. Défaut 15.
#' @param long_min Longueur minimale (m) d'un linéaire retenu. Défaut 30.
#' @param emprise Emprise polygonale restreignant le balayage (régime
#'   `corridor`) ; `NULL` balaye toute la grille (régime `complet`). La spec 026
#'   prescrit `complet` pour la **validation** — un corridor biaise le
#'   dénominateur du taux de faux positifs vers les zones déjà intéressantes — et
#'   `corridor` en production.
#' @param dtm_res Résolution (m) de la grille de référence. Défaut 1.
#' @param methode Vectoriseur, passé tel quel à `dessertR::dsr_detecter()`.
#'   **Défaut `"squelette"`, nommé et non subi** : depuis dessertR 1.1.0,
#'   `"auto"` résout vers `"agent"`, mais l'agent ne peut pas s'amorcer quand
#'   `buffer_ref > 0` — `dsr_amorces()` filtre ses amorces sur `!is.na(p)` à
#'   l'extrémité des tronçons de référence, qui est précisément la zone que
#'   `dsr_indice_detection()` vient de masquer. `"auto"` replierait donc sur le
#'   squelette **en silence**, et la chaîne mesurée changerait sans préavis au
#'   jour où l'amont corrigera. Voir `specs/026` §6.0.1 (précondition P5).
#' @param poids Poids des trois termes de la fusion, vecteur nommé
#'   `c(geo=, surf=, vessel=)`. `NULL` (défaut) laisse ceux de `dsr_detecter()`.
#'
#'   **À connaître avant de régler quoi que ce soit** : `dsr_detecter()` fusionne
#'   en **moyenne géométrique pondérée**, donc dominée par son plus **petit**
#'   terme — un poids n'y dose pas une contribution, il arme un **veto**. Mesuré
#'   sur le bloc `wsfi` (campagne CA-26.5) : le terme `vessel`, à son poids par
#'   défaut de 1, ramène `p_desserte` de 0,210 à **0,001** sur des pistes
#'   réelles, parce que `vesselness` est un détecteur de crêtes creux dont
#'   1,62 % des cellules atteignent la rampe. `c(geo = 1, surf = 0.5, vessel = 0)`
#'   neutralise ce veto.
#' @param seuil_vessel Début de la rampe d'appartenance sur `vesselness`. `NULL`
#'   (défaut) laisse celui de `dsr_detecter()` (0,3) — à comparer aux bornes
#'   calibrées du même canal dans `specs$geomorpho`, qui saturent à 0,07.
#' @param specs Bornes d'appartenance. **Quatre formes acceptées** :
#'   * [specs_desserte_calibrees()] (défaut) — bornes figées, imbriquées
#'     (`geomorpho`/`surface`/`c_vessel`) ;
#'   * `"auto"` — **calibre sur place** avec `dessertR::dsr_calibrer_specs()`,
#'     à partir du MNT et de la `reference` fournis. C'est la réponse au conseil
#'     de dessertR quand les bornes figées saturent (« des bornes calibrées sur
#'     un AUTRE massif ne se transportent pas ») : l'appelant suit ce conseil
#'     sans avoir à connaître deux vocabulaires de specs. **Exige `reference`.**
#'     `surface` et `c_vessel` restent figés, une calibration ne les produisant
#'     pas ;
#'   * la sortie **plate** de `dsr_calibrer_specs()$specs` — reconnue à sa forme
#'     et promue en `geomorpho`, cf. [specs_depuis_calibration()] ;
#'   * `NULL` — **restaure les specs de dessertR**, dont les bornes sont dérivées par
#'   quantiles de l'emprise — le `seuil` cesse alors d'être comparable d'un site
#'   à l'autre.
#' @return Un `sf` de `LINESTRING` avec `source = "detectee"` et `p_desserte`.
#'   Sans `dessertR`, une couche vide et un message — jamais d'échec. L'attribut
#'   **`canal_surface`** (logique) dit si le canal de surface a réellement été
#'   calculé : il est présent sur **toute** sortie, vide comprise, pour qu'un
#'   résultat nul se lise sans ambiguïté.
#' @seealso [detecter_desserte_balayage()], [qualifier_desserte()],
#'   [acquire_desserte_osm()], `specs/026`.
#' @export
detecter_desserte <- function(mnt, reference = NULL, las_source = NULL,
                              seuil = 0.6, buffer_ref = 15, long_min = 30,
                              emprise = NULL, dtm_res = 1,
                              methode = "squelette",
                              specs = specs_desserte_calibrees(),
                              poids = NULL, seuil_vessel = NULL) {
  checkmate::assert_number(seuil, lower = 0, upper = 1)
  # `canal_surface` porte sur TOUTES les sorties, y compris vides : un appelant
  # qui recoit zero lineaire doit pouvoir distinguer « rien detecte » de « rien
  # detecte, et sans le canal que dessertR pondere double ».
  vide <- function(canal = FALSE) {
    v <- sf::st_sf(source = character(0), p_desserte = numeric(0),
      geometry = sf::st_sfc())
    attr(v, "canal_surface") <- canal
    v
  }
  if (!.dessertr_dispo()) {
    cli::cli_inform(c(
      "!" = "Detection indisponible ({.pkg dessertR} absent) : couche vide.",
      "i" = "{.code remotes::install_github(\"pobsteta/dessertR\")}"
    ))
    return(vide())
  }
  # nocov start : chemin dessertR, hors CI (valide sur dalle reelle).
  # `specs = "auto"` : on calibre SUR PLACE. C'est ce que dessertR conseille quand
  # ses bornes saturent -- « des bornes calibrees sur un AUTRE massif ne se
  # transportent pas » -- et l'appelant n'a aucune raison de connaitre deux
  # vocabulaires de specs pour suivre ce conseil.
  auto <- identical(specs, "auto")
  if (auto && is.null(reference)) {
    cli::cli_abort(c(
      "{.code specs = \"auto\"} exige une {.arg reference}.",
      "i" = "La calibration apprend a separer desserte et non-desserte : sans
             desserte connue, il n'y a rien a apprendre.",
      "v" = "Fournir {.arg reference}, ou {.code specs = NULL} pour les bornes
             par quantiles de dessertR."
    ))
  }
  specs <- if (auto) specs_desserte_calibrees() else .specs_normaliser(specs)
  ref <- if (!is.null(reference)) sf::st_geometry(sf::st_as_sf(reference)) else NULL
  r <- .as_raster(mnt, "mnt")
  res_max <- max(terra::res(r))
  if (res_max > 1.5) {
    cli::cli_warn(c(
      "!" = "MNT a {round(res_max, 1)} m : le micro-relief d'une plateforme
             ancienne ne survit pas a cette resolution.",
      "i" = "Fournir un MNT a {.strong 1 m ou plus fin}."
    ))
  }
  grille <- .dsr("dsr_grille_reference")(r, res = dtm_res)
  # `c_vessel` ancre la vesselness AVANT toute appartenance : `dsr_frangi()`
  # derive sinon son `c` du maximum de l'image, en amont des bornes, et aucune
  # borne ne le rattrape. Relaye jusqu'ici depuis dessertR 1.1.0 -- d'ou la
  # garde : sur une 1.0.x, `dsr_layers_dtm(c_vessel = )` echouerait sur un
  # argument inconnu, et un repli SILENCIEUX rendrait une detection relative a
  # l'emprise sans que rien ne le dise.
  ancrable <- !is.null(specs) && !is.null(specs$c_vessel) &&
    "c_vessel" %in% names(formals(.dsr("dsr_layers_dtm")))
  if (!is.null(specs) && !is.null(specs$c_vessel) && !ancrable) {
    cli::cli_warn(c(
      "!" = "{.pkg dessertR} {utils::packageVersion(.PKG_DESSERTR)} n'expose pas
             {.arg c_vessel} : la vesselness reste relative a l'emprise.",
      "i" = "Installer {.pkg dessertR} >= 1.1.0 pour que {.arg seuil} soit
             comparable d'un site a l'autre."
    ))
  }
  pile <- if (ancrable) {
    .dsr("dsr_layers_dtm")(r, grille = grille, c_vessel = specs$c_vessel)
  } else {
    .dsr("dsr_layers_dtm")(r, grille = grille)
  }
  # Calibration sur place, une fois la pile construite : `dsr_calibrer_specs()`
  # veut exactement ces couches et la reference. On garde `surface` et
  # `c_vessel` figes -- la calibration ne les produit pas (cf.
  # `specs_depuis_calibration()`), et rebatir la pile pour un `c_vessel` local
  # couterait un second passage sur toute l'emprise.
  if (auto) {
    cal <- tryCatch(.dsr("dsr_calibrer_specs")(pile, reference = ref),
                    error = function(e) NULL)
    if (is.null(cal) || is.null(cal$specs) || length(cal$specs) == 0) {
      cli::cli_warn(c(
        "!" = "Calibration automatique sans resultat : bornes figees conservees.",
        "i" = "Aucun canal ne separait la reference du reste -- MNT trop grossier
               (viser {.strong 1 m ou plus fin}) ou reference trop courte."
      ))
    } else {
      specs <- specs_depuis_calibration(cal, surface = specs$surface,
                                        c_vessel = specs$c_vessel)
      cli::cli_inform("Calibration automatique : {length(cal$specs)} canau{?x} retenu{?s}
                       ({.val {names(cal$specs)}}).")
    }
  }
  # Les bornes CALIBREES sont ce qui rend `seuil` absolu. Sans elles,
  # `dsr_appartenance()` ancre chaque canal sur les quantiles de l'emprise
  # fournie, et le meme terrain rend des detections differentes selon le
  # decoupage (mesure : 116 m sur 0,25 km2 analyses seuls, 0 m sur la meme
  # fenetre dans 4 km2). `specs = NULL` restaure le comportement dessertR.
  sigma_geo <- if (is.null(specs)) {
    .dsr("dsr_conductivite")(pile)
  } else {
    .dsr("dsr_conductivite")(pile, specs = specs$geomorpho)
  }
  # VESSELNESS N'EST PASSE EN VETO QUE S'IL N'EST PAS DEJA UN CANAL DE `sigma_geo`.
  #
  # `dsr_detecter()` fusionne ses termes en MOYENNE GEOMETRIQUE ponderee
  # (`exp(sum(w log(mu)) / sum(w))`), donc dominee par son plus PETIT terme, et
  # `vesselness` y pese 1 -- le double du canal de surface. Or il entre par une
  # rampe demarrant a `seuil_vessel = 0,3`, alors que c'est un detecteur de
  # cretes CREUX par nature : sur le bloc wsfi, 1,62 % des cellules seulement
  # atteignent 0,3 (mediane 0,0023). Le terme vaut donc ~0 presque partout et
  # ecrase `p_desserte`, quelle que soit la qualite de la geomorphologie.
  #
  # Et il etait compte DEUX FOIS : `specs_desserte_calibrees()$geomorpho` porte
  # deja un canal `vesselness` de poids 2, calibre entre 0,00064 et 0,0708 --
  # une borne haute 4,2 fois PLUS BASSE que le debut de la rampe du veto. Les
  # deux lectures se contredisent, et le veto l'emporte.
  #
  # Mesure sur les 4 pistes annotees du bloc wsfi (campagne CA-26.5) : avec la
  # geomorphologie seule, 50,2 % de leurs cellules passent le seuil 0,40 ; avec
  # le veto, 0,0 %. C'est ce veto, et non les bornes, qui expliquait le rappel
  # nul. Cf. `data-raw/annotation_wsfi/RESULTATS.md`.
  vess_dans_specs <- !is.null(specs) && !is.null(specs$geomorpho) &&
    "vesselness" %in% names(specs$geomorpho)
  vess <- if (!vess_dans_specs && "vesselness" %in% names(pile)) {
    pile[["vesselness"]]
  } else {
    NULL
  }
  if (vess_dans_specs) {
    cli::cli_inform(c(
      "i" = "{.field vesselness} est deja un canal de {.arg specs$geomorpho}
             (poids {specs$geomorpho$vesselness$poids}) : il n'est pas repasse en
             veto separe.",
      "i" = "Le repasser le compterait deux fois, la seconde avec une rampe
             {round(0.3 / specs$geomorpho$vesselness$b, 1)}x au-dessus de sa
             propre borne calibree."
    ))
  }

  # Canal de surface : c'est LUI qui porte le signal -- AUC 0,870 sur
  # `taux_penetration`, le meilleur des quatre canaux calibres.
  sigma_surf <- NULL
  if (!is.null(las_source)) {
    dalles <- tryCatch(.dsr("dsr_catalog")(laz = las_source), error = function(e) NULL)
    # NE LIRE QUE LES DALLES QUI TOUCHENT LA GRILLE. `.dsr_canaux_dalles()` lit
    # chaque fichier qu'on lui passe, sans verifier qu'il sert : sur le bloc
    # `ltcp`, cela faisait relire 25 dalles couvrant 2 500 ha pour produire un
    # raster de 100 ha -- plus de 46 min sans aboutir. Le catalogue porte deja
    # l'emprise de chaque dalle (`xmin`/`ymin`/`xmax`/`ymax`), il suffit de s'en
    # servir.
    laz <- .dalles_utiles(dalles, grille)
    sigma_surf <- .dsr_canaux_dalles(laz, grille, specs = specs$surface)$sigma_surf
  }
  if (is.null(sigma_surf)) {
    # Pas de guillemets francais ICI : R CMD check refuse le non-ASCII dans un
    # LITTERAL de chaine (il le tolere en commentaire). Cf. memoire « rcmdcheck
    # avant push ».
    cli::cli_warn("Detection sans canal de surface : detection nettement moins
                   sure (cf. {.fn dsr_indice_detection}).")
  }

  # `ref` est deja calcule en amont (le mode "auto" en a besoin pour calibrer).
  det <- tryCatch(
    do.call(.dsr("dsr_detecter"), c(
      list(sigma_geo, reference = ref, vesselness = vess,
        sigma_surf = sigma_surf, seuil = seuil, buffer_ref = buffer_ref,
        methode = methode,
        long_min = long_min, emprise = emprise,
        regime = if (is.null(emprise)) "complet" else "corridor"),
      if (!is.null(poids)) list(poids = poids),
      if (!is.null(seuil_vessel)) list(seuil_vessel = seuil_vessel))),
    error = function(e) {
      cli::cli_warn("Detection echouee : {conditionMessage(e)}.")
      NULL
    }
  )
  if (is.null(det) || nrow(sf::st_as_sf(det)) == 0) {
    return(vide(!is.null(sigma_surf)))
  }
  out <- sf::st_as_sf(det)
  out$source <- "detectee"
  if (!("p_desserte" %in% names(out))) {
    out$p_desserte <- NA_real_
  }
  out <- out[, c("source", "p_desserte"), drop = FALSE]
  # L'attribut, pas seulement l'avertissement : `cli_warn` produit une condition
  # que R DIFFERE jusqu'au retour au niveau superieur. Dans un `Rscript`, le
  # « Detection sans canal de surface » n'apparait donc qu'a la toute fin -- le
  # balayage wsfi du 2026-07-31 a tourne 82 min sans qu'on puisse savoir, en
  # cours de route, si le canal pondere DOUBLE etait la. Un banc doit pouvoir
  # l'affirmer, pas le supposer d'apres la presence de fichiers .laz sur le
  # disque (un invariant qui passe a vide, cf. lecon Phase B).
  attr(out, "canal_surface") <- !is.null(sigma_surf)
  out
  # nocov end
}

#' Balayage de seuils pour la détection (spec 026, CA-26.5)
#'
#' La spec 026 ne pose pas un seuil : elle **mesure où la détection décroche**.
#' Ce balayage rend, pour chaque seuil, le linéaire détecté et la part recoupant
#' un objet **BD TOPO connu** — des faux positifs quantifiés sans annotation.
#'
#' @details
#' Le recoupement automatique ne **remplace pas** l'annotation sur orthophoto : il
#' la réduit. Un linéaire qui ne recoupe aucun objet connu n'est pas pour autant
#' une desserte — ce peut être une terrasse, une limite parcellaire non
#' cartographiée, ou une trace fossile. Le CA-26.5 n'est pas satisfait sans la
#' part annotée.
#'
#' @section Performance:
#' **`length(seuils)` fois le cout de [detecter_desserte()]** : la pile de
#' couches et le canal de surface sont rebatis a chaque seuil, rien n'est
#' memoise. Avec le defaut a cinq seuils, compter **cinq fois** la mesure citee
#' par [detecter_desserte()], pour le meme pic memoire. Outil de calage hors
#' ligne : ne jamais le cabler sur une action interactive.
#' @inheritParams detecter_desserte
#' @param seuils Seuils balayés. Défaut `seq(0.4, 0.8, by = 0.1)`, la plage
#'   prescrite par la spec 026 §7.1.
#' @param objets_connus `sf` d'objets BD TOPO (cours d'eau, fossés, limites) dont
#'   le recoupement vaut faux positif. `NULL` pour ne pas le mesurer.
#' @param tol_recoupement Demi-largeur (m) du corridor de recoupement. Défaut 10.
#' @param ... Passé à [detecter_desserte()] (`buffer_ref`, `long_min`,
#'   `emprise`, `dtm_res`).
#' @return Un `data.frame` : `seuil`, `n`, `km`, `km_recoupe`, `pct_recoupe`.
#' @seealso [detecter_desserte()], `specs/026`.
#' @export
detecter_desserte_balayage <- function(mnt, reference = NULL, las_source = NULL,
                                       seuils = seq(0.4, 0.8, by = 0.1),
                                       objets_connus = NULL, tol_recoupement = 10,
                                       ...) {
  checkmate::assert_numeric(seuils, lower = 0, upper = 1, min.len = 1)
  corr <- if (!is.null(objets_connus) && nrow(sf::st_as_sf(objets_connus)) > 0) {
    sf::st_union(sf::st_buffer(sf::st_geometry(sf::st_as_sf(objets_connus)),
      tol_recoupement))
  } else {
    NULL
  }
  lignes <- lapply(seuils, function(s) {
    d <- detecter_desserte(mnt, reference = reference, las_source = las_source,
      seuil = s, ...)
    km <- if (nrow(d)) sum(as.numeric(sf::st_length(d))) / 1000 else 0
    # Recoupement : longueur DANS le corridor des objets connus.
    km_rec <- if (nrow(d) && !is.null(corr)) {
      g <- sf::st_intersection(sf::st_geometry(d), corr)
      if (length(g)) sum(as.numeric(sf::st_length(g))) / 1000 else 0
    } else {
      NA_real_
    }
    data.frame(seuil = s, n = nrow(d), km = km, km_recoupe = km_rec,
      pct_recoupe = if (km > 0) 100 * km_rec / km else NA_real_)
  })
  do.call(rbind, lignes)
}
