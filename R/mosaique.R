#' Traiter une emprise par tuiles
#'
#' Découpe l'emprise, applique un moteur à chaque tuile sur une fenêtre élargie d'un
#' halo, **certifie** le résultat cellule par cellule (spec 007 §4.3) et recompose une
#' mosaïque. Le résultat est **identique** à celui du moteur appliqué d'un seul bloc,
#' partout où il est certifié.
#'
#' @details
#' Le halo **double** tant que des cellules de la tuile restent non certifiées, jusqu'à
#' `halo_max_m`. Au-delà, ces cellules sortent en `indetermine` — la classe que
#' [recapituler()] produit déjà pour les bordures de pente — et un avertissement le dit.
#' Elles ne sont **jamais** rangées dans `non_accessible` : le doute se déclare.
#'
#' `pre` doit couvrir toute l'emprise. Ses rasters peuvent être **adossés à des
#' fichiers** (`preprocess(write_dir = …)`) : `terra` n'en charge alors que la fenêtre
#' de chaque tuile, ce qui rend le traitement possible là où le mono-bloc ne tiendrait
#' pas en mémoire — le véritable obstacle du passage à l'échelle, avant le temps de calcul.
#'
#' L'`allocation` porte un indice de cellule dans la grille **globale**, jamais celle de
#' la tuile : sans cette remise à l'échelle, deux tuiles alloueraient le même identifiant
#' à deux dessertes différentes.
#'
#' @param pre Objet `foretaccess_preprocessing` couvrant toute l'emprise.
#' @param config Objet [foretaccess_config()]. Les paramètres de tuilage vivent dans
#'   `config$general` : `tuile_m`, `halo_initial_m`, `halo_max_m`.
#' @param moteur Fonction moteur, de signature `(pre, config, bord)`. Défaut [skidder()].
#' @param write_dir Répertoire d'écriture des COG recomposés, ou `NULL`.
#' @param quiet Supprime la progression.
#'
#' @return Un objet de classe `foretaccess_mosaique` :
#'   \describe{
#'     \item{`accessibilite`, `distance_*`, `allocation`}{les couches du moteur,
#'       recomposées sur toute l'emprise.}
#'     \item{`certifie`}{`SpatRaster` logique. Gardé en mémoire, **pas écrit** : les
#'       cellules non certifiées se lisent déjà comme `NA` dans les couches.}
#'     \item{`recap`}{`data.frame` agrégé, `indetermine` compris.}
#'     \item{`tuiles`}{`data.frame` : halo final et cellules non certifiées, par tuile.}
#'     \item{`indetermine_ha`}{surface non certifiée, toujours reportée.}
#'     \item{`grid`, `config`, `fichiers`}{comme au Lot 1.}
#'   }
#' @seealso [decouper_emprise()], [certifier_propagation()], [skidder()]
#' @export
#' @examples
#' toy <- system.file("extdata/toy", package = "foretaccess")
#' pre <- preprocess(file.path(toy, "mnt.tif"), file.path(toy, "desserte.gpkg"),
#'                   file.path(toy, "foret.gpkg"))
#' cfg <- foretaccess_config(general = list(tuile_m = 150, halo_initial_m = 50))
#' mo <- traiter_par_tuiles(pre, cfg, quiet = TRUE)
#' mo$recap
traiter_par_tuiles <- function(pre,
                               config = foretaccess_config(),
                               moteur = skidder,
                               write_dir = NULL,
                               quiet = FALSE) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  validate_config(config)
  checkmate::assert_function(moteur)

  ge <- config$general
  nr <- terra::nrow(pre$mnt)
  nc <- terra::ncol(pre$mnt)
  n <- nr * nc

  plan <- decouper_emprise(pre$mnt, ge$tuile_m, 0)$tuiles
  sortie <- .sortie_vide(n)
  certifie <- rep(FALSE, n)
  journal <- vector("list", nrow(plan))

  for (i in seq_len(nrow(plan))) {
    if (!quiet) cli::cli_alert_info("Tuile {i}/{nrow(plan)}")
    r <- .traiter_tuile(pre, config, moteur, plan[i, ], nr, nc)
    glo <- .cellules_globales(r$ligne, nc)
    sortie <- .poser_tuile(sortie, r, glo)
    certifie[glo] <- r$certifie
    journal[[i]] <- data.frame(id = plan$id[i], halo_m = r$halo_m, non_certifie = r$non_certifie)
  }

  journal <- do.call(rbind, journal)
  restant <- sum(journal$non_certifie)
  if (restant > 0) {
    cli::cli_warn(c(
      "{restant} cellule{?s} non certifiee{?s} apres elargissement du halo.",
      "i" = "Classees {.val indetermine}, jamais {.val non_accessible}.",
      "i" = "Augmenter {.field halo_max_m} (actuellement {ge$halo_max_m} m) pour les resoudre."
    ))
  }

  .assembler_mosaique(sortie, certifie, pre, config, journal, write_dir)
}

# Fenetre de calcul d'une tuile pour un halo donne, et ses cotes ouverts. Le halo est
# rabote sur l'emprise : un cote qui y bute est *ferme*, rien n'existant au-dela.
.fenetre_calcul <- function(ligne, halo_m, res, nr, nc) {
  h <- as.integer(ceiling(halo_m / res))

  t <- ligne
  t$hl1 <- max(1L, t$l1 - h)
  t$hl2 <- min(nr, t$l2 + h)
  t$hc1 <- max(1L, t$c1 - h)
  t$hc2 <- min(nc, t$c2 + h)
  t$ouvert_haut <- t$hl1 > 1L
  t$ouvert_bas <- t$hl2 < nr
  t$ouvert_gauche <- t$hc1 > 1L
  t$ouvert_droite <- t$hc2 < nc
  t$halo_cel <- h
  t
}

# Traite une tuile, en doublant le halo tant que des cellules restent non certifiees.
# Chaque doublement quadruple la surface du halo : la convergence est rapide, et le
# plafond `halo_max_m` borne le pire cas.
.traiter_tuile <- function(pre, config, moteur, ligne, nr, nc) {
  ge <- config$general
  res <- terra::res(pre$mnt)[1]
  halo <- ge$halo_initial_m

  repeat {
    t <- .fenetre_calcul(ligne, halo, res, nr, nc)
    out <- .calculer_tuile(pre, config, moteur, t, nc)

    if (out$non_certifie == 0L || halo >= ge$halo_max_m) break
    halo <- min(2 * halo, ge$halo_max_m)
  }
  c(out, list(halo_m = halo))
}

# Calcul d'une tuile sur sa fenetre elargie, puis extraction de la fenetre d'ecriture.
.calculer_tuile <- function(pre, config, moteur, t, nc) {
  fen <- .ext_cellules(pre$mnt, t$hl1, t$hl2, t$hc1, t$hc2)
  pre_t <- .recadrer_pre(pre, fen, t$halo_cel)

  ncw <- t$hc2 - t$hc1 + 1L
  cel_t <- .cellules_fenetre(t, ncw)

  if (!.tuile_calculable(pre_t)) {
    return(.tuile_indeterminee(cel_t, t))
  }

  sk <- moteur(pre_t, config, bord = .cotes_ouverts(t))
  couches <- lapply(.couches_skidder(), function(nm) {
    as.numeric(terra::values(sk[[nm]]))[cel_t]
  })
  names(couches) <- .couches_skidder()

  cert <- as.logical(terra::values(sk$certifie))[cel_t]
  couches$allocation <- .allocation_globale(couches$allocation, t, ncw, nc)

  list(valeurs = couches, certifie = cert, ligne = t, non_certifie = sum(!cert))
}

# Une tuile sans desserte dans sa fenetre de calcul n'est pas calculable : le moteur
# n'aurait aucun point de depart. Elle n'est pas pour autant inaccessible -- une desserte
# hors fenetre peut la desservir, et le trainage y entrer. On ne calcule rien, on ne
# certifie rien, et le halo grandit.
#
# Meme les cellules hors foret y restent indeterminees : leur *classe* serait certaine,
# mais leurs distances ne le sont pas -- la zone de trainage deborde de 50 m hors foret
# (spec 002 §4.5.1), et le mono-bloc leur attribue une distance non nulle.
.tuile_calculable <- function(pre_t) {
  any(!is.na(terra::values(pre_t$desserte)))
}

.tuile_indeterminee <- function(cel_t, t) {
  n <- length(cel_t)
  nms <- .couches_skidder()
  valeurs <- structure(lapply(nms, function(x) rep(NA_real_, n)), names = nms)
  list(valeurs = valeurs, certifie = rep(FALSE, n), ligne = t, non_certifie = n)
}

# Emprise geographique d'un rectangle de cellules.
.ext_cellules <- function(gabarit, l1, l2, c1, c2) {
  e <- as.vector(terra::ext(gabarit))
  r <- terra::res(gabarit)[1]
  terra::ext(
    e[["xmin"]] + (c1 - 1L) * r, e[["xmin"]] + c2 * r,
    e[["ymax"]] - l2 * r, e[["ymax"]] - (l1 - 1L) * r
  )
}

# Indices, dans la fenetre de calcul, des cellules de la fenetre d'ecriture.
.cellules_fenetre <- function(t, ncw) {
  lr <- (t$l1:t$l2) - t$hl1 + 1L
  cr <- (t$c1:t$c2) - t$hc1 + 1L
  as.vector(outer(lr, cr, function(a, b) (a - 1L) * ncw + b))
}

# Indices globaux correspondants.
.cellules_globales <- function(t, nc) {
  as.vector(outer(t$l1:t$l2, t$c1:t$c2, function(a, b) (a - 1L) * nc + b))
}

# L'allocation designe une cellule de desserte : son indice doit vivre dans la grille
# globale, sans quoi deux tuiles alloueraient le meme identifiant a deux dessertes.
.allocation_globale <- function(a, t, ncw, nc) {
  ok <- !is.na(a)
  al <- ((a[ok] - 1) %/% ncw) + 1
  ac <- ((a[ok] - 1) %% ncw) + 1
  a[ok] <- (al + t$hl1 - 2) * nc + (ac + t$hc1 - 1)
  a
}

# Recadre l'objet de pretraitement sur une fenetre, en memorisant la largeur du halo :
# le moteur en a besoin pour savoir si la portee du treuil est couverte.
.recadrer_pre <- function(pre, fen, halo_cel) {
  out <- pre
  for (nm in names(pre)) {
    if (inherits(pre[[nm]], "SpatRaster")) out[[nm]] <- terra::crop(pre[[nm]], fen)
  }
  out$grid <- .grille(out$mnt)
  out$halo_cel <- halo_cel
  out$fichiers <- NULL
  out
}

.sortie_vide <- function(n) {
  nms <- .couches_skidder()
  structure(lapply(nms, function(x) rep(NA_real_, n)), names = nms)
}

.poser_tuile <- function(sortie, r, glo) {
  for (nm in names(sortie)) sortie[[nm]][glo] <- r$valeurs[[nm]]
  sortie
}

.assembler_mosaique <- function(sortie, certifie, pre, config, journal, write_dir) {
  # Une cellule non certifiee ne publie aucun chiffre : ni classe, ni distance, ni
  # allocation. Un resultat plausible mais faux est pire qu'un `NA` declare.
  for (nm in names(sortie)) sortie[[nm]][!certifie] <- NA_real_

  faire <- function(v, nom) {
    r <- terra::rast(pre$mnt)
    terra::values(r) <- v
    names(r) <- nom
    r
  }

  acc <- faire(sortie$accessibilite, "accessibilite")
  levels(acc) <- data.frame(
    value = 1:4,
    classe = c("parcourable", "accessible", "non_accessible", "hors_foret")
  )
  recap <- recapituler(acc, pre$volume)

  mo <- structure(
    list(
      accessibilite           = acc,
      distance_treuillage     = faire(sortie$distance_treuillage, "distance_treuillage"),
      distance_trainage_foret = faire(sortie$distance_trainage_foret, "distance_trainage_foret"),
      distance_trainage_piste = faire(sortie$distance_trainage_piste, "distance_trainage_piste"),
      distance_debardage      = faire(sortie$distance_debardage, "distance_debardage"),
      allocation              = faire(sortie$allocation, "allocation"),
      certifie                = faire(as.numeric(certifie), "certifie"),
      recap                   = recap,
      tuiles                  = journal,
      indetermine_ha          = .surface_indetermine(recap),
      grid                    = pre$grid,
      config                  = config,
      fichiers                = NULL
    ),
    class = "foretaccess_mosaique"
  )

  if (!is.null(write_dir)) mo$fichiers <- .ecrire_rasters_skidder(mo, write_dir)
  mo
}

.surface_indetermine <- function(recap) {
  s <- recap$surface_ha[recap$classe == "indetermine"]
  if (!length(s)) 0 else s
}

#' @export
print.foretaccess_mosaique <- function(x, ...) {
  cli::cli_inform(c(
    "Mosaique ForetAccess",
    "*" = "grille : {x$grid$nrow} x {x$grid$ncol} cellules, {nrow(x$tuiles)} tuile{?s}",
    "*" = "halo final : {max(x$tuiles$halo_m)} m au plus",
    "*" = "indetermine : {signif(x$indetermine_ha, 4)} ha"
  ))
  invisible(x)
}
