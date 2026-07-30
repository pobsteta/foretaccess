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
#' @return Un `sf` de `LINESTRING` avec `source = "detectee"` et `p_desserte`.
#'   Sans `dessertR`, une couche vide et un message — jamais d'échec.
#' @seealso [detecter_desserte_balayage()], [qualifier_desserte()],
#'   [acquire_desserte_osm()], `specs/026`.
#' @export
detecter_desserte <- function(mnt, reference = NULL, las_source = NULL,
                              seuil = 0.6, buffer_ref = 15, long_min = 30,
                              emprise = NULL, dtm_res = 1) {
  checkmate::assert_number(seuil, lower = 0, upper = 1)
  vide <- sf::st_sf(source = character(0), p_desserte = numeric(0),
    geometry = sf::st_sfc())
  if (!.dessertr_dispo()) {
    cli::cli_inform(c(
      "!" = "Detection indisponible ({.pkg dessertR} absent) : couche vide.",
      "i" = "{.code remotes::install_github(\"pobsteta/dessertR\")}"
    ))
    return(vide)
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
  pile <- .dsr("dsr_layers_dtm")(r, grille = grille)
  sigma_geo <- .dsr("dsr_conductivite")(pile)
  vess <- if ("vesselness" %in% names(pile)) pile[["vesselness"]] else NULL

  # Canal de surface : c'est LUI qui porte le signal. Sans nuage, dessertR
  # previent que la detection est « nettement moins sure ».
  sigma_surf <- NULL
  if (!is.null(las_source)) {
    dalles <- tryCatch(.dsr("dsr_catalog")(laz = las_source), error = function(e) NULL)
    laz <- if (!is.null(dalles) && !is.null(dalles$laz)) as.character(dalles$laz) else character(0)
    sigma_surf <- .dsr_canaux_dalles(laz, grille)$sigma_surf
  }
  if (is.null(sigma_surf)) {
    cli::cli_warn("Detection sans canal de surface : « nettement moins sure »
                   (cf. {.fn dsr_indice_detection}).")
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
    return(vide)
  }
  out <- sf::st_as_sf(det)
  out$source <- "detectee"
  if (!("p_desserte" %in% names(out))) {
    out$p_desserte <- NA_real_
  }
  out[, c("source", "p_desserte"), drop = FALSE]
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
