# Client Overpass canonique de l'ecosysteme (ADR-010).
#
# Il remplace DEUX implementations divergentes -- celle d'ici (via `osmdata`) et
# celle de `dessertR` (via `system2("curl")`) -- dont chacune avait raison la ou
# l'autre se trompait. Les rationales qui suivent sont le produit d'incidents
# reels : elles migrent avec le code, elles ne meurent pas avec lui.

# Instances Overpass, essayees dans l'ordre. L'instance principale limite
# agressivement le debit : une session un peu active se fait refuser, et les
# miroirs n'ont pas les memes quotas. Mesure du 2026-07-30 : apres une journee de
# requetes, l'instance par defaut refusait tout tandis qu'un miroir repondait
# immediatement.
OSM_SERVEURS_OVERPASS <- c(
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://overpass.osm.ch/api/interpreter",
  "https://overpass.private.coffee/api/interpreter"
)

# Corps de reponse en deca duquel une instance ne peut rien avoir renvoye d'utile
# (un XML Overpass vide legitime fait deja plus). Sert de garde-fou au cas ou le
# `<remark>` manquerait.
.OSM_TAILLE_MIN <- 100L

#' Query the Overpass API for OpenStreetMap features
#'
#' The ecosystem's canonical Overpass client (ADR-010). Fetches raw XML over
#' `curl`, then reads it through GDAL's OSM driver.
#'
#' @details
#' **Three outcomes, never conflated.** This is the contract:
#'
#' | outcome | signal | behaviour |
#' |---|---|---|
#' | data | XML contains `<way` | returns the `sf` |
#' | genuinely empty | valid XML, no `<way`, **no** `<remark>` | returns an empty `sf` -- that *is* a result |
#' | refusal | `<remark>`, HTTP 429/504, timeout, or body under 100 bytes | **errors** |
#'
#' **A refusal never becomes an empty layer.** A throttled instance answers with
#' well-formed XML of a few hundred bytes, no HTTP error code, and a `<remark>`
#' element. Read naively, that says *"nothing here"* -- the mistake that hid the
#' absence of DFCI data for a whole day.
#'
#' **Why `curl` and not `osmdata`.** A saturated instance does not error, it
#' *stalls*: `osmdata` then loops on a 60 s backoff with no ceiling (16
#' consecutive retries measured, 16 minutes of pure waiting). `setTimeLimit()`
#' cannot help -- it only fires at R interpreter checkpoints, never on a socket
#' blocked inside C. The bound must live in the transport, and libcurl's
#' `timeout` provides exactly that.
#'
#' **Why instance rotation used to fail.** `osmdata::set_overpass_url()` calls
#' `overpass_status()`, so *switching instances is itself a network call*: when
#' the instance is saturated it is the switch that fails, and rotation dies
#' before trying a single mirror. Passing the URL as a loop argument removes the
#' problem by construction.
#'
#' @section Bounded duration:
#' No call can exceed `timeout * length(serveurs) * (1 + max_reprises)` seconds
#' -- 90 x 4 x 3 = **18 minutes** worst case with the defaults, and a few seconds
#' nominally. Lower `timeout` or shorten `serveurs` to tighten it. On HTTP 429 a
#' `Retry-After` header is honoured **only if under 10 s**; beyond that, moving to
#' the next instance beats waiting.
#'
#' @param bbox_wgs Bounding box in WGS84 (`sf::st_bbox()`, or a numeric vector
#'   `xmin, ymin, xmax, ymax`).
#' @param cle OSM key (e.g. `"highway"`), **or** a list of `list(cle=, valeur=)`
#'   filters to fetch in a **single** query as an Overpass union. Grouping
#'   filters is the point: Overpass caps the number of requests, not the area.
#' @param valeur Optional value for `cle`. Ignored when `cle` is a filter list.
#' @param timeout Per-request ceiling (s), passed to both libcurl and Overpass QL.
#' @param serveurs Instances tried in order.
#' @param max_reprises Retries per instance before moving on.
#' @param couches GDAL OSM layers to read. Default `lines` and `multipolygons`,
#'   which together cover what the obstacle and road layers need.
#' @return An `sf` (possibly with zero rows), carrying the attributes
#'   `instance`, `requete` and `date_requete` -- see [osm_provenance()].
#' @seealso [acquire_desserte_osm()], [acquire_obstacles()], [acquire_dfci()].
#' @export
#' @examples
#' # Construire la requete sans l'envoyer (aucun acces reseau) :
#' cat(foretaccess:::.osm_requete(
#'   c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01), "highway"))
osm_overpass <- function(bbox_wgs, cle, valeur = NULL, timeout = 90,
                         serveurs = OSM_SERVEURS_OVERPASS, max_reprises = 2,
                         couches = c("lines", "multipolygons")) {
  .require_pkg("curl")
  ql <- .osm_requete(bbox_wgs, cle, valeur, timeout)
  brut <- .osm_transport(ql, timeout, serveurs, max_reprises)
  out <- .osm_lire(brut$corps, couches)
  attr(out, "instance") <- brut$instance
  attr(out, "requete") <- ql
  attr(out, "date_requete") <- brut$date
  out
}

#' Provenance of an Overpass response
#'
#' @param x An `sf` returned by [osm_overpass()].
#' @return A named list: `instance`, `requete`, `date_requete`, `nb_entites`.
#'   Two runs a month apart otherwise differ with **no trace at all** -- on data
#'   feeding a network design, that is a substantive problem, not bookkeeping.
#' @seealso [osm_overpass()].
#' @export
osm_provenance <- function(x) {
  list(
    instance = attr(x, "instance") %||% NA_character_,
    requete = attr(x, "requete") %||% NA_character_,
    date_requete = attr(x, "date_requete") %||% NA_character_,
    nb_entites = if (inherits(x, "sf")) nrow(x) else NA_integer_
  )
}

# --- Requete ----------------------------------------------------------------

# Overpass QL. `cle` accepte une liste de filtres : les grouper en UNE union est
# tout l'interet, Overpass plafonnant le nombre de requetes et non la surface.
# `way` ET `relation` : sans les relations, les plans d'eau multipolygones
# manquent (ils ne sont pas des ways).
.osm_requete <- function(bbox_wgs, cle, valeur = NULL, timeout = 90) {
  b <- as.numeric(bbox_wgs[c("ymin", "xmin", "ymax", "xmax")])
  bb <- paste0("(", paste(format(b, scientific = FALSE, trim = TRUE),
                          collapse = ","), ")")
  filtres <- if (is.list(cle)) cle else list(list(cle = cle, valeur = valeur))
  sel <- vapply(filtres, function(f) {
    if (is.null(f$valeur) || !nzchar(f$valeur[1])) {
      sprintf("[\"%s\"]", f$cle)
    } else {
      sprintf("[\"%s\"=\"%s\"]", f$cle, f$valeur[1])
    }
  }, character(1))
  corps <- paste0(c(paste0("  way", sel, bb, ";"),
                    paste0("  relation", sel, bb, ";")), collapse = "\n")
  paste0("[out:xml][timeout:", as.integer(timeout), "];\n(\n", corps,
         "\n);\n(._;>;);\nout body;\n")
}

# --- Transport --------------------------------------------------------------

# Rotation d'instances. L'URL est un simple argument de boucle : contrairement a
# `osmdata::set_overpass_url()`, basculer ne coute AUCUN appel reseau, donc la
# rotation survit a une instance saturee.
.osm_transport <- function(ql, timeout, serveurs, max_reprises) {
  derniere <- NULL
  for (i in seq_along(serveurs)) {
    u <- serveurs[i]
    for (essai in seq_len(max_reprises + 1L)) {
      rep <- .osm_curl(u, ql, timeout)
      verdict <- .osm_verdict(rep)
      if (identical(verdict$statut, "ok")) {
        if (i > 1L) {
          cli::cli_inform("OSM : instance {.val {serveurs[1]}} indisponible,
                           repli sur {.val {u}}.")
        }
        return(list(corps = rep$content, instance = u,
                    date = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")))
      }
      derniere <- verdict
      # `Retry-After` court : on patiente. Long : on change d'instance plutot que
      # d'attendre -- c'est le comportement d'`osmdata` (60 s en boucle, sans
      # plafond) qu'on refuse de reproduire.
      if (identical(verdict$statut, "quota") && !is.na(verdict$retry) &&
          verdict$retry <= 10) {
        Sys.sleep(verdict$retry)
      } else {
        break
      }
    }
  }
  cli::cli_abort(c(
    "Overpass a refuse la requete sur {length(serveurs)} instance{?s}.",
    "x" = "Derniere cause : {derniere$message}.",
    "i" = "Un refus n'est PAS une absence de donnee : ne pas le lire comme
           une couche vide."
  ))
}

# Appel borne AU NIVEAU DU TRANSPORT. Le `timeout` de libcurl coupe un socket
# bloque dans le C, ce que `setTimeLimit()` ne sait pas faire.
.osm_curl <- function(url, ql, timeout) { # nocov start : acces reseau
  h <- curl::new_handle()
  curl::handle_setopt(h, timeout = timeout, connecttimeout = min(timeout, 20),
                      postfields = ql, useragent = "foretaccess/R (+GPL-3)")
  tryCatch(curl::curl_fetch_memory(url, handle = h),
           error = function(e) list(status_code = -1L, content = raw(0),
                                    headers = raw(0), erreur = conditionMessage(e)))
} # nocov end

# LES TROIS ISSUES DU CONTRAT, decidees ICI et nulle part ailleurs.
.osm_verdict <- function(rep) {
  code <- rep$status_code %||% -1L
  if (!is.null(rep$erreur)) {
    return(list(statut = "reseau", message = rep$erreur, retry = NA_real_))
  }
  if (identical(as.integer(code), 429L) || identical(as.integer(code), 504L)) {
    return(list(statut = "quota", message = paste("HTTP", code),
                retry = .osm_retry_after(rep$headers)))
  }
  if (code < 200 || code >= 300) {
    return(list(statut = "http", message = paste("HTTP", code), retry = NA_real_))
  }
  txt <- rawToChar(rep$content %||% raw(0))
  Encoding(txt) <- "UTF-8"
  if (length(rep$content %||% raw(0)) < .OSM_TAILLE_MIN) {
    return(list(statut = "tronque",
                message = sprintf("corps de %d octets", length(rep$content)),
                retry = NA_real_))
  }
  # Le piege : XML BIEN FORME, HTTP 200, quelques centaines d'octets, et un
  # `<remark>` qui dit le refus. Lu naivement, cela signifie « rien ici ».
  if (grepl("<remark>", txt, fixed = TRUE)) {
    rk <- sub(".*<remark>\\s*(.*?)\\s*</remark>.*", "\\1", txt)
    return(list(statut = "remark", message = paste("remark Overpass :", rk),
                retry = NA_real_))
  }
  list(statut = "ok", message = NA_character_, retry = NA_real_)
}

.osm_retry_after <- function(headers) {
  if (is.null(headers) || !length(headers)) {
    return(NA_real_)
  }
  h <- tryCatch(curl::parse_headers(headers), error = function(e) character(0))
  v <- grep("^retry-after:", tolower(h), value = TRUE)
  if (!length(v)) {
    return(NA_real_)
  }
  suppressWarnings(as.numeric(trimws(sub("^[^:]*:", "", v[1]))))
}

# --- Lecture ----------------------------------------------------------------

# Driver OSM de GDAL. `other_tags` porte les tags que le driver ne promeut pas en
# colonne (selon `OSM_CONFIG_FILE`) : on les deplie explicitement, sinon
# `tracktype`/`surface`/`access` -- documentes en sortie d'`acquire_desserte_osm()`
# -- disparaitraient silencieusement.
.osm_lire <- function(corps, couches) {
  f <- tempfile(fileext = ".osm")
  on.exit(unlink(f), add = TRUE)
  writeBin(corps, f)
  morceaux <- list()
  for (l in couches) {
    d <- tryCatch(sf::st_read(f, layer = l, quiet = TRUE),
                  error = function(e) NULL)
    if (!is.null(d) && nrow(d) > 0) {
      morceaux[[length(morceaux) + 1L]] <- .osm_deplier_tags(d)
    }
  }
  if (!length(morceaux)) {
    return(sf::st_sf(osm_id = character(0), geometry = sf::st_sfc(crs = 4326)))
  }
  cols <- Reduce(union, lapply(morceaux, names))
  morceaux <- lapply(morceaux, function(d) {
    for (n in setdiff(cols, names(d))) d[[n]] <- NA
    d[, cols]
  })
  out <- do.call(rbind, morceaux)
  if ("osm_id" %in% names(out)) out <- out[!duplicated(out$osm_id), ]
  out
}

# `other_tags` de GDAL : "cle"=>"valeur","cle2"=>"valeur2". On en extrait les
# tags utiles quand ils ne sont pas deja des colonnes.
.osm_deplier_tags <- function(d, tags = c("highway", "tracktype", "surface",
                                          "access", "barrier", "natural",
                                          "waterway", "railway")) {
  if (!"other_tags" %in% names(d)) {
    return(d)
  }
  ot <- as.character(d$other_tags)
  ot[is.na(ot)] <- ""
  for (t in tags) {
    # NE PAS sauter une colonne partiellement remplie : le driver peut promouvoir
    # `highway` pour un objet et le laisser dans `other_tags` pour un autre. Un
    # `next` sur « la colonne existe et n'est pas toute vide » laissait alors des
    # NA que `other_tags` savait combler -- trouve par le test, pas a la lecture.
    motif <- paste0("\"", t, "\"=>\"([^\"]*)\"")
    v <- ifelse(grepl(motif, ot), sub(paste0(".*", motif, ".*"), "\\1", ot),
                NA_character_)
    if (t %in% names(d)) {
      d[[t]][is.na(d[[t]])] <- v[is.na(d[[t]])]
    } else if (any(!is.na(v))) {
      d[[t]] <- v
    }
  }
  d
}
