# Provenance des caches d'acquisition (spec 027).
#
# Un cache est nomme d'apres ce qu'il CONTIENT (`desserte.gpkg`, `mnt.tif`),
# jamais d'apres ce qui l'a PRODUIT. Toute correction du code est donc annulee
# en silence pour quiconque possede deja un cache. Cinq incidents en deux jours
# (PLAN.md, 2026-07-29/30), tous de cette cause :
#
#   classification desserte : mapping heuristique servi apres le passage en clsvac
#   masque foret            : 13 polygones de landes, exclus par ACCESSFOR
#   MNT (14 juillet)        : RGE ALTI par WMS, blocky, pentes fausses a 382 %
#   acquisition WFS         : reseau ampute de 110 troncons interieurs
#   DFCI / Overpass         : « injoignable » rendu comme « rien ici »
#
# Le troisieme a fait tourner le banc `aoi` DEUX SEMAINES sur un terrain fictif.
#
# On enregistre donc, a cote de chaque fichier de cache, un sidecar decrivant ce
# qui l'a produit ; a la relecture on compare aux parametres de l'appel courant.
# Le SIDECAR plutot qu'un nom de fichier encode : le nom reste lisible et stable
# pour les outils SIG, et la provenance peut s'enrichir sans casser les chemins.

.POLITIQUES_CACHE <- c("reacquerir", "avertir", "echouer", "ignorer")

# Chemin du sidecar d'un fichier de cache.
.chemin_provenance <- function(chemin) paste0(chemin, ".provenance.json")

# Ecrit la provenance. `params` ne doit contenir que ce qui CHANGE LE CONTENU :
# une provenance trop bavarde invaliderait des caches sains et pousserait a
# mettre `politique_cache = "ignorer"`, ce qui ramenerait au probleme de depart.
.provenance_ecrire <- function(chemin, couche, source = NULL, params = list()) {
  p <- list(
    couche = couche,
    source = source %||% NA_character_,
    version_paquet = as.character(utils::packageVersion("foretaccess")),
    date = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    parametres = params
  )
  tryCatch(
    jsonlite::write_json(p, .chemin_provenance(chemin), auto_unbox = TRUE,
      pretty = TRUE, null = "null"),
    error = function(e) invisible(NULL) # un cache sans sidecar reste utilisable
  )
  invisible(p)
}

.provenance_lire <- function(chemin) {
  f <- .chemin_provenance(chemin)
  if (!file.exists(f)) {
    return(NULL)
  }
  tryCatch(jsonlite::read_json(f, simplifyVector = TRUE), error = function(e) NULL)
}

# Compare la provenance enregistree aux parametres attendus. Rend le vecteur des
# noms qui DIVERGENT (vide si tout concorde). Un parametre absent du sidecar
# compte comme divergent : on ne peut pas savoir, donc on ne suppose pas.
.provenance_diff <- function(prov, source, params) {
  if (is.null(prov)) {
    return("sidecar_absent")
  }
  d <- character(0)
  if (!is.null(source) && !identical(as.character(prov$source), as.character(source))) {
    d <- c(d, "source")
  }
  enr <- prov$parametres
  for (n in names(params)) {
    a <- params[[n]]
    b <- if (is.list(enr) && n %in% names(enr)) enr[[n]] else NULL
    if (is.null(b) || !isTRUE(all.equal(as.character(a), as.character(b)))) {
      d <- c(d, n)
    }
  }
  d
}

#' Politique de réutilisation des caches d'acquisition
#'
#' Que faire quand un cache existe mais **n'a pas été produit avec les paramètres
#' de l'appel courant** ? Défaut `"reacquerir"` : le coût d'une ré-acquisition est
#' mesurable, celui d'un résultat faux ne l'est pas.
#'
#' @details
#' * `"reacquerir"` — ignore le cache divergent et refait l'acquisition ;
#' * `"avertir"` — sert le cache en nommant ce qui diverge ;
#' * `"echouer"` — interrompt : pour les bancs et la CI, où un cache périmé
#'   fausse une mesure publiée ;
#' * `"ignorer"` — aucun contrôle, comportement antérieur à la v1.29.0.
#'
#' Un cache **sans sidecar** de provenance (antérieur à cette version) est traité
#' comme divergent, avec un message distinct : on ne peut pas savoir, donc on ne
#' suppose pas que c'est bon.
#'
#' @param chemin Chemin du fichier de cache.
#' @param couche Nom de la couche (`"desserte"`, `"mnt"`, ...).
#' @param source Identifiant de la source (typename WFS, couche WMS...).
#' @param params Liste nommée des paramètres qui **changent le contenu**.
#' @param politique Une valeur de [politique_cache_valeurs()].
#' @return `TRUE` si le cache est utilisable en l'état, `FALSE` sinon.
#' @seealso `specs/027`.
#' @export
cache_utilisable <- function(chemin, couche, source = NULL, params = list(),
                             politique = "reacquerir") {
  politique <- match.arg(politique, .POLITIQUES_CACHE)
  if (identical(politique, "ignorer") || !file.exists(chemin)) {
    return(file.exists(chemin))
  }
  d <- .provenance_diff(.provenance_lire(chemin), source, params)
  if (!length(d)) {
    return(TRUE)
  }
  absent <- identical(d, "sidecar_absent")
  msg <- if (absent) {
    "Cache {.file {basename(chemin)}} sans provenance (anterieur a la v1.29.0) :
     impossible de savoir avec quels parametres il a ete produit."
  } else {
    "Cache {.file {basename(chemin)}} produit avec d'autres parametres :
     {.field {d}}."
  }
  switch(politique,
    echouer = cli::cli_abort(c(msg,
      "i" = "Passer {.code politique_cache = \"reacquerir\"} ou purger le cache.")),
    avertir = {
      cli::cli_warn(c(msg, "!" = "Cache servi tel quel : le resultat peut ne pas
                                  refleter les parametres demandes."))
      TRUE
    },
    reacquerir = {
      cli::cli_inform(c(msg, "i" = "Re-acquisition."))
      FALSE
    }
  )
}

#' Valeurs admises pour `politique_cache`
#'
#' @return Un vecteur de caractères.
#' @seealso [cache_utilisable()], `specs/027`.
#' @export
politique_cache_valeurs <- function() .POLITIQUES_CACHE
