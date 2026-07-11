#' Découper une emprise en tuiles avec halo
#'
#' Découpe la grille d'un raster gabarit en **fenêtres d'écriture disjointes** (les
#' tuiles), chacune assortie d'une **fenêtre de calcul** élargie d'un halo. Le halo
#' n'est pas un chevauchement à fusionner : il ne sert qu'au calcul, et n'est jamais
#' écrit. La recomposition est donc une mosaïque, sans règle de fusion (spec 007 §4.5).
#'
#' @details
#' Le découpage travaille en **indices de lignes et de colonnes**, jamais en
#' coordonnées : deux tuiles adjacentes partagent une frontière exacte, sans risque
#' d'arrondi sur les emprises.
#'
#' Chaque tuile porte les **côtés ouverts** de sa fenêtre de calcul : ceux par lesquels
#' un chemin venu du reste du territoire peut entrer. Un côté qui coïncide avec le bord
#' de l'emprise est **fermé** — rien n'existe au-delà. Cette distinction évite au
#' certificat (spec 007 §4.3) d'être inutilement pessimiste sur les tuiles de bordure.
#'
#' @param gabarit `SpatRaster` (ou chemin) dont la grille sert de référence.
#' @param tuile_m Côté d'une tuile, en unités du CRS. Arrondi au nombre entier de
#'   cellules supérieur.
#' @param halo_m Largeur du halo, en unités du CRS. Défaut `0`.
#'
#' @return Un objet de classe `foretaccess_tuiles` :
#'   \describe{
#'     \item{`tuiles`}{`data.frame`, une ligne par tuile : `id`, les lignes/colonnes
#'       de la fenêtre d'écriture (`l1`, `l2`, `c1`, `c2`), celles de la fenêtre de
#'       calcul (`hl1`, `hl2`, `hc1`, `hc2`), et les côtés ouverts
#'       (`ouvert_haut`, `ouvert_bas`, `ouvert_gauche`, `ouvert_droite`).}
#'     \item{`nrow`, `ncol`, `res`}{la grille du gabarit.}
#'     \item{`tuile_cel`, `halo_cel`}{tuile et halo, en cellules.}
#'   }
#' @seealso [fenetre_tuile()], [certifier_propagation()]
#' @export
#' @examples
#' r <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 100,
#'                  ymin = 0, ymax = 100, crs = "EPSG:2154")
#' decouper_emprise(r, tuile_m = 50, halo_m = 10)
decouper_emprise <- function(gabarit, tuile_m, halo_m = 0) {
  gabarit <- .as_raster(gabarit, "gabarit")
  checkmate::assert_number(tuile_m, lower = 0)
  checkmate::assert_number(halo_m, lower = 0)

  res <- terra::res(gabarit)
  if (!isTRUE(all.equal(res[1], res[2]))) {
    cli::cli_abort(c(
      "{.arg gabarit} doit avoir des cellules carrees.",
      "x" = "Resolution : {paste(res, collapse = ' x ')}."
    ))
  }
  res <- res[1]

  nr <- terra::nrow(gabarit)
  nc <- terra::ncol(gabarit)
  tuile_cel <- max(1L, as.integer(ceiling(tuile_m / res)))
  halo_cel <- as.integer(ceiling(halo_m / res))

  l1 <- seq(1L, nr, by = tuile_cel)
  c1 <- seq(1L, nc, by = tuile_cel)
  g <- expand.grid(c1 = c1, l1 = l1)

  t <- data.frame(
    id = seq_len(nrow(g)),
    l1 = g$l1, l2 = pmin(g$l1 + tuile_cel - 1L, nr),
    c1 = g$c1, c2 = pmin(g$c1 + tuile_cel - 1L, nc)
  )

  t$hl1 <- pmax(1L, t$l1 - halo_cel)
  t$hl2 <- pmin(nr, t$l2 + halo_cel)
  t$hc1 <- pmax(1L, t$c1 - halo_cel)
  t$hc2 <- pmin(nc, t$c2 + halo_cel)

  # Un cote est *ouvert* si la fenetre de calcul ne bute pas sur le bord de l'emprise :
  # un chemin venu d'ailleurs peut y entrer. Sinon rien n'existe au-dela.
  t$ouvert_haut <- t$hl1 > 1L
  t$ouvert_bas <- t$hl2 < nr
  t$ouvert_gauche <- t$hc1 > 1L
  t$ouvert_droite <- t$hc2 < nc

  structure(
    list(
      tuiles = t, nrow = nr, ncol = nc, res = res,
      tuile_cel = tuile_cel, halo_cel = halo_cel,
      ext = as.vector(terra::ext(gabarit)), crs = terra::crs(gabarit)
    ),
    class = "foretaccess_tuiles"
  )
}

#' Emprise d'une tuile
#'
#' @param tuiles Objet `foretaccess_tuiles` issu de [decouper_emprise()].
#' @param id Identifiant de la tuile.
#' @param quoi `"halo"` (fenêtre de calcul, défaut) ou `"tuile"` (fenêtre d'écriture).
#'
#' @return Un `SpatExtent`.
#' @export
#' @examples
#' r <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 100,
#'                  ymin = 0, ymax = 100, crs = "EPSG:2154")
#' tu <- decouper_emprise(r, tuile_m = 50, halo_m = 10)
#' fenetre_tuile(tu, 1)
fenetre_tuile <- function(tuiles, id, quoi = c("halo", "tuile")) {
  checkmate::assert_class(tuiles, "foretaccess_tuiles")
  quoi <- match.arg(quoi)

  t <- tuiles$tuiles[tuiles$tuiles$id == id, ]
  if (!nrow(t)) cli::cli_abort("Tuile {id} inconnue.")

  prefixe <- if (quoi == "halo") "h" else ""
  l1 <- t[[paste0(prefixe, "l1")]]
  l2 <- t[[paste0(prefixe, "l2")]]
  c1 <- t[[paste0(prefixe, "c1")]]
  c2 <- t[[paste0(prefixe, "c2")]]

  e <- tuiles$ext
  r <- tuiles$res
  terra::ext(
    e[["xmin"]] + (c1 - 1L) * r, e[["xmin"]] + c2 * r,
    e[["ymax"]] - l2 * r, e[["ymax"]] - (l1 - 1L) * r
  )
}

# Cotes ouverts d'une tuile, sous forme de vecteur de caracteres, tel que
# `certifier_propagation()` l'attend.
.cotes_ouverts <- function(t) {
  c("haut", "bas", "gauche", "droite")[c(
    t$ouvert_haut, t$ouvert_bas, t$ouvert_gauche, t$ouvert_droite
  )]
}

#' @export
print.foretaccess_tuiles <- function(x, ...) {
  n <- nrow(x$tuiles)
  cli::cli_inform(c(
    "Decoupage ForetAccess",
    "*" = "grille : {x$nrow} x {x$ncol} cellules a {x$res} m",
    "*" = "{n} tuile{?s} de {x$tuile_cel} cellules, halo de {x$halo_cel} cellule{?s}",
    "*" = "surcout surfacique moyen : {signif(.surcout_halo(x), 3)}x"
  ))
  invisible(x)
}

# Rapport entre la surface calculee (fenetres de calcul) et la surface ecrite
# (fenetres d'ecriture). Vaut 1 sans halo ; croit vite quand le halo domine la tuile.
.surcout_halo <- function(x) {
  t <- x$tuiles
  calc <- sum((t$hl2 - t$hl1 + 1) * (t$hc2 - t$hc1 + 1))
  ecrit <- sum((t$l2 - t$l1 + 1) * (t$c2 - t$c1 + 1))
  calc / ecrit
}
