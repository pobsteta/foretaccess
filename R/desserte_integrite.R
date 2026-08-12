# Contraintes d'integrite du reseau de desserte (spec 025, annexe ACCESSFOR p.51).
#
#   - la classe 1 (piste) doit etre connectee a une 2 ou 3 ;
#   - la classe 2 (route forestiere) doit etre connectee a une 3 (reseau public).
#
# Elles ne sont pas decoratives : une piste dont le bois n'atteint aucune route
# est un cul-de-sac ou le debardage n'aboutit pas. Un reseau qui les viole
# produit des surfaces declarees accessibles qui ne le sont pas.
#
# ACCESSFOR les fait respecter par un script FME PLUS des retouches manuelles.
# Sylvaccess, lui, se contente d'AVERTIR (fichier `Pistes_non_connectees`). On
# suit Sylvaccess : on diagnostique et on marque, on ne corrige pas d'office --
# corriger automatiquement retirerait de la desserte reelle des que le
# diagnostic se trompe.
#
# Le graphe vient de `dsr_reseau()` (dessertR) : collage de noeuds, deduplication
# des paralleles, composantes connexes, `connecte_public` par arete. Regle
# stricte 1 : on consomme, on ne reimplemente pas.

.PKG_IGRAPH <- "igraph"

# Diagnostic NON EFFECTUE, mêmes colonnes (CA-25.1).
#
# La dégradation reste douce -- l'objet garde sa forme, les appelants qui lisent
# `troncons` ne cassent pas -- mais elle ne doit plus être SILENCIEUSE. Un résumé
# à `n_infractions = NA` rendu dans une interface **se lit comme « aucune
# infraction »** : une fausse réassurance sur exactement la question posée. Le
# champ `disponible` porte donc le fait, et `raison` le pourquoi ; `print()` le
# dit en toutes lettres au lieu d'omettre la ligne.
.integrite_vide <- function(desserte, raison = NA_character_) {
  d <- sf::st_as_sf(desserte)
  d$composant <- NA_integer_
  d$connecte_public <- NA
  d$viole_contrainte <- NA
  d$cause <- NA_character_
  structure(
    list(
      troncons = d,
      resume = c(n_troncons = nrow(d), n_infractions = NA_integer_,
                 longueur_infraction_m = NA_real_, n_composants = NA_integer_,
                 n_composants_orphelins = NA_integer_),
      courbe = NULL,
      disponible = FALSE,
      raison = raison
    ),
    class = "foretaccess_integrite"
  )
}

#' Vérifie les contraintes d'intégrité du réseau de desserte (spec 025)
#'
#' Applique les deux contraintes de l'annexe ACCESSFOR (rapport février 2025,
#' p. 51) : une **piste** doit être connectée à une route forestière ou au réseau
#' public, une **route forestière** au réseau public. Les tronçons qui les violent
#' sont **signalés, jamais retirés**.
#'
#' @details
#' **Trois causes, de nature différente**, qu'il faut séparer avant toute
#' remédiation :
#'
#' * `bord_aoi` — la composante touche le bord de l'emprise : le raccordement est
#'   probablement hors AOI, c'est un artefact de découpe et non un défaut ;
#' * `topologie` — l'infraction disparaît quand on relâche la tolérance de
#'   collage des nœuds : extrémités non nodées, écarts décimétriques ;
#' * `reel` — ni l'un ni l'autre. C'est une information, pas une erreur.
#'
#' **Aucune donnée n'est modifiée.** Le recollage de nœuds (niveau 2) n'est
#' appliqué que si `tol_noeud` est explicitement augmenté ; la suppression de
#' composantes (niveau 3) **n'existe pas** dans ce code. C'est ce qu'ACCESSFOR a
#' fait à la main, et l'automatiser retirerait de la desserte réelle dès que le
#' diagnostic se trompe. Sylvaccess lui-même se contente d'avertir.
#'
#' @param desserte Réseau de desserte : `sf` de lignes portant `classe`
#'   (sortie d'[acquire_desserte()]).
#' @param aoi Emprise (`sf`/`sfc`) servant à détecter les composantes touchant le
#'   bord. `NULL` : la cause `bord_aoi` n'est pas attribuée.
#' @param tol_noeud Distance (m) de collage des extrémités. Défaut 1.
#' @param tol_test_topologie Tolérance relâchée servant à tester la cause
#'   `topologie` : une infraction qui disparaît à cette tolérance en relève.
#'   Défaut 5.
#' @param marge_bord_m Distance (m) au bord de l'`aoi` en deçà de laquelle une
#'   composante est réputée le toucher. Défaut 10.
#' @param largeur_dedupe Écart (m) de déduplication des parallèles passé à
#'   `dsr_reseau()`. **Défaut 0 : désactivée.** La valeur 3 de dessertR vise des
#'   tracés forestiers corrigés indépendamment, où deux parallèles proches sont
#'   un artefact. Sur un réseau incluant le **réseau public** (chaussées
#'   séparées, giratoires, contre-allées) elle coupe des liaisons **réelles** :
#'   mesuré sur l'AOI oracle à 1600 m de buffer, elle retirait 260 tronçons sur
#'   1003 et fragmentait le graphe en 69 composantes dont 34 isolées, fabriquant
#'   21 fausses infractions.
#' @return Un objet `foretaccess_integrite` : `troncons` (`sf` avec `composant`,
#'   `connecte_public`, `viole_contrainte`, `cause`), `resume` (compteurs),
#'   `courbe` (`NULL` ici, renseigné par [integrite_buffer_adaptatif()]),
#'   `disponible` et `raison`.
#'
#'   **Lire `disponible` avant `resume`.** Sans `dessertR`/`igraph`, ou si
#'   `dsr_reseau()` n'aboutit pas, le diagnostic n'est pas effectué : `resume`
#'   est alors tout en `NA` et un avertissement est émis. Un `n_infractions` à
#'   `NA` signifie **« on ne sait pas »**, jamais « aucune infraction » — ne
#'   l'affichez pas comme un verdict. [dessertR_disponible()] permet de poser la
#'   question *avant* de lancer le calcul.
#' @seealso [dessertR_disponible()], [integrite_buffer_adaptatif()],
#'   [acquire_desserte()], `specs/025`.
#' @export
verifier_integrite_desserte <- function(desserte, aoi = NULL, tol_noeud = 1,
                                        tol_test_topologie = 5,
                                        marge_bord_m = 10,
                                        largeur_dedupe = 0) {
  d <- sf::st_as_sf(.as_vector(desserte, "desserte"))
  if (!("classe" %in% names(d))) {
    cli::cli_abort("{.arg desserte} doit porter un champ {.field classe}.")
  }
  # AVERTISSEMENT, pas information : un diagnostic non effectue rendu tel quel se
  # lit comme un diagnostic sans infraction. `cli_inform` se perd dans un log de
  # worker ; un warning se voit, se capture (`withCallingHandlers`) et remonte.
  manque <- c(
    if (!.dessertr_dispo()) .PKG_DESSERTR,
    if (!requireNamespace(.PKG_IGRAPH, quietly = TRUE)) .PKG_IGRAPH
  )
  if (length(manque)) {
    cli::cli_warn(c(
      "!" = "Integrite {.strong NON CONTROLEE} : {.pkg {manque}} absent{?s}.",
      "x" = "Le resultat n'est pas {.strong aucune infraction} : c'est
             {.strong on ne sait pas}.",
      "i" = "{.code remotes::install_github(\"pobsteta/dessertR\")}",
      "i" = "Tester d'avance avec {.fn dessertR_disponible}."
    ))
    return(.integrite_vide(d, paste0("paquet absent : ", toString(manque))))
  }
  # nocov start : chemin dessertR/igraph, hors CI (valide sur l'AOI oracle).
  res <- .integrite_calculer(d, tol_noeud, largeur_dedupe)
  if (is.null(res)) {
    # dessertR est la, mais `dsr_reseau` a echoue (couche degeneree, geometries
    # inexploitables). Ce chemin ne disait RIEN du tout : pire que l'absence de
    # paquet, puisque rien ne signalait meme l'indisponibilite.
    cli::cli_warn(c(
      "!" = "Integrite {.strong NON CONTROLEE} : {.fn dsr_reseau} n'a pas abouti.",
      "i" = "Couche degeneree ou geometries inexploitables (lignes nulles,
             {.val NA}, auto-intersections)."
    ))
    return(.integrite_vide(d, "dsr_reseau n'a pas abouti"))
  }
  res$disponible <- TRUE
  res$raison <- NA_character_
  res$troncons$cause <- .integrite_causes(res$troncons, d, aoi,
    tol_noeud, tol_test_topologie, marge_bord_m, largeur_dedupe)
  res
  # nocov end
}

# Coeur du diagnostic : graphe, composantes, contraintes. NULL si dsr_reseau
# echoue (couche degeneree, geometries inexploitables).
.integrite_calculer <- function(d, tol_noeud, largeur_dedupe = 0) { # nocov start
  traces <- .troncons_linestring_tous(d)
  if (is.null(traces) || nrow(traces) == 0) {
    return(NULL)
  }
  pub <- traces[traces$classe == "reseau_public", ]
  res <- tryCatch(
    .dsr("dsr_reseau")(traces, tol_noeud = tol_noeud,
      largeur_dedupe = largeur_dedupe,
      reseau_public = if (nrow(pub)) sf::st_geometry(pub) else NULL),
    error = function(e) NULL
  )
  if (is.null(res) || is.null(res$aretes)) {
    return(NULL)
  }
  ar <- sf::st_as_sf(res$aretes)
  ar$viole_contrainte <- .integrite_violations(ar)
  long <- as.numeric(sf::st_length(ar))
  comp <- ar$composant
  a_route <- tapply(ar$classe %in% c("route", "reseau_public"), comp, any)

  structure(
    list(
      troncons = ar,
      resume = c(
        n_troncons = nrow(ar),
        n_infractions = sum(ar$viole_contrainte, na.rm = TRUE),
        longueur_infraction_m = sum(long[ar$viole_contrainte], na.rm = TRUE),
        n_composants = length(unique(comp)),
        n_composants_orphelins = sum(!a_route, na.rm = TRUE)
      ),
      courbe = NULL
    ),
    class = "foretaccess_integrite"
  )
}

# Les deux contraintes de l'annexe p.51, evaluees PAR COMPOSANTE.
.integrite_violations <- function(ar) {
  cl <- as.character(ar$classe)
  comp <- as.character(ar$composant)
  a_route <- tapply(cl %in% c("route", "reseau_public"), comp, any)
  a_public <- tapply(cl == "reseau_public", comp, any)
  v <- rep(FALSE, nrow(ar))
  est_piste <- cl == "piste"
  est_route <- cl == "route"
  v[est_piste] <- !a_route[comp[est_piste]]
  v[est_route] <- !a_public[comp[est_route]]
  v[is.na(v)] <- FALSE
  v
}

# Attribution de la cause probable (CA-25.2). L'ordre compte : le bord d'AOI
# prime, car une composante coupee par la decoupe n'est pas diagnosticable
# autrement -- son raccordement est hors emprise, par construction.
.integrite_causes <- function(ar, d, aoi, tol_noeud, tol_relachee, marge,
                              largeur_dedupe = 0) {
  cause <- rep(NA_character_, nrow(ar))
  viole <- ar$viole_contrainte
  if (!any(viole)) {
    return(cause)
  }
  # 1. Bord d'AOI : la composante touche-t-elle la limite de l'emprise ?
  if (!is.null(aoi)) {
    bord <- sf::st_boundary(sf::st_union(sf::st_geometry(sf::st_as_sf(aoi))))
    pres_bord <- lengths(sf::st_is_within_distance(sf::st_geometry(ar), bord,
      dist = marge)) > 0
    comp_bord <- unique(ar$composant[pres_bord])
    cause[viole & ar$composant %in% comp_bord] <- "bord_aoi"
  }
  # 2. Topologie : l'infraction survit-elle a une tolerance de collage relachee ?
  reste <- viole & is.na(cause)
  if (any(reste) && tol_relachee > tol_noeud) {
    r2 <- .integrite_calculer(d, tol_relachee, largeur_dedupe)
    if (!is.null(r2) && nrow(r2$troncons) == nrow(ar)) {
      # Meme cardinalite : l'appariement positionnel tient. Sinon on s'abstient
      # plutot que d'apparier a l'aveugle.
      guerie <- reste & !r2$troncons$viole_contrainte
      cause[guerie] <- "topologie"
    }
  }
  # 3. Le reste est reel.
  cause[viole & is.na(cause)] <- "reel"
  cause
} # nocov end

# Toutes les geometries ramenees a des LINESTRING uniques, `classe` conservee.
.troncons_linestring_tous <- function(d) {
  ls <- lapply(seq_len(nrow(d)), function(i) .troncon_linestring(d[i, ]))
  ok <- !vapply(ls, is.null, logical(1))
  if (!any(ok)) {
    return(NULL)
  }
  do.call(rbind, ls[ok])
}

#' @export
print.foretaccess_integrite <- function(x, ...) {
  r <- x$resume
  cli::cli_h3("Integrite du reseau de desserte (spec 025)")
  # Un diagnostic non effectue se DIT. Auparavant la ligne « Infractions » etait
  # simplement omise, et un lecteur presse y voyait un reseau sans infraction.
  if (isFALSE(x$disponible)) {
    cli::cli_text("{r[['n_troncons']]} troncon{?s}.")
    cli::cli_alert_danger("Diagnostic {.strong NON EFFECTUE}
                          {if (!is.na(x$raison)) paste0('(', x$raison, ')') else ''}.")
    cli::cli_alert_info("Ce n'est pas {.strong aucune infraction} : c'est
                         {.strong on ne sait pas}.")
    return(invisible(x))
  }
  cli::cli_text("{r[['n_troncons']]} troncon{?s}, {r[['n_composants']]} composante{?s},
                 dont {r[['n_composants_orphelins']]} orpheline{?s}.")
  if (!is.na(r[["n_infractions"]])) {
    cli::cli_text("Infractions : {r[['n_infractions']]}
                   ({round(r[['longueur_infraction_m']] / 1000, 2)} km).")
    if (!all(is.na(x$troncons$cause))) {
      print(table(cause = x$troncons$cause, useNA = "no"))
    }
  }
  invisible(x)
}

#' Élargissement adaptatif de l'emprise pour distinguer l'effet de bord (spec 025)
#'
#' Une piste connectée à une route située **hors de l'AOI** paraît orpheline :
#' c'est un artefact de découpe, pas un défaut de donnée. Plutôt que de deviner un
#' buffer, on le fait **converger**.
#'
#' @details
#' Le point qui fait la validité de la méthode : la longueur en infraction est
#' mesurée **sur l'AOI stricte** à chaque itération. Mesurée sur l'emprise
#' élargie, elle augmenterait mécaniquement (plus de réseau, donc plus
#' d'infractions) et la suite ne convergerait jamais.
#'
#' La **décroissance de `L(b)` sépare les causes** : ce qui disparaît en
#' élargissant était un effet de bord ; ce qui résiste à un buffer large est
#' topologique ou réel. La courbe est le diagnostic, pas un sous-produit.
#'
#' @param aoi Emprise stricte (`sf`/`sfc`).
#' @param acquerir Fonction `function(emprise)` rendant la desserte sur cette
#'   emprise. Défaut : [acquire_desserte()] avec les réglages courants.
#' @param buffer_initial,buffer_max Bornes du balayage (m). Défauts 100 et 3000 --
#'   au-delà on téléchargerait un département pour rattacher une piste.
#' @param facteur Multiplicateur d'une itération à l'autre. Défaut 2.
#' @param gain_min Arrêt quand la décroissance relative de `L(b)` passe sous ce
#'   seuil. Défaut 0,05 (5 %).
#' @param ... Passé à [verifier_integrite_desserte()].
#' @return Un objet `foretaccess_integrite` du dernier buffer, dont `courbe` est
#'   un `data.frame` (`buffer_m`, `n_infractions`, `longueur_infraction_m`).
#' @seealso [verifier_integrite_desserte()], `specs/025`.
#' @export
integrite_buffer_adaptatif <- function(aoi, acquerir = NULL,
                                       buffer_initial = 100, buffer_max = 3000,
                                       facteur = 2, gain_min = 0.05, ...) {
  checkmate::assert_number(buffer_initial, lower = 0, finite = TRUE)
  checkmate::assert_number(buffer_max, lower = buffer_initial, finite = TRUE)
  checkmate::assert_number(facteur, lower = 1.0001, finite = TRUE)
  if (is.null(acquerir)) {
    acquerir <- function(emprise) acquire_desserte(emprise) # nocov
  }
  aoi_sf <- sf::st_as_sf(sf::st_geometry(sf::st_as_sf(aoi)))
  courbe <- data.frame(buffer_m = numeric(0), n_infractions = integer(0),
                       longueur_infraction_m = numeric(0))
  b <- buffer_initial
  dernier <- NULL
  precedent <- NA_real_
  repeat {
    des <- acquerir(sf::st_buffer(aoi_sf, b))
    diag <- verifier_integrite_desserte(des, aoi = aoi_sf, ...)
    # MESURE SUR L'AOI STRICTE : sans ce clip, elargir ajoute du reseau donc des
    # infractions, et la suite ne converge pas.
    tr <- diag$troncons
    dedans <- lengths(sf::st_intersects(sf::st_geometry(tr),
      sf::st_geometry(aoi_sf))) > 0
    viole <- isTRUE_vec(tr$viole_contrainte) & dedans
    l <- sum(as.numeric(sf::st_length(tr))[viole], na.rm = TRUE)
    courbe <- rbind(courbe, data.frame(buffer_m = b, n_infractions = sum(viole),
                                       longueur_infraction_m = l))
    dernier <- diag
    gain <- if (is.na(precedent) || precedent <= 0) Inf else (precedent - l) / precedent
    if (b >= buffer_max || (is.finite(gain) && gain < gain_min)) {
      break
    }
    precedent <- l
    b <- min(b * facteur, buffer_max)
  }
  dernier$courbe <- courbe
  dernier
}

# `viole_contrainte` peut porter des NA (troncons non diagnostiques) : on les
# traite comme non-infractions plutot que de propager le NA dans une somme.
isTRUE_vec <- function(x) {
  x <- as.logical(x)
  x[is.na(x)] <- FALSE
  x
}
