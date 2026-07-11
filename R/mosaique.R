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
                               quiet = FALSE,
                               couches = NULL) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  validate_config(config)
  checkmate::assert_function(moteur)

  # Chaque moteur nomme ses couches ; le tuilage n'en connait aucune. Faute d'indication,
  # on prend celles du skidder, moteur par defaut.
  if (is.null(couches)) couches <- .couches_skidder()

  ge <- config$general
  nr <- terra::nrow(pre$mnt)
  nc <- terra::ncol(pre$mnt)
  n <- nr * nc

  pre <- .precalculer_piste(pre, config)

  plan <- decouper_emprise(pre$mnt, ge$tuile_m, 0)$tuiles
  sortie <- .sortie_vide(n, couches)
  certifie <- rep(FALSE, n)
  acquis <- vector("list", nrow(plan))
  halo <- rep(ge$halo_initial_m, nrow(plan))

  # Boucle par *niveau de halo* : toutes les tuiles d'un meme niveau partent ensemble,
  # et seules celles qui restent non certifiees repartent au niveau suivant. Le halo
  # grandit donc en parallele, sans qu'une tuile difficile bloque les autres.
  actives <- seq_len(nrow(plan))
  while (length(actives)) {
    if (!quiet) {
      cli::cli_alert_info("Halo {halo[actives[1]]} m : {length(actives)} tuile{?s}")
    }
    taches <- lapply(actives, function(i) {
      .fenetre_calcul(plan[i, ], halo[i], terra::res(pre$mnt)[1], nr, nc)
    })
    res <- .appliquer_tuiles(pre, config, moteur, taches, nc, ge$workers, couches)

    fini <- vapply(seq_along(actives), function(k) {
      res[[k]]$non_certifie == 0L || halo[actives[k]] >= ge$halo_max_m
    }, logical(1))

    for (k in which(fini)) acquis[[actives[k]]] <- c(res[[k]], list(halo_m = halo[actives[k]]))
    halo[actives[!fini]] <- pmin(2 * halo[actives[!fini]], ge$halo_max_m)
    actives <- actives[!fini]
  }

  journal <- vector("list", nrow(plan))
  for (i in seq_len(nrow(plan))) {
    r <- acquis[[i]]
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

  .assembler_mosaique(sortie, certifie, pre, config, journal, write_dir, couches)
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

# Repartit les tuiles d'un niveau de halo sur les workers. `workers = 1` execute *sans
# demon*, dans le processus courant : indispensable au debogage, ou un plantage dans un
# demon ne remonte qu'une trace tronquee.
#
# Les `SpatRaster` portent des pointeurs C++ : ils ne franchissent pas la frontiere de
# processus. On recadre donc dans le parent -- une lecture de fenetre, que `terra` fait
# sans charger le raster entier -- puis on emballe (`terra::wrap()`) la seule tuile.
.appliquer_tuiles <- function(pre, config, moteur, taches, nc, workers, couches) {
  if (workers <= 1L) {
    return(lapply(taches, function(t) {
      .executer_tuile(.preparer_tuile(pre, t), config, moteur, t, nc, couches)
    }))
  }
  charges <- lapply(taches, function(t) {
    list(t = t, pre = .emballer_pre(.preparer_tuile(pre, t)))
  })

  mirai::daemons(as.integer(workers))
  on.exit(mirai::daemons(0L), add = TRUE)
  mirai::everywhere(library(foretaccess))

  travaux <- mirai::mirai_map(
    charges,
    function(charge, config, moteur, nc, couches, deballer, executer) {
      executer(deballer(charge$pre), config, moteur, charge$t, nc, couches)
    },
    # `...` de `mirai_map()` sert a *iterer* ; les constantes passent par `.args`. Les
    # fonctions internes y voyagent en valeur, plutot que d'etre rappelees par `:::`.
    .args = list(
      config = config, moteur = moteur, nc = nc, couches = couches,
      deballer = .deballer_pre, executer = .executer_tuile
    )
  )
  .verifier_demons(travaux[])
}

# Une erreur dans un demon revient comme valeur, non comme condition : sans ce controle,
# elle traverserait la boucle de halo en silence et ressortirait en `NA` indechiffrable.
.verifier_demons <- function(res) {
  rate <- vapply(res, function(x) inherits(x, "miraiError"), logical(1))
  if (any(rate)) {
    cli::cli_abort(c(
      "{sum(rate)} tuile{?s} en echec dans un demon {.pkg mirai}.",
      "x" = "{as.character(res[[which(rate)[1]]])}",
      "i" = "Rejouer avec {.code workers = 1} pour obtenir la trace complete."
    ))
  }
  res
}

# La distance sur piste est la propagation la plus longue du moteur : sur donnees reelles
# elle atteint 4 km, ce qui forcerait le halo a 4 km -- et le surcout du halo croit comme
# (1 + 2 halo / tuile)^2. Mais elle vit sur le *reseau*, unidimensionnel et creux : une
# seule propagation globale la donne exactement, pour une fraction du cout d'une tuile.
# Elle cesse alors d'etre un moteur de halo. Le pretraitement la porte, `.recadrer_pre()`
# la decoupe, `skidder()` la reprend telle quelle.
.precalculer_piste <- function(pre, config) {
  if (!is.null(pre$distance_piste)) {
    return(pre)
  }
  cout <- surface_cout_skidder(pre, config)
  d <- .distance_sur_piste(pre, cout)$distance

  r <- terra::rast(pre$mnt)
  terra::values(r) <- d
  names(r) <- "distance_piste"
  pre$distance_piste <- r
  pre
}

# Recadre le pretraitement sur la fenetre de calcul d'une tuile.
.preparer_tuile <- function(pre, t) {
  fen <- .ext_cellules(pre$mnt, t$hl1, t$hl2, t$hc1, t$hc2)
  .recadrer_pre(pre, fen, t$halo_cel)
}

.emballer_pre <- function(pre_t) {
  for (nm in names(pre_t)) {
    if (inherits(pre_t[[nm]], "SpatRaster")) pre_t[[nm]] <- terra::wrap(pre_t[[nm]])
  }
  pre_t
}

.deballer_pre <- function(pre_t) {
  for (nm in names(pre_t)) {
    if (inherits(pre_t[[nm]], "PackedSpatRaster")) pre_t[[nm]] <- terra::unwrap(pre_t[[nm]])
  }
  pre_t
}

# Calcul d'une tuile sur sa fenetre elargie, puis extraction de la fenetre d'ecriture.
.executer_tuile <- function(pre_t, config, moteur, t, nc, couches) {
  ncw <- t$hc2 - t$hc1 + 1L
  cel_t <- .cellules_fenetre(t, ncw)

  if (!.tuile_calculable(pre_t)) {
    return(.tuile_indeterminee(cel_t, t, couches))
  }

  sk <- moteur(pre_t, config, bord = .cotes_ouverts(t))
  valeurs <- lapply(couches, function(nm) {
    as.numeric(terra::values(sk[[nm]]))[cel_t]
  })
  names(valeurs) <- couches

  cert <- as.logical(terra::values(sk$certifie))[cel_t]
  valeurs$allocation <- .allocation_globale(valeurs$allocation, t, ncw, nc)

  list(valeurs = valeurs, certifie = cert, ligne = t, non_certifie = sum(!cert))
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

.tuile_indeterminee <- function(cel_t, t, couches) {
  n <- length(cel_t)
  valeurs <- structure(lapply(couches, function(x) rep(NA_real_, n)), names = couches)
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

.sortie_vide <- function(n, couches) {
  structure(lapply(couches, function(x) rep(NA_real_, n)), names = couches)
}

.poser_tuile <- function(sortie, r, glo) {
  for (nm in names(sortie)) sortie[[nm]][glo] <- r$valeurs[[nm]]
  sortie
}

.assembler_mosaique <- function(sortie, certifie, pre, config, journal, write_dir, couches) {
  # Une cellule non certifiee ne publie aucun chiffre : ni classe, ni distance, ni
  # allocation. Un resultat plausible mais faux est pire qu'un `NA` declare.
  for (nm in names(sortie)) sortie[[nm]][!certifie] <- NA_real_

  faire <- function(v, nom) {
    r <- terra::rast(pre$mnt)
    terra::values(r) <- v
    names(r) <- nom
    r
  }

  # Les couches du moteur, recomposees generiquement -- le nom de chacune vient du moteur.
  rasters <- stats::setNames(lapply(couches, function(nm) faire(sortie[[nm]], nm)), couches)
  acc <- rasters$accessibilite
  levels(acc) <- data.frame(
    value = 1:4,
    classe = c("parcourable", "accessible", "non_accessible", "hors_foret")
  )
  rasters$accessibilite <- acc
  recap <- recapituler(acc, pre$volume)

  mo <- structure(
    c(rasters, list(
      certifie       = faire(as.numeric(certifie), "certifie"),
      recap          = recap,
      tuiles         = journal,
      indetermine_ha = .surface_indetermine(recap),
      couches        = couches,
      grid           = pre$grid,
      config         = config,
      fichiers       = NULL
    )),
    class = "foretaccess_mosaique"
  )

  if (!is.null(write_dir)) mo$fichiers <- .ecrire_rasters_couches(mo, mo$couches, write_dir)
  mo
}

# Ecrit les couches nommees d'un objet en COG. Generique : sert au tuilage, quel que soit
# le moteur.
.ecrire_rasters_couches <- function(x, couches, write_dir) {
  checkmate::assert_string(write_dir)
  dir.create(write_dir, recursive = TRUE, showWarnings = FALSE)
  chemins <- vapply(couches, function(nm) {
    f <- file.path(write_dir, paste0(nm, ".tif"))
    terra::writeRaster(x[[nm]], f, filetype = "COG", overwrite = TRUE)
    f
  }, character(1))
  as.list(chemins)
}

# `recapituler()` emet toujours une ligne `indetermine`, meme vide : pas de cas absent.
.surface_indetermine <- function(recap) {
  recap$surface_ha[recap$classe == "indetermine"]
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
