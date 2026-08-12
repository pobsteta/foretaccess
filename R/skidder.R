#' Moteur d'accessibilité skidder (débusqueur)
#'
#' Applique les règles Sylvaccess v3.6 au jeu de rasters produit par
#' [preprocess()] : circulation libre sous le seuil de pente, treuillage
#' au-delà, et distances de débardage. Aucune I/O : le moteur consomme l'objet du
#' Lot 1 (ADR-004) et tous ses seuils viennent de `config` (ADR-003).
#'
#' @details
#' Deux mécanismes coexistent, et ils n'ont pas la même nature :
#' * le **traînage** est un plus court chemin sur la surface de coût
#'   ([propager_cout()], [surface_cout_skidder()]) ;
#' * le **treuillage** est un balayage radial en ligne droite ([treuiller()]).
#'
#' L'option de modélisation `1` (défaut v3.6, « limiter l'impact sur le sol »)
#' **privilégie le treuillage** : une cellule treuillable l'est, même si l'engin
#' pourrait y rouler. L'option `2` n'est pas implémentée.
#'
#' Le treuillage se fait en **trois passes**, comme dans Sylvaccess :
#' depuis les routes, depuis les pistes, puis — c'est le point qu'on oublie —
#' depuis le **contour de la zone où l'engin a roulé** (`skid_debusq_contour`).
#' La machine entre en forêt, s'arrête au bord du terrain roulable, et treuille
#' de là en **emportant la distance déjà parcourue** : le critère de choix porte
#' alors sur le **total** traînage + câble, non sur la seule longueur de câble.
#' Cette troisième passe est purement additive — elle ne corrige jamais une
#' cellule que les deux premières ont atteinte.
#'
#' @section Écarts assumés avec Sylvaccess v3.6:
#' La hiérarchie route / piste est réduite à deux niveaux (`route` et `dfci`
#' comptent comme routes), et l'option de modélisation 2 n'est pas implémentée.
#' Voir `specs/002-skidder.md`.
#'
#' @param pre Objet `foretaccess_preprocessing` issu de [preprocess()].
#' @param config Objet [foretaccess_config()].
#' @param trajets_depuis Cellules (indices ou points `sf`) pour lesquelles
#'   reconstruire le trajet de traînage vers la desserte. `NULL` (défaut) : aucun.
#' @param write_dir Répertoire d'écriture des rasters en GeoTIFF/COG, ou `NULL`.
#' @param bord Côtés ouverts de la fenêtre, quand `pre` n'est qu'une **tuile** d'un
#'   territoire plus vaste (voir [certifier_propagation()]). `NULL` (défaut) : `pre`
#'   couvre tout le territoire, le résultat est exact partout. Sinon, la sortie porte
#'   une couche `certifie` (spec 007 §4.3).
#'
#' @section Pourquoi une zone traversée par une piste ressort `non_accessible`:
#' La question se pose devant chaque carte, et il y a **trois réponses**, très
#' inégales. Mesuré sur l'AOI de Dabo (16 783 cellules `non_accessible`, dont
#' 1 912 à moins de 25 m d'un linéaire BD TOPO) :
#'
#' 1. **Ce que vous voyez n'est pas une desserte pour le modèle — 93 % des cas.**
#'    La classification ACCESSFOR ne retient que « Route à 1/2 chaussées »,
#'    « Route empierrée » et « Chemin » ; **tout le reste** — au premier chef les
#'    **sentiers**, mais aussi ronds-points, escaliers, bacs — devient
#'    `hors_desserte` et sort du débardage. Sur Dabo cela fait 320 tronçons sur
#'    1 032, soit **31 % du réseau visible sur une carte**. Ce n'est pas un
#'    défaut : c'est la règle de l'annexe p. 51, et elle est délibérée. Un
#'    gestionnaire qui juge ces sentiers praticables change de
#'    `classification` dans [acquire_desserte()] — en sachant que `"accessfor"`
#'    et `"clsvac"` divergent sur **42 %** des tronçons.
#' 2. **La pente, pas la distance — 7 % des cas.** Les cellules restantes
#'    touchent une vraie desserte, mais dépassent le seuil de roulage
#'    (`pente_skidder_max_pct`, 30 %) ; l'essentiel tombe aussi dans
#'    `exclusion_mask` (pente d'abattage). L'engin n'y roule pas et n'y travaille
#'    pas : la proximité d'une piste n'y change rien.
#' 3. **La piste est orpheline.** Une cellule rattachée à une desserte qui ne
#'    rejoint **aucune route** est déclarée non accessible : le bois y arriverait
#'    sans pouvoir en repartir. Ce motif n'explique aucune cellule sur Dabo, mais
#'    il domine sur un réseau fragmenté — c'est ce que
#'    [verifier_integrite_desserte()] diagnostique.
#'
#' Une cellule **non certifiée** est `NA` (`indetermine`), jamais rangée dans
#' `non_accessible` : le doute se déclare, il ne se range pas (spec 007 §4.4).
#'
#' @return Un objet de classe `foretaccess_skidder` :
#'   \describe{
#'     \item{`accessibilite`}{`SpatRaster` catégoriel : `parcourable`,
#'       `accessible`, `non_accessible`, `hors_foret`. `NA` = indéterminé.}
#'     \item{`distance_treuillage`}{distance **3D** de treuillage (m), 0 sinon.}
#'     \item{`distance_trainage_foret`}{distance de traînage en forêt (m).}
#'     \item{`distance_trainage_piste`}{distance sur piste jusqu'à une route (m).}
#'     \item{`distance_debardage`}{somme des trois précédentes.}
#'     \item{`allocation`}{cellule de desserte de rattachement.}
#'     \item{`trajet`}{`sf` de `LINESTRING`, ou `NULL`.}
#'     \item{`certifie`}{`SpatRaster` logique, ou `NULL` si `bord` l'est.}
#'     \item{`recap`}{`data.frame` des surfaces et volumes par classe.}
#'     \item{`grid`, `config`, `fichiers`}{comme au Lot 1.}
#'   }
#' @export
#' @examples
#' toy <- system.file("extdata/toy", package = "foretaccess")
#' pre <- preprocess(file.path(toy, "mnt.tif"), file.path(toy, "desserte.gpkg"),
#'                   file.path(toy, "foret.gpkg"))
#' sk <- skidder(pre)
#' sk$recap
skidder <- function(pre,
                    config = foretaccess_config(),
                    trajets_depuis = NULL,
                    write_dir = NULL,
                    bord = NULL) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  validate_config(config)

  if (as.integer(config$skidder$option_modelisation) != 1L) {
    cli::cli_abort(c(
      "Seule l'option de modelisation 1 est implementee.",
      "i" = "L'option 2 (privilegier le debusquage) est reportee (spec 002, section 10.8)."
    ))
  }

  # Le reseau public n'accueille pas de bois debarde : c'est le point de
  # chargement du camion, et pour le skidder une barriere. Sylvaccess l'exclut
  # explicitement des sources (`from_rast[Res_pub==1]=0`). Cf. .classes_desserte().
  desserte_cel <- .cellules_livraison(pre)
  if (!length(desserte_cel)) {
    cli::cli_abort("Aucune cellule de desserte : le skidder n'a pas de point de depart.")
  }

  # --- Treuillage : balayage radial, hors cellules de desserte. ---------------
  zone_tr <- zone_treuillable(pre, config)
  zone_tr[desserte_cel] <- 0
  # Le balayage part des seules cellules de LIVRAISON : on ne treuille pas vers
  # une route publique. Lui passer `pre$desserte` brut la remettait en jeu comme
  # source, et c'est de la que venaient 98,9 % de nos cellules en trop.
  treuil <- treuiller(pre$mnt, .desserte_livraison(pre), zone_tr, config)

  # --- Trainage sur piste : distance le long des pistes jusqu'a une route. ----
  # Elle se calcule AVANT le trainage en foret, dont elle est une entree : c'est
  # elle qui penalise les pistes eloignees du reseau (voir plus bas).
  #
  # Si le pretraitement la porte deja (tuilage), elle est globale, donc exacte : le
  # reseau est unidimensionnel et creux, on le propage une fois pour toute l'emprise
  # plutot que de faire grandir le halo jusqu'a sa plus longue piste (spec 007 §4.3.1).
  #
  # La propagation LE LONG du reseau se fait sur la pente seule, sans surcout
  # d'obstacle : une desserte n'est pas un obstacle a la circulation sur
  # elle-meme. Le reseau public est a la fois desserte (on y livre le bois) et
  # obstacle du skidder (on ne debarde pas au travers) ; lui appliquer le
  # surcout ferait payer 1000 par cellule de route traversee et rendrait la
  # distance sur piste absurde. Sylvaccess fait de meme : `Link_tracks_res_pub`
  # et `Link_RF_res_pub` tournent sur `Pond_pente` (pente pure), et seule la
  # propagation en foret utilise `Pond_pente2` (pente + 1000 x obstacles).
  cout_reseau <- ponderation_pente(pre$slope_pct)
  piste <- if (is.null(pre$distance_piste)) {
    .distance_sur_piste(pre, cout_reseau, bord)
  } else {
    # Distance ET injoignabilite precalculees globalement (`.precalculer_piste()`).
    # `injoignable` est un fait global : le reprendre ici, sans quoi le tuilage
    # gardait comme semences des pistes orphelines que le mono-bloc ecarte.
    inj <- if (is.null(pre$piste_injoignable)) {
      rep(FALSE, terra::ncell(pre$mnt))
    } else {
      as.logical(terra::values(pre$piste_injoignable))
    }
    list(
      distance = as.numeric(terra::values(pre$distance_piste)),
      injoignable = inj,
      certifie = NULL
    )
  }
  d_piste <- piste$distance

  # --- Trainage en foret : plus court chemin depuis la desserte. --------------
  # La zone roulable inclut le saut de `distance_hors_desserte_max_m` hors foret.
  #
  # DEUX propagations, et non une, parce que Sylvaccess en fait deux : une depuis
  # les PISTES sur la zone privee des routes forestieres
  # (`Dfwd_flat_forest_tracks`, zone `Pente_ok_skidder * (Route_for == 0)`), une
  # depuis les ROUTES sur la zone privee des pistes (`Dfwd_flat_forest_road`,
  # zone `Pente_ok_skidder * (Piste == 0)`). Les deux resultats sont ensuite
  # ARBITRES (voir `.arbitrer_desserte()`). Une propagation unique semant tout le
  # reseau a cout nul -- ce que nous faisions -- allouait chaque cellule a la
  # desserte la plus proche a vol de cout, fut-elle en bout d'une piste de 2 km.
  cout <- surface_cout_skidder(pre, config)
  zone_rl <- zone_roulable_connectee(pre, config)
  jeux <- .jeux_desserte(
    pre, desserte_cel, zone_rl, d_piste, piste$injoignable, config
  )

  rl <- .rouler(cout, jeux, zone_rl, d_piste, pre, config, bord)
  roulage <- rl$roulage
  cert_r <- rl$certificat

  # --- Combinaison (option 1 : le treuillage prime). --------------------------
  d_tr <- as.numeric(terra::values(treuil$distance))
  a_tr <- as.numeric(terra::values(treuil$allocation))
  d_rl <- as.numeric(terra::values(roulage$cout_cumule))
  a_rl <- as.numeric(terra::values(roulage$allocation))
  # Pour le classement, `parcourable` decrit la praticabilite du terrain forestier,
  # pas la zone de propagation (qui deborde de 50 m hors foret).
  roulable <- as.numeric(terra::values(zone_roulage(pre, config))) == 1
  foret <- as.numeric(terra::values(pre$foret_mask)) == 1
  pente_na <- is.na(terra::values(pre$slope_pct))

  est_desserte <- rep(FALSE, length(d_tr))
  est_desserte[desserte_cel] <- TRUE

  treuille <- !is.na(d_tr) & !est_desserte
  roule <- !is.na(d_rl) & !est_desserte

  allocation <- ifelse(treuille, a_tr, ifelse(roule, a_rl, NA_real_))
  allocation[est_desserte] <- desserte_cel

  dist_treuil <- ifelse(treuille, d_tr, 0)
  dist_foret <- ifelse(!treuille & roule, d_rl, 0)
  dist_piste <- .piste_allouee(d_piste, allocation)

  # --- Treuillage depuis le CONTOUR de la zone roulee (troisieme passe). ------
  # L'engin entre en foret, s'arrete au bord du terrain roulable, et treuille
  # DEPUIS LA. Sans cette passe, une cellule ne peut etre treuillee que depuis
  # une desserte : c'est ce qui nous rendait trop conservateurs sur 1,7 % de la
  # carte ColduPre (des cellules a 70 m de toute route y recoivent pourtant du
  # debusquage). Cf. `skid_debusq_contour()` / `skid_fill_contour()`.
  ct <- .treuillage_contour(
    pre, config, zone_tr, d_rl, a_rl, d_piste, foret, roule | est_desserte
  )
  if (!is.null(ct)) {
    # Merge additif, jamais correctif : Sylvaccess ne remplit que les cellules
    # qu'aucune passe precedente n'a atteintes (`if Ddebusquage[y,x]<0`).
    neuf <- !is.na(ct$distance) & !treuille & !roule & !est_desserte
    dist_treuil[neuf] <- ct$distance[neuf]
    dist_foret[neuf] <- ct$distance_foret[neuf]
    dist_piste[neuf] <- ct$distance_piste[neuf]
    allocation[neuf] <- ct$allocation[neuf]
    treuille <- treuille | neuf
  }

  # Une cellule rattachee a une desserte INJOIGNABLE n'est pas accessible : le
  # bois y arriverait sans pouvoir en repartir (piste orpheline, qui ne rejoint
  # aucune route). Cf. `.distance_sur_piste()`.
  orpheline <- rep(FALSE, length(d_tr))
  ok <- !is.na(allocation)
  orpheline[ok] <- piste$injoignable[allocation[ok]]

  # `parcourable` decrit la praticabilite du terrain (pente sous le seuil), pas le
  # mecanisme d'extraction : une cellule treuillee peut etre parcourable.
  accessible <- (treuille | roule | est_desserte) & !orpheline
  parcourable <- accessible & roulable

  codes <- rep(3, length(d_tr)) # non_accessible
  codes[accessible] <- 2 # accessible (par treuillage)
  codes[parcourable | est_desserte] <- 1 # parcourable par l'engin
  codes[!foret & !est_desserte] <- 4 # hors_foret
  codes[pente_na] <- NA_real_

  # Une cellule non certifiee est `indetermine` (`NA`), jamais rangee dans
  # `non_accessible` : le doute se declare, il ne se range pas (spec 007 §4.4).
  certifie <- .certifier_skidder(cert_r, piste$certifie, treuille, roule, allocation, pre, config, bord)
  if (!is.null(certifie)) codes[!certifie] <- NA_real_

  faire <- function(v, nom) {
    r <- terra::rast(pre$mnt)
    terra::values(r) <- v
    names(r) <- nom
    r
  }

  acc <- faire(codes, "accessibilite")
  levels(acc) <- data.frame(
    value = 1:4,
    classe = c("parcourable", "accessible", "non_accessible", "hors_foret")
  )

  dist_total <- dist_treuil + dist_foret + dist_piste
  dist_total[is.na(codes)] <- NA_real_

  sk <- structure(
    list(
      accessibilite           = acc,
      distance_treuillage     = faire(dist_treuil, "distance_treuillage"),
      distance_trainage_foret = faire(dist_foret, "distance_trainage_foret"),
      distance_trainage_piste = faire(dist_piste, "distance_trainage_piste"),
      distance_debardage      = faire(dist_total, "distance_debardage"),
      allocation              = faire(allocation, "allocation"),
      trajet                  = NULL,
      certifie                = if (is.null(certifie)) NULL else faire(certifie, "certifie"),
      recap                   = recapituler(acc, pre$volume),
      grid                    = pre$grid,
      config                  = config,
      fichiers                = NULL
    ),
    class = "foretaccess_skidder"
  )

  if (!is.null(trajets_depuis)) {
    sk$trajet <- chemin_optimal(roulage, trajets_depuis)
  }
  if (!is.null(write_dir)) {
    sk$fichiers <- .ecrire_rasters_skidder(sk, write_dir)
  }
  sk
}

# Treuillage depuis le contour de la zone atteinte en roulant (`skid_debusq_contour`).
#
# `zone_tracteur` = les cellules de foret ou l'engin peut se rendre en roulant. Son
# CONTOUR (au sens de `get_contour()` : cellule de la zone dont la fenetre 3x3 n'est
# pas entierement dans la zone) sert de nouvelle rampe de treuillage. Chaque point du
# contour PORTE la distance deja parcourue pour l'atteindre -- trainage en foret plus
# trainage sur piste --, et le critere d'amelioration porte sur le TOTAL, pas sur la
# seule longueur de cable. Les cibles sont les cellules treuillables HORS de la zone
# roulee : on ne treuille pas vers un point ou l'on peut se rendre.
#
# Rend `NULL` si le contour est vide (pas de zone roulee, ou zone sans bord).
.treuillage_contour <- function(pre, config, zone_tr, d_rl, a_rl, d_piste, foret, roule) {
  n <- terra::ncell(pre$mnt)
  zt <- roule & foret

  # Contour : cellule de la zone dont la fenetre 3x3 compte moins de 9 cellules de
  # zone. Les cellules de bord de grille en font partie, comme chez Sylvaccess (le
  # denominateur y vaut 9 quelle que soit la troncature de la fenetre).
  ztr <- terra::rast(pre$mnt)
  terra::values(ztr) <- as.numeric(zt)
  voisins <- terra::focal(ztr, w = 3, fun = "sum", na.rm = TRUE)
  contour <- zt & (as.numeric(terra::values(voisins)) < 9)

  # Un point du contour n'est une rampe de treuillage que s'il est praticable :
  # ni obstacle, ni reseau public, ni desserte (deja traitee par les deux
  # premieres passes).
  contour <- contour &
    as.numeric(terra::values(pre$obstacles_complets_mask)) == 0 &
    as.numeric(terra::values(pre$obstacles_partiels_mask)) == 0 &
    as.numeric(terra::values(pre$reseau_public_mask)) == 0 &
    is.na(terra::values(pre$desserte))
  contour[is.na(contour)] <- FALSE
  if (!any(contour)) {
    return(NULL)
  }

  src <- terra::rast(pre$mnt)
  v <- rep(NA_real_, n)
  v[contour] <- 1
  terra::values(src) <- v

  # Cibles : treuillables, mais hors de la zone deja roulee (`Zone_OK[zone_tracteur==1]=0`).
  zone_ct <- terra::deepcopy(zone_tr)
  zone_ct[which(zt)] <- 0

  # Cout porte par chaque rampe : trainage en foret + trainage sur la piste de sa
  # desserte de rattachement.
  cout <- rep(0, n)
  cout[contour] <- d_rl[contour] + .piste_allouee(d_piste, a_rl)[contour]

  tr <- treuiller(pre$mnt, src, zone_ct, config, depart_cout = cout)

  d <- as.numeric(terra::values(tr$distance))
  a <- as.numeric(terra::values(tr$allocation)) # cellule du contour, pas la desserte
  d[contour] <- NA_real_ # les rampes elles-memes restent traitees par le roulage

  atteint <- !is.na(d) & !is.na(a)
  dfor <- rep(NA_real_, n)
  dpis <- rep(NA_real_, n)
  alloc <- rep(NA_real_, n)
  # On herite de la rampe : sa distance de trainage, sa piste, et sa desserte.
  dfor[atteint] <- d_rl[a[atteint]]
  dpis[atteint] <- .piste_allouee(d_piste, a_rl)[a[atteint]]
  alloc[atteint] <- a_rl[a[atteint]]
  d[!atteint] <- NA_real_

  list(distance = d, distance_foret = dfor, distance_piste = dpis, allocation = alloc)
}

# Sur-approximation locale de la zone traversable globale : tout terrain roulable, plus
# la desserte elle-meme, qu'une pente forte pourrait exclure. `d_bord` doit s'y propager
# librement, sans quoi il cesserait de minorer le cout d'entree (spec 007 §4.3).
.zone_majorante <- function(pre, config) {
  z <- terrain_roulable(pre, config)
  z[!is.na(terra::values(pre$desserte))] <- 1
  z
}

# Portee maximale du treuil : au-dela, aucun rayon ne survit. Le halo doit la couvrir,
# sinon une desserte hors fenetre treuillerait dans la tuile sans qu'on le sache.
.portee_treuil <- function(config, res) {
  sk <- config$skidder
  max(sk$debardage_amont_max_m, sk$debardage_aval_max_m) + 1.5 * res
}

# Certificat composite du moteur (spec 007 §4.3). `NULL` hors tuilage.
#
# Le treuillage, l'abattage et la pente sont *locaux* : exacts des lors que le halo
# couvre la portee du treuil. Restent le trainage, dont le certificat porte a la fois
# le cout et la zone, et la distance sur piste, qu'il faut certifier **a la cellule de
# desserte allouee** -- c'est elle qui la porte.
.certifier_skidder <- function(cert_r, cert_piste, treuille, roule, allocation,
                               pre, config, bord) {
  if (is.null(cert_r)) {
    return(NULL)
  }
  res <- terra::res(pre$mnt)[1]
  halo_suffisant <- length(bord) == 0L ||
    .halo_cellules(pre) * res >= .portee_treuil(config, res)
  if (!halo_suffisant) {
    return(rep(FALSE, terra::ncell(pre$mnt)))
  }

  ok <- as.logical(terra::values(cert_r$certifie))
  # L'allocation du trainage n'importe que pour les cellules qu'il dessert vraiment.
  alloc_r <- roule & !treuille
  ok[alloc_r] <- ok[alloc_r] & as.logical(terra::values(cert_r$certifie_allocation))[alloc_r]

  if (!is.null(cert_piste)) {
    cp <- as.logical(terra::values(cert_piste))
    a <- !is.na(allocation)
    ok[a] <- ok[a] & cp[allocation[a]]
  }
  ok
}

# Largeur du halo effectivement disponible autour de la fenetre, en cellules. Sans
# information de tuilage, la fenetre est le territoire : la portee est toujours couverte.
.halo_cellules <- function(pre) {
  if (is.null(pre$halo_cel)) Inf else pre$halo_cel
}

# Raster de sources : chaque cellule de desserte porte son propre indice.
.sources_desserte <- function(pre, desserte_cel) {
  s <- terra::rast(pre$mnt)
  v <- rep(NA_real_, terra::ncell(s))
  v[desserte_cel] <- desserte_cel
  terra::values(s) <- v
  s
}

# Indices des cellules de desserte de classe `piste`, parmi les cellules de livraison.
# Vecteur vide si la desserte n'est pas categorisee (fixtures, dessertes-points) : il
# n'y a alors pas de piste a distinguer de la route, donc pas d'arbitrage a faire.
.cellules_piste <- function(pre, desserte_cel) {
  cl <- terra::levels(pre$desserte)[[1]]
  if (!is.data.frame(cl) || ncol(cl) < 2L) {
    return(integer(0))
  }
  code <- cl[[1]][as.character(cl[[2]]) == "piste"]
  if (!length(code)) {
    return(integer(0))
  }
  v <- as.numeric(terra::values(pre$desserte))
  desserte_cel[v[desserte_cel] %in% code]
}

# Propagation du trainage DEPUIS LES PISTES (`Dfwd_flat_forest_tracks`,
# sylvaccess_cython3.pyx:3667-3736). Ce n'est PAS un Dijkstra : la ponderation de la
# piste y est un VETO, pas un moteur. Transcription du test (`pyx:3712-3721`) :
#
#     if Out_distance[y,x] > Dist:                     # (1) le cout FORET s'ameliore
#         if Dpiste[y,x] < 0:                          #     cellule jamais atteinte
#             relaxer
#         elif Dpiste[y,x]*100 + 2*Out_distance[y,x]   # (2) ET le critere pondere
#              > 2*Dist + Dpiste[y1,x1]*100:           #     s'ameliore aussi
#             relaxer
#
# La condition (2), normalisee, compare `d_foret + c_prop x d_piste(semence)`. Mais
# elle est IMBRIQUEE dans (1) : elle peut BLOQUER une amelioration du cout foret, elle
# ne peut jamais faire accepter un chemin forestier plus long pour gagner de la piste.
#
# Cela a une consequence qu'on ne voit qu'en mesurant : la distance en foret reste
# PILOTEE par le cout forestier -- le veto peut la laisser au-dessus du minimum (il
# refuse un raccourci qui degraderait la semence), mais jamais l'allonger au profit
# de la piste. Un vrai `argmin(d_foret + 0,5 x d_piste)` -- l'implementation
# "propre", qu'on croit fidele a l'intention -- echange, lui, de la foret contre de
# la piste : mesure sur ColduPre, mediane 138,3 m la ou Sylvaccess donne 124,0 ; le
# veto rend 120,2 m. On transcrit donc la LETTRE, pas l'intention.
#
# Corollaire assume : comme dans la source, le resultat depend de l'ORDRE de
# depilement quand plusieurs semences se valent. C'est une heuristique gloutonne,
# pas un minimum global -- et c'est ce que fait Sylvaccess.
#
# `d_piste` est un PAYLOAD de la semence, transporte a l'identique le long du chemin
# (`Dpiste[y,x] = Dpiste[y1,x1]`, pyx:3721) : il ne varie que si la cellule change de
# semence allouee.
#
# Le veto brise la monotonie de l'etiquette : une cellule deja depilee peut encore
# s'ameliorer. On ne fige donc AUCUNE cellule -- le tas sert de file de travail
# (label-correcting, comme les balayages iteratifs du `.pyx`). La terminaison tient
# a ce que `dist` decroit strictement a chaque relaxation acceptee.
.propager_trainage <- function(cout, franchissable, depart, d_piste, nr, nc, pas, c_prop) {
  n <- nr * nc
  dist <- rep(Inf, n)
  alloc <- rep(NA_real_, n)
  pred <- rep(NA_real_, n)
  dpis <- rep(NA_real_, n) # `Dpiste` : payload de la semence (NA = jamais atteinte)

  tas <- .tas_binaire(max(64L, length(depart) * 2L))
  vo <- .voisins_8(pas)
  dl <- vo$dl
  dc <- vo$dc
  pas_v <- vo$pas

  dist[depart] <- 0
  alloc[depart] <- depart
  dpis[depart] <- d_piste[depart]
  for (s in depart) tas$ajouter(s, 0)

  while (!tas$vide()) {
    u <- tas$retirer()
    du <- dist[u]
    dpu <- dpis[u]
    lu <- ((u - 1L) %/% nc) + 1L
    cu <- ((u - 1L) %% nc) + 1L

    for (k in seq_len(8L)) {
      lv <- lu + dl[k]
      cv <- cu + dc[k]
      if (lv < 1L || lv > nr || cv < 1L || cv > nc) next

      v <- (lv - 1L) * nc + cv
      if (!franchissable[v]) next

      dv <- du + cout[v] * pas_v[k]
      # (1) Le cout foret doit s'ameliorer strictement -- garde de `pyx:3712`.
      if (dv >= dist[v]) next
      # (2) Et le critere pondere aussi, si la cellule a deja une semence.
      if (!is.na(dpis[v]) &&
        dist[v] + c_prop * dpis[v] <= dv + c_prop * dpu) {
        next
      }

      dist[v] <- dv
      alloc[v] <- alloc[u]
      pred[v] <- u
      dpis[v] <- dpu
      tas$ajouter(v, dv)
    }
  }

  dist[!is.finite(dist)] <- NA_real_
  list(dist = dist, alloc = alloc, pred = pred)
}

# Les deux jeux de semences du trainage, calques sur les deux appels de Sylvaccess
# (`Sylvaccess_1_skidder.py:435` et `:442`) :
#
#  * PISTE  : semences = cellules de piste ; zone privee des ROUTES FORESTIERES
#             (`Pente_ok_skidder * (Route_for == 0)`) ; propagation a veto
#             (`.propager_trainage()`).
#  * ROUTE  : semences = routes et pistes DFCI ; zone privee des PISTES
#             (`Pente_ok_skidder * (Piste == 0)`) ; Dijkstra ordinaire, aucune
#             ponderation (`Dfwd_flat_forest_road`).
#
# Sans piste (ou sans route), il n'y a rien a arbitrer : un seul jeu, semences =
# toute la desserte, comportement d'avant le Lot 12. C'est aussi le cas des
# dessertes non categorisees.
.jeux_desserte <- function(pre, desserte_cel, zone_rl, d_piste, injoignable, config) {
  cel_piste <- .cellules_piste(pre, desserte_cel)
  cel_route <- setdiff(desserte_cel, cel_piste)

  # Une piste ORPHELINE (qui ne rejoint aucune route) n'est pas une semence : le
  # bois y arriverait sans pouvoir en repartir. Sylvaccess la RETIRE de sa table
  # (`Lien_Piste`, valeur sentinelle 100001 supprimee -- `Sylvaccess_1_skidder.py:204`).
  # La garder semerait la penalite `c_prop x 0` (sa distance sur piste vaut 0, faute
  # de route a rejoindre) : la piste orpheline serait donc la MOINS penalisee de
  # toutes, et raflerait l'arbitrage contre les routes qui, elles, desservent
  # vraiment. Mesure sur le jouet : 6 cellules de foret rendues inaccessibles alors
  # qu'une route les servait.
  cel_piste <- setdiff(cel_piste, which(injoignable))

  if (!length(cel_piste) || !length(cel_route)) {
    return(list(list(
      cellules = desserte_cel, sources = .sources_desserte(pre, desserte_cel),
      zone = zone_rl, veto = FALSE
    )))
  }

  # La zone de chaque propagation exclut les cellules de l'AUTRE reseau.
  masque <- function(cel) {
    m <- terra::rast(pre$mnt)
    v <- as.numeric(terra::values(zone_rl))
    v[is.na(v)] <- 0
    v[cel] <- 0
    terra::values(m) <- v
    m
  }

  list(
    piste = list(
      cellules = cel_piste, sources = .sources_desserte(pre, cel_piste),
      zone = masque(cel_route), veto = TRUE
    ),
    route = list(
      cellules = cel_route, sources = .sources_desserte(pre, cel_route),
      zone = masque(cel_piste), veto = FALSE
    )
  )
}

# Lance les propagations de trainage, puis les arbitre. Rend un objet de meme forme
# que `propager_cout()` -- `cout_cumule` y est la distance en FORET -- et le
# certificat correspondant (conjonction des deux, en tuilage).
.rouler <- function(cout, jeux, zone_rl, d_piste, pre, config, bord) {
  lancer <- function(j) {
    prop <- if (j$veto) {
      .trainage_piste(cout, j, d_piste, pre, config)
    } else {
      propager_cout(cout, j$sources, zone = j$zone)
    }
    if (is.null(bord)) {
      return(list(prop = prop, cert = NULL))
    }
    # `zone_rl` est *monotone* : calculee sur une fenetre, elle ne peut que
    # sous-estimer la zone globale. Certifier le trainage suffit donc a certifier
    # aussi la zone -- a condition de minorer `d_bord` sur une sur-approximation.
    # La propagation a veto (`j$veto`) exige la certification STRICTE (voir
    # `.certifier_depuis()`) : a egalite, le veto n'est pas stable.
    cert <- .certifier_depuis(
      cout, prop,
      zone_majorante = .zone_majorante(pre, config), bord = bord, strict = j$veto
    )
    list(prop = prop, cert = cert)
  }

  res <- lapply(jeux, lancer)
  if (length(res) == 1L) {
    return(list(roulage = res[[1]]$prop, certificat = res[[1]]$cert))
  }
  .arbitrer_desserte(res$piste, res$route, d_piste, pre, config, bord)
}

# Habille `.propager_trainage()` en `foretaccess_propagation`, comme `propager_cout()`.
.trainage_piste <- function(cout, jeu, d_piste, pre, config) {
  nr <- terra::nrow(cout)
  nc <- terra::ncol(cout)
  cv <- as.numeric(terra::values(cout))
  zv <- as.numeric(terra::values(jeu$zone))
  franchissable <- !is.na(cv) & !is.na(zv) & zv != 0

  s <- .propager_trainage(
    cout = cv, franchissable = franchissable, depart = jeu$cellules,
    d_piste = d_piste, nr = nr, nc = nc, pas = terra::res(cout)[1],
    c_prop = config$skidder$ponderation_piste_propagation
  )

  faire <- function(v, nom) {
    r <- terra::rast(cout)
    terra::values(r) <- v
    names(r) <- nom
    r
  }
  structure(
    list(
      cout_cumule = faire(s$dist, "cout_cumule"),
      allocation = faire(s$alloc, "allocation"),
      predecesseur = faire(s$pred, "predecesseur")
    ),
    class = "foretaccess_propagation"
  )
}

# Arbitrage route forestiere <-> piste, calque sur `skid_fill_opt1`
# (`sylvaccess_cython3.pyx:4283`) :
#
#     if not (DTrain_foret + 0.1 * DTrain_piste) < D_foret_RF:  ->  on prend la ROUTE
#
# soit : la route l'emporte des que `d_foret_route <= d_foret_piste + c_arb x d_piste`.
# Le mettre a l'egalite n'est pas un detail -- c'est la source qui prefere la route a
# egalite. Et le coefficient d'arbitrage (0,1) n'est PAS celui de la propagation
# (0,5) : ce sont deux decisions distinctes. Le premier dit ce que vaut un metre de
# piste quand on choisit entre deux pistes ; le second, ce qu'il vaut quand on
# renonce a la piste pour la route -- d'ou un fort biais en faveur de la piste.
.arbitrer_desserte <- function(rp, rr, d_piste, pre, config, bord) {
  n <- terra::ncell(pre$mnt)
  vals <- function(r) as.numeric(terra::values(r))

  c_arb <- config$skidder$ponderation_piste_arbitrage

  # Les deux propagations rendent une distance en FORET (le veto de
  # `.propager_trainage()` ne penalise pas la sortie : il ne fait que trancher entre
  # semences). Elles sont donc directement comparables.
  d_p <- vals(rp$prop$cout_cumule) # depuis les pistes
  a_p <- vals(rp$prop$allocation)
  p_p <- vals(rp$prop$predecesseur)
  d_pi <- .piste_allouee(d_piste, a_p) # piste que la semence retenue laisse a remonter

  d_r <- vals(rr$prop$cout_cumule) # depuis les routes
  a_r <- vals(rr$prop$allocation)
  p_r <- vals(rr$prop$predecesseur)

  vu_p <- !is.na(d_p)
  vu_r <- !is.na(d_r)
  route <- vu_r & (!vu_p | (d_r <= d_p + c_arb * d_pi))

  cout <- rep(NA_real_, n)
  cout[vu_p] <- d_p[vu_p]
  cout[route] <- d_r[route]

  alloc <- rep(NA_real_, n)
  alloc[vu_p] <- a_p[vu_p]
  alloc[route] <- a_r[route]

  pred <- rep(NA_real_, n)
  pred[vu_p] <- p_p[vu_p]
  pred[route] <- p_r[route]

  faire <- function(v, nom) {
    r <- terra::rast(pre$mnt)
    terra::values(r) <- v
    names(r) <- nom
    r
  }
  roulage <- structure(
    list(
      cout_cumule = faire(cout, "cout_cumule"),
      allocation = faire(alloc, "allocation"),
      predecesseur = faire(pred, "predecesseur")
    ),
    class = "foretaccess_propagation"
  )

  # En tuilage, une cellule n'est certifiee que si les DEUX propagations le sont :
  # l'arbitrage les compare, et un chemin venu du dehors peut renverser le choix.
  cert <- NULL
  if (!is.null(bord)) {
    et <- function(a, b, nom) faire(as.numeric(vals(a) & vals(b)), nom)
    ok <- et(rp$cert$certifie, rr$cert$certifie, "certifie")
    cert <- structure(
      list(
        propagation = roulage,
        certifie = ok,
        certifie_allocation = et(
          rp$cert$certifie_allocation, rr$cert$certifie_allocation,
          "certifie_allocation"
        ),
        n_non_certifie = sum(vals(ok) == 0)
      ),
      class = "foretaccess_certificat"
    )
  }

  list(roulage = roulage, certificat = cert)
}

# Distance, le long des pistes, jusqu'a la route la plus proche. Les cellules de
# route valent 0 ; les cellules hors reseau valent 0 (elles ne trainent pas sur piste).
#
# Le cout est la surface ponderee par la pente (`Pond_pente`), comme dans
# `Dfwd_flat_forest_tracks()` : une piste en devers coute plus qu'une piste plate.
#
# Le reseau est une donnee locale : sa restriction a la fenetre est exacte, et sert donc
# aussi de zone majorante. Seule la *distance* le long du reseau deborde de la fenetre.
.distance_sur_piste <- function(pre, cout, bord = NULL) {
  n <- terra::ncell(pre$mnt)

  # Sans table de categories, la desserte ne distingue pas piste et route : il n'y a
  # donc pas de trainage sur piste (cas des dessertes-points de test, ou d'un reseau
  # non categorise). On rend une distance nulle plutot que de planter.
  cl <- terra::levels(pre$desserte)[[1]]
  if (!is.data.frame(cl) || ncol(cl) < 2L) {
    return(list(distance = rep(0, n), injoignable = rep(FALSE, n), certifie = NULL))
  }
  code_piste <- cl[[1]][as.character(cl[[2]]) == "piste"]
  codes <- as.numeric(terra::values(pre$desserte))

  # Deux roles distincts, a ne pas confondre : le reseau public n'est pas une
  # SOURCE de debardage (on n'y depose pas de bois -- cf. `.cellules_livraison()`),
  # mais il fait bien partie du RESEAU sur lequel se mesure la distance : c'est
  # le terminus de la chaine piste -> route forestiere -> route publique.
  # Sylvaccess le passe explicitement en argument de `Link_tracks_res_pub` et
  # `Link_RF_res_pub`. L'exclure ici orphelinerait des pistes que Sylvaccess
  # dessert (mesure : -3 points d'accord sur ColduPre).
  est_piste <- !is.na(codes) & codes %in% code_piste
  est_route <- !is.na(codes) & !est_piste

  if (!any(est_route) || !any(est_piste)) {
    return(list(distance = rep(0, n), injoignable = rep(FALSE, n), certifie = NULL))
  }

  zone <- terra::rast(pre$mnt)
  terra::values(zone) <- as.numeric(est_piste | est_route)

  src <- terra::rast(pre$mnt)
  v <- rep(NA_real_, n)
  v[est_route] <- 1
  terra::values(src) <- v

  if (is.null(bord)) {
    prop <- propager_cout(cout, src, zone = zone)
    certifie <- NULL
  } else {
    cert <- certifier_propagation(cout, src, zone = zone, bord = bord)
    prop <- cert$propagation
    certifie <- cert$certifie
  }

  # Une cellule de desserte dont le cout cumule reste NA ne rejoint AUCUNE route :
  # le bois y arriverait sans pouvoir en repartir. Elle est INJOIGNABLE, et les
  # cellules de foret qui lui sont allouees sont inaccessibles. Rendre 0 ici -- la
  # reponse la plus optimiste possible -- ferait passer une piste orpheline pour
  # une desserte parfaite. Sylvaccess les recense (`Routes_forestieres_non_connectees`).
  injoignable <- as.logical((est_piste | est_route) &
    is.na(as.numeric(terra::values(prop$cout_cumule))))

  d <- as.numeric(terra::values(prop$cout_cumule))
  d[is.na(d)] <- 0
  list(distance = d, injoignable = injoignable, certifie = certifie)
}

# Reporte la distance sur piste de la cellule de desserte allouee a chaque pixel.
.piste_allouee <- function(d_piste, allocation) {
  out <- rep(0, length(allocation))
  ok <- !is.na(allocation)
  out[ok] <- d_piste[allocation[ok]]
  out
}

# Couches raster ecrites par write_dir.
.couches_skidder <- function() {
  c(
    "accessibilite", "distance_treuillage", "distance_trainage_foret",
    "distance_trainage_piste", "distance_debardage", "allocation"
  )
}

.ecrire_rasters_skidder <- function(sk, write_dir) {
  checkmate::assert_string(write_dir)
  dir.create(write_dir, recursive = TRUE, showWarnings = FALSE)

  chemins <- vapply(.couches_skidder(), function(nm) {
    f <- file.path(write_dir, paste0(nm, ".tif"))
    terra::writeRaster(sk[[nm]], f, filetype = "COG", overwrite = TRUE)
    f
  }, character(1))
  as.list(chemins)
}

#' Classify skidding distance into Sylvaccess distance bands
#'
#' Turns the continuous skidding distance (`sk$distance_debardage`) into the
#' categorical **"skidding distance classes"** raster that Sylvaccess exports:
#' distance bands (`config$skidder$classes_distance_m`, e.g. 0-250, 250-500,
#' 500-1000, 1000-1500, 1500-2000, >2000 m), plus `inaccessible`,
#' `inexploitable` (harvest slope exceeded) and `hors_foret`. The `skidder()`
#' engine already computes the distance; this is the display-ready product.
#'
#' Precedence per cell: `hors_foret` (not forest) < distance band (reachable) <
#' `inaccessible` (forest, not reached) < `inexploitable` (forest, local slope
#' above the harvest threshold — overrides). The `inexploitable` class requires
#' `pre` (its `exclusion_mask`); without it those cells stay in their
#' accessibility class.
#'
#' @param sk A `foretaccess_skidder` **or** `foretaccess_porteur` object (output
#'   of [skidder()] / [porteur()]). Both carry the same `accessibilite` levels
#'   and a `distance_debardage`, so the banding is identical; only the underlying
#'   distance model differs.
#' @param pre The `foretaccess_preprocessing` object used to run the engine.
#'   Optional; supplies the harvest-slope exclusion needed for the
#'   `inexploitable` class.
#' @param config A `foretaccess_config`; the distance bands live in
#'   `config$skidder$classes_distance_m`. Defaults to `sk$config`.
#' @return A categorical `SpatRaster` (`classe_debardage`) with an attached
#'   colour table, directly plottable and compatible with [recapituler()].
#' @seealso [accessfor_correspondance()] maps these classes onto the IGN ACCESSFOR
#'   reference layer.
#' @export
classes_debardage <- function(sk, pre = NULL, config = sk$config) {
  checkmate::assert_multi_class(sk, c("foretaccess_skidder", "foretaccess_porteur"))
  if (!is.null(pre)) checkmate::assert_class(pre, "foretaccess_preprocessing")
  bornes <- config$skidder$classes_distance_m
  k <- length(bornes) # nombre de bandes (la derniere est ouverte : > bornes[k])

  # Codes de la couche d'accessibilite (robuste aux valeurs numeriques).
  niv <- terra::levels(sk$accessibilite)[[1]]
  code <- function(nom) niv[[1]][as.character(niv[[2]]) == nom]
  acc <- as.numeric(terra::values(sk$accessibilite))
  dist <- as.numeric(terra::values(sk$distance_debardage))

  # Bande de distance (1..k) ; findInterval : [b1,b2) -> 1, ..., >= bk -> k.
  band <- findInterval(dist, bornes)
  band[band < 1] <- 1L

  out <- rep(NA_real_, length(acc))
  out[acc == code("hors_foret")] <- k + 3 # hors foret (transparent)
  reachable <- acc %in% c(code("parcourable"), code("accessible")) & is.finite(dist)
  out[reachable] <- band[reachable]
  out[acc == code("non_accessible")] <- k + 1 # inaccessible

  # Inexploitable (pente d'abattage locale depassee) : prioritaire, foret seule.
  if (!is.null(pre)) {
    excl <- as.numeric(terra::values(pre$exclusion_mask)) == 1
    foret <- as.numeric(terra::values(pre$foret_mask)) > 0
    out[foret & excl %in% TRUE] <- k + 2 # inexploitable
  }

  r <- terra::rast(sk$accessibilite)
  terra::values(r) <- out

  # Etiquettes : bandes finies "a-b", derniere "> bk", puis les 3 classes hors bande.
  etiquettes <- c(
    if (k >= 2) paste0(bornes[-k], "-", bornes[-1]),
    paste0("> ", bornes[k]),
    "inaccessible", "inexploitable", "hors_foret"
  )
  levels(r) <- data.frame(value = seq_along(etiquettes), classe = etiquettes)

  # Table de couleurs facon Sylvaccess (vert proche -> rouge lointain).
  pal_bandes <- grDevices::colorRampPalette(
    c("#1a9e8f", "#9acd32", "#ffe600", "#f6a21e", "#e5720b", "#c0392b")
  )(k)
  couleurs <- c(pal_bandes, "#b0b0b0", "#000000", "#00000000") # +inacc +inexpl +hors_foret
  terra::coltab(r) <- data.frame(
    value = seq_along(etiquettes),
    col = couleurs
  )
  names(r) <- "classe_debardage" # apres levels<-, qui ecrase le nom de couche
  r
}

#' @export
print.foretaccess_skidder <- function(x, ...) {
  r <- x$recap
  cli::cli_inform(c(
    "Moteur skidder ForetAccess",
    "*" = "grille : {x$grid$nrow} x {x$grid$ncol} cellules",
    "*" = "surfaces (ha) : {paste0(r$classe, ' = ', signif(r$surface_ha, 4), collapse = ' ; ')}",
    "*" = "distance de debardage max : \\
           {signif(max(terra::values(x$distance_debardage), na.rm = TRUE), 5)} m"
  ))
  invisible(x)
}
