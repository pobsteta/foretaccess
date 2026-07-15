#' Certificat d'exactitude d'une propagation sur une fenêtre
#'
#' Propage un coût sur une fenêtre de calcul, et **prouve**, cellule par cellule, que
#' le résultat est celui qu'aurait donné la même propagation sur le territoire entier.
#' Sans cela, un plus court chemin — qui n'a **aucune portée bornée** — produit des
#' artefacts de bordure indiscernables d'un résultat correct (spec 007 §4.2).
#'
#' @details
#' Soit `R` la fenêtre de calcul, `d_R` le coût cumulé depuis les sources présentes
#' dans `R`, et `d_∂` le coût cumulé depuis le **bord ouvert** de `R`, pris à coût nul.
#'
#' **Certificat.** Si `d_R(v) ≤ d_∂(v)`, alors `d_R(v)` est le coût global.
#'
#' *Preuve.* Soit `P` un chemin global optimal aboutissant en `v`. Si `P` reste dans
#' `R`, sa source y est aussi, donc `d_R(v) ≤ coût(P)`. Sinon `P` entre dans `R` par
#' une cellule `b` du bord ouvert ; le suffixe de `P` depuis `b` reste dans `R` et
#' coûte au plus `coût(P)`. Comme `d_∂` part de `b` à coût nul et que les coûts sont
#' positifs, `d_∂(v) ≤ coût(P)`. Sous l'hypothèse, `d_R(v) ≤ d_∂(v) ≤ coût(P)`, qui est
#' le coût global. Or `d_R(v) ≥` ce coût, puisque `R` offre moins de chemins. Égalité. ∎
#'
#' Trois conséquences :
#' * **Allocation.** Si l'inégalité est **stricte**, aucun chemin extérieur n'atteint le
#'   coût optimal : la source allouée est exacte elle aussi. À égalité, la distance est
#'   exacte mais l'allocation peut différer.
#' * **Inaccessibilité.** `d_R(v) = ∞` et `d_∂(v) = ∞` vérifient `∞ ≤ ∞` : la cellule est
#'   certifiée **inaccessible**, rien ne pouvant entrer jusqu'à elle.
#' * **Connexité.** Le cas `coût ≡ 0` certifie l'appartenance à une composante connexe.
#'
#' Le bord **fermé** (un côté qui coïncide avec le bord de l'emprise) n'est pas une
#' entrée : rien n'existe au-delà. L'ignorer rendrait le certificat inutilement
#' pessimiste sur les tuiles de bordure.
#'
#' `cout_max` s'applique aux **deux** propagations. C'est ce qui rend le certificat
#' correct pour un coût plafonné : une cellule que le bord n'atteint pas sous le plafond
#' ne peut pas non plus être atteinte de l'extérieur sous ce plafond.
#'
#' @inheritParams propager_cout
#' @param zone_majorante `SpatRaster` logique **contenant** la zone traversable globale,
#'   restreinte à la fenêtre. Défaut : `zone`, correct quand `zone` est purement locale.
#'   Quand `zone` dépend d'une connexité globale (donc sous-estimée sur la fenêtre),
#'   passer ici une sur-approximation locale, sans quoi `d_∂` ne minorerait plus rien.
#' @param bord Cellules d'entrée : un vecteur de côtés ouverts parmi `"haut"`, `"bas"`,
#'   `"gauche"`, `"droite"` ; un `SpatRaster` logique ; ou `NULL` (défaut) pour les
#'   quatre côtés. `character(0)` : aucune entrée, tout est certifié.
#'
#' @return Un objet de classe `foretaccess_certificat` :
#'   \describe{
#'     \item{`propagation`}{l'objet `foretaccess_propagation` de [propager_cout()].}
#'     \item{`certifie`}{`SpatRaster` logique : le coût cumulé y est exact.}
#'     \item{`certifie_allocation`}{`SpatRaster` logique : l'allocation y est exacte.}
#'     \item{`n_non_certifie`}{nombre de cellules non certifiées.}
#'   }
#' @seealso [propager_cout()], [decouper_emprise()]
#' @export
#' @examples
#' cout <- terra::rast(nrows = 5, ncols = 5, xmin = 0, xmax = 5,
#'                     ymin = 0, ymax = 5, crs = "EPSG:2154")
#' terra::values(cout) <- 1
#' src <- terra::rast(cout)
#' src[1, 1] <- 1
#' # Aucune entree possible : la fenetre est le territoire entier.
#' cert <- certifier_propagation(cout, src, bord = character(0))
#' cert$n_non_certifie
certifier_propagation <- function(surface_cout,
                                  sources,
                                  zone = NULL,
                                  zone_majorante = zone,
                                  bord = NULL,
                                  cout_max = Inf) {
  surface_cout <- .as_raster(surface_cout, "surface_cout")
  prop <- propager_cout(surface_cout, sources, zone = zone, cout_max = cout_max)
  .certifier_depuis(surface_cout, prop, zone_majorante, bord, cout_max)
}

# Certifie une propagation DEJA CALCULEE, en la confrontant a ce qu'un chemin venu du
# dehors pourrait atteindre. Separee de `certifier_propagation()` pour que le skidder
# puisse certifier sa propagation a veto (`.propager_trainage()`), qui n'est pas un
# Dijkstra et ne passe donc pas par `propager_cout()`.
#
# Le certificat reste correct pour elle : sa distance est SUPERIEURE OU EGALE au
# minimum forestier pur (le veto ne fait que bloquer des ameliorations), tandis que
# `d_bord` reste ce minimum. Comparer les deux ne peut donc que certifier MOINS de
# cellules qu'il n'est permis -- jamais plus. Le doute penche du bon cote.
.certifier_depuis <- function(surface_cout, prop, zone_majorante, bord,
                              cout_max = Inf, strict = FALSE) {
  entrees <- .entrees(surface_cout, bord, zone_majorante)
  d_r <- .cout_ou_infini(prop$cout_cumule)

  if (is.null(entrees)) {
    # Aucune entree : la fenetre est fermee, tout chemin global y est deja contenu.
    d_b <- rep(Inf, length(d_r))
  } else {
    prop_b <- propager_cout(surface_cout, entrees, zone = zone_majorante, cout_max = cout_max)
    d_b <- .cout_ou_infini(prop_b$cout_cumule)
  }

  # `strict` : ne certifier qu'en INEGALITE STRICTE. Le theoreme du halo certifie a
  # l'egalite `d_R = d_b` -- la distance y reste exacte -- mais cela suppose une
  # semantique de plus court chemin. La propagation a VETO (`.propager_trainage()`)
  # n'en est pas une : a egalite, un chemin venu du dehors peut atteindre le meme cout
  # forestier PUIS renverser le choix de semence du veto (payload `d_piste` different).
  # L'inegalite stricte l'exclut -- aucun chemin externe n'egale meme le cout interne,
  # donc le chemin gagnant est entierement dans la fenetre, semence et payload compris.
  certifie <- if (strict) {
    (d_r < d_b) | (is.infinite(d_r) & is.infinite(d_b))
  } else {
    d_r <= d_b
  }
  # A egalite, un chemin exterieur peut atteindre le meme cout par une autre source :
  # la distance reste exacte, l'allocation non. Une cellule inaccessible des deux cotes
  # n'a pas d'allocation : la sienne, `NA`, est exacte.
  certifie_alloc <- (d_r < d_b) | (is.infinite(d_r) & is.infinite(d_b))

  faire <- function(v, nom) {
    r <- terra::rast(surface_cout)
    terra::values(r) <- as.numeric(v)
    names(r) <- nom
    r
  }

  structure(
    list(
      propagation = prop,
      certifie = faire(certifie, "certifie"),
      certifie_allocation = faire(certifie_alloc, "certifie_allocation"),
      n_non_certifie = sum(!certifie)
    ),
    class = "foretaccess_certificat"
  )
}

# Cout cumule, les cellules non atteintes valant `Inf` plutot que `NA` : le certificat
# est une comparaison, et `Inf <= Inf` y a le sens voulu, la ou `NA` contaminerait tout.
.cout_ou_infini <- function(r) {
  v <- as.numeric(terra::values(r))
  v[is.na(v)] <- Inf
  v
}

# Cellules par lesquelles un chemin venu de l'exterieur peut entrer : l'anneau des cotes
# ouverts, prive des cellules infranchissables — aucun chemin ne passe par elles, et les
# retenir declarerait non certifiees des cellules qui le sont. `NULL` si aucune entree.
.entrees <- function(gabarit, bord, zone_majorante) {
  m <- as.logical(terra::values(.masque_bord(gabarit, bord)))
  m[is.na(m)] <- FALSE

  m <- m & !is.na(terra::values(gabarit))
  if (!is.null(zone_majorante)) {
    zv <- as.numeric(terra::values(zone_majorante))
    m <- m & !is.na(zv) & zv != 0
  }
  if (!any(m)) {
    return(NULL)
  }

  r <- terra::rast(gabarit)
  v <- rep(NA_real_, terra::ncell(r))
  v[m] <- 1
  terra::values(r) <- v
  r
}

# Anneau exterieur de la fenetre, restreint aux cotes ouverts. Tout chemin venu de
# l'exterieur le traverse, en 8-connexite comme en 4.
.masque_bord <- function(gabarit, bord) {
  if (inherits(bord, "SpatRaster")) {
    .valider_grille(bord, gabarit, "bord")
    return(bord)
  }
  cotes <- if (is.null(bord)) c("haut", "bas", "gauche", "droite") else bord
  checkmate::assert_subset(cotes, c("haut", "bas", "gauche", "droite"))

  nr <- terra::nrow(gabarit)
  nc <- terra::ncol(gabarit)
  m <- matrix(FALSE, nr, nc)
  if ("haut" %in% cotes) m[1L, ] <- TRUE
  if ("bas" %in% cotes) m[nr, ] <- TRUE
  if ("gauche" %in% cotes) m[, 1L] <- TRUE
  if ("droite" %in% cotes) m[, nc] <- TRUE

  r <- terra::rast(gabarit)
  v <- as.numeric(t(m))
  v[v == 0] <- NA_real_
  terra::values(r) <- v
  r
}

#' @export
print.foretaccess_certificat <- function(x, ...) {
  n <- terra::ncell(x$certifie)
  cli::cli_inform(c(
    "Certificat ForetAccess",
    "*" = "{n - x$n_non_certifie}/{n} cellule{?s} certifiee{?s} ({signif(100 * (1 - x$n_non_certifie / n), 4)} %)",
    "*" = "allocation certifiee : {sum(terra::values(x$certifie_allocation) == 1)}/{n}"
  ))
  invisible(x)
}
