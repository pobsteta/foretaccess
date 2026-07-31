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
#' @param specs Bornes d'appartenance, voir [specs_desserte_calibrees()] (défaut).
#'   **`NULL` restaure les specs de dessertR**, dont les bornes sont dérivées par
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
                              specs = specs_desserte_calibrees()) {
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
  vess <- if ("vesselness" %in% names(pile)) pile[["vesselness"]] else NULL

  # Canal de surface : c'est LUI qui porte le signal -- AUC 0,870 sur
  # `taux_penetration`, le meilleur des quatre canaux calibres.
  sigma_surf <- NULL
  if (!is.null(las_source)) {
    dalles <- tryCatch(.dsr("dsr_catalog")(laz = las_source), error = function(e) NULL)
    laz <- if (!is.null(dalles) && !is.null(dalles$laz)) as.character(dalles$laz) else character(0)
    sigma_surf <- .dsr_canaux_dalles(laz, grille, specs = specs$surface)$sigma_surf
  }
  if (is.null(sigma_surf)) {
    # Pas de guillemets francais ICI : R CMD check refuse le non-ASCII dans un
    # LITTERAL de chaine (il le tolere en commentaire). Cf. memoire « rcmdcheck
    # avant push ».
    cli::cli_warn("Detection sans canal de surface : detection nettement moins
                   sure (cf. {.fn dsr_indice_detection}).")
  }

  ref <- if (!is.null(reference)) sf::st_geometry(sf::st_as_sf(reference)) else NULL
  det <- tryCatch(
    .dsr("dsr_detecter")(sigma_geo, reference = ref, vesselness = vess,
      sigma_surf = sigma_surf, seuil = seuil, buffer_ref = buffer_ref,
      long_min = long_min, emprise = emprise,
      regime = if (is.null(emprise)) "complet" else "corridor"),
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
