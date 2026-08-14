# Classement des lineaires detectes (spec 030 sec. 4) : desserte, piste,
# cloisonnement, layon parcellaire, pare-feu.
#
# La logique est celle de `dessertR::dsr_classer()` -- on CONSOMME le moteur, on
# ne le reimplemente pas (regle stricte 1). Ce fichier n'existe que pour une
# raison, et elle est de dependance : `nemetonshiny` appelait
# `dessertR::dsr_classer()` DIRECTEMENT, alors que `dessertR` n'etait declare
# nulle part dans son DESCRIPTION, l'appel etant enveloppe dans un
# `tryCatch(error = function(e) NULL)`. Sur un poste sans dessertR, le classement
# disparaissait donc sans le dire : la carte montrait des lineaires detectes non
# classes, indiscernables de lineaires que le moteur aurait juges indeterminables.
#
# Le sens des dependances est : l'app depend de `foretaccess`, jamais de son
# moteur. D'ou ce wrapper -- et l'indisponibilite y devient VISIBLE (avertissement
# + attribut `disponible`), au lieu d'etre avalee.

#' Classify detected linear features (desserte, skid trail, firebreak...)
#'
#' Wraps `dessertR::dsr_classer()`: labels each line of a **detected** network
#' with `CLASSE`, `CLASSE_CONF` (share of informed criteria that agree),
#' `CLASSE_MOTIF` (which criteria voted) and `OSM_TAGS` (a *proposed* tagging,
#' never uploaded).
#'
#' @details
#' **Why it lives here.** Callers depend on `foretaccess`, never on its engine.
#' The app used to call `dessertR::dsr_classer()` directly, wrapped in a
#' `tryCatch()` that returned `NULL`: without `dessertR` installed the
#' classification vanished **silently**. Here the unavailability is a warning and
#' an attribute, not an absence.
#'
#' **Geometry.** `dsr_classer()` requires `LINESTRING`; BD TOPO and most
#' detection outputs are `MULTILINESTRING`. The recast is done here, once.
#'
#' **The criteria you do not pass are unknown, not false.** `stations`
#' ([acquire_desserte_lidar()]'s measurement), `ndvi` and `tpi` each switch on a
#' family of criteria; without them `dessertR` declares them unknown and
#' `CLASSE_CONF` drops. **Always display `CLASSE_CONF` next to `CLASSE`.**
#'
#' @param traces Detected network: path or `sf` of lines (the output of
#'   [detecter_desserte()]).
#' @param reference Reference network (`sf`/`sfc`, e.g. BD TOPO): what it carries
#'   is a desserte. `NULL` to judge every line on its structure alone.
#' @param parcellaire Forest compartment boundaries (`sf`/`sfc`) or `NULL`.
#' @param sous_type_parcelle OSM sub-type of those boundaries: `"section"`
#'   (management units -- boundaries marked on the ground) or `"border"`
#'   (cadastral property limits). Passed **explicitly** to `dessertR`, which
#'   otherwise emits a notice: the value cannot be read off the geometry.
#' @param stations Per-station measurements (`sf`/`data.frame` with a `troncon`
#'   column, from `dsr_measure()`) or `NULL`.
#' @param ndvi `SpatRaster` of NDVI, or `NULL` -- without it, road/track is never
#'   decided and `pare_feu` is never posted.
#' @param tpi `SpatRaster` of topographic position, or `NULL`.
#' @param ... Passed to `dessertR::dsr_classer()`.
#' @return The input `sf` with `CLASSE`, `CLASSE_CONF`, `CLASSE_MOTIF` and
#'   `OSM_TAGS`. Attribute `disponible`: `FALSE` when `dessertR` is missing or
#'   the classification failed -- the columns are then all `NA` and a **warning**
#'   is emitted. `NA` classes mean *"not classified"*, never *"nothing found"*.
#' @seealso [detecter_desserte()], [dessertR_disponible()], `specs/030`.
#' @export
#' @examples
#' det <- sf::st_sf(geometry = sf::st_sfc(
#'   sf::st_linestring(rbind(c(0, 0), c(100, 0))), crs = 2154))
#' cl <- classer_desserte(det)      # sans dessertR : colonnes a NA, avertissement
#' attr(cl, "disponible")
classer_desserte <- function(traces, reference = NULL, parcellaire = NULL,
                             sous_type_parcelle = c("section", "border"),
                             stations = NULL, ndvi = NULL, tpi = NULL, ...) {
  sous_type_parcelle <- match.arg(sous_type_parcelle)
  tr <- sf::st_zm(sf::st_as_sf(.as_vector(traces, "traces")), drop = TRUE)
  if (nrow(tr) == 0) {
    cli::cli_abort("La couche {.arg traces} est vide.")
  }

  if (!.dessertr_dispo()) {
    cli::cli_warn(c(
      "!" = "Lineaires {.strong NON CLASSES} : {.pkg dessertR} absent.",
      "x" = "Une classe {.val NA} signifie {.strong non classe}, jamais
             {.strong rien trouve}.",
      "i" = "{.code remotes::install_github(\"pobsteta/dessertR\")}",
      "i" = "Tester d'avance avec {.fn dessertR_disponible}."
    ))
    return(.classes_vides(tr))
  }

  # nocov start : chemin dessertR, absent de la CI.
  lin <- tryCatch(
    if (any(sf::st_geometry_type(tr) != "LINESTRING")) {
      suppressWarnings(sf::st_cast(tr, "LINESTRING"))
    } else {
      tr
    },
    error = function(e) NULL
  )
  cl <- if (is.null(lin)) {
    NULL
  } else {
    tryCatch(
      .dsr("dsr_classer")(lin, stations = stations, ndvi = ndvi,
        reference = reference, parcellaire = parcellaire, tpi = tpi,
        sous_type_parcelle = sous_type_parcelle, ...),
      error = function(e) {
        cli::cli_warn(c(
          "!" = "Lineaires {.strong NON CLASSES} : {.fn dsr_classer} a echoue.",
          "x" = conditionMessage(e)
        ))
        NULL
      }
    )
  }
  if (!inherits(cl, "sf") || !("CLASSE" %in% names(cl))) {
    return(.classes_vides(tr))
  }
  attr(cl, "disponible") <- TRUE
  cl
  # nocov end
}

# Classement NON EFFECTUE, memes colonnes : l'appelant qui lit `CLASSE` ne casse
# pas, mais `disponible` porte le fait.
.classes_vides <- function(tr) {
  tr$CLASSE <- NA_character_
  tr$CLASSE_CONF <- NA_real_
  tr$CLASSE_MOTIF <- NA_character_
  tr$OSM_TAGS <- NA_character_
  attr(tr, "disponible") <- FALSE
  tr
}
