# `hors_desserte` (CL_SVAC = 0) traverse la chaine : ACCEPTE en entree (il porte
# la connectivite, cf. `verifier_integrite_desserte()`), RETIRE avant toute
# rasterisation. Ces deux moitiés doivent tenir ensemble : `acquire_desserte()`
# le conserve par defaut depuis le 2026-07-30, et `preprocess()` l'a rejete
# jusqu'a la v2.0.0 -- aucun appelant ne pouvait consommer le defaut.

seg <- function(a, b) sf::st_linestring(rbind(a, b))

# Une route horizontale et un `hors_desserte` vertical qui la CROISENT : la
# cellule de croisement est partagee. C'est la configuration qui piege.
desserte_croisement <- function() {
  sf::st_sf(
    classe = c("route", "hors_desserte"),
    geometry = sf::st_sfc(
      seg(c(0, 50), c(100, 50)),
      seg(c(50, 0), c(50, 100)),
      crs = 2154
    )
  )
}

# Ajoute des tronçons `hors_desserte` a une couche existante, en respectant le
# nom de sa colonne de geometrie (`geom` pour le jeu jouet).
ajouter_hors_desserte <- function(base, ...) {
  g <- sf::st_sfc(..., crs = sf::st_crs(base))
  extra <- sf::st_sf(classe = rep("hors_desserte", length(g)), geometry = g)
  nom <- attr(base, "sf_column")
  names(extra)[names(extra) == "geometry"] <- nom
  sf::st_geometry(extra) <- nom
  rbind(base, extra)
}

grille_croisement <- function() {
  terra::rast(terra::ext(0, 100, 0, 100), resolution = 10, crs = "EPSG:2154")
}

# Sentinelle entiere de terra pour un champ `NA`. `terra::rasterize()` la GRAVE
# dans les cellules atteintes, au lieu de les laisser vides -- et elle survit a
# `fun = "max"`. Un test qui se contente de `is.na()` est donc VACANT.
SENTINELLE <- -2147483648

test_that("valider_entrees() rejette toujours une classe reellement inconnue", {
  d <- toy_desserte()
  d$classe[1] <- "totalement_inconnue"
  expect_error(
    valider_entrees(mnt = toy_mnt(), desserte = d, foret = toy_foret()),
    "totalement_inconnue"
  )
})

test_that("valider_entrees() accepte hors_desserte", {
  d <- toy_desserte()
  d$classe[1] <- "hors_desserte"
  expect_true(valider_entrees(mnt = toy_mnt(), desserte = d, foret = toy_foret()))
})

test_that("hors_desserte n'ecrase PAS la classe d'une cellule partagee", {
  out <- foretaccess:::.rasteriser_desserte(desserte_croisement(),
    grille_croisement())
  v <- terra::values(out, mat = FALSE)

  # Le controle qui compte : la sentinelle est une VALEUR, pas un `NA`.
  expect_false(any(!is.na(v) & v == SENTINELLE))
  expect_false(any(!is.na(v) & v < 0))

  # La route garde TOUTES ses cellules, croisement compris. Sans filtrage amont
  # elle en perdait une (mesure DABO : 440 cellules sur 24 259, aux jonctions).
  route <- match("route", .classes_desserte())
  seule <- foretaccess:::.rasteriser_desserte(
    desserte_croisement()[1, ], grille_croisement()
  )
  expect_equal(sum(!is.na(v) & v == route),
    sum(!is.na(terra::values(seule, mat = FALSE))))
  expect_setequal(unique(v[!is.na(v)]), route)
})

test_that("le vocabulaire raster reste a 4 classes", {
  out <- foretaccess:::.rasteriser_desserte(desserte_croisement(),
    grille_croisement())
  niveaux <- as.character(terra::levels(out)[[1]][[2]])
  # Ajouter hors_desserte ici le ferait passer devant `reseau_public` sous le
  # `fun = "max"` qui donne la priorite a la barriere.
  expect_identical(niveaux, .classes_desserte())
  expect_false("hors_desserte" %in% niveaux)
})

test_that("une desserte entierement hors_desserte donne un raster vide, pas une erreur", {
  d <- desserte_croisement()[2, ]
  out <- foretaccess:::.rasteriser_desserte(d, grille_croisement())
  expect_true(all(is.na(terra::values(out, mat = FALSE))))
  expect_identical(as.character(terra::levels(out)[[1]][[2]]), .classes_desserte())
})

test_that("preprocess() est INVARIANT sous la presence de hors_desserte", {
  # La formulation la plus forte : elle verifie d'un coup le filtrage et
  # l'absence d'effet de bord sur les autres couches.
  stricte <- toy_desserte()
  # L'un croise la route ET la piste (cellules partagees), l'autre longe le bord
  # et n'a aucune cellule commune.
  avec_hd <- ajouter_hors_desserte(stricte,
    seg(c(0, 250), c(250, 0)),
    seg(c(10, 240), c(240, 240)))

  pre_s <- preprocess(mnt = toy_mnt(), desserte = stricte, foret = toy_foret())
  pre_a <- preprocess(mnt = toy_mnt(), desserte = avec_hd, foret = toy_foret())

  for (couche in c("desserte", "dfci_source_mask", "reseau_public_mask",
                   "foret_mask", "exclusion_mask")) {
    expect_equal(
      terra::values(pre_a[[couche]], mat = FALSE),
      terra::values(pre_s[[couche]], mat = FALSE),
      info = couche
    )
  }
  expect_identical(
    as.character(terra::levels(pre_a$desserte)[[1]][[2]]),
    as.character(terra::levels(pre_s$desserte)[[1]][[2]])
  )
})

test_that("un hors_desserte flagge CL_DFCI ne devient pas source du camion", {
  # `flag_dfci()` (voie OSM) peut apparier un CL_SVAC = 0 a une piste DFCI. Sans
  # retrait, il ouvrirait une cellule-source sur une non-desserte.
  d <- desserte_croisement()
  d$dfci <- c(0L, 1L)
  m <- foretaccess:::.rasteriser_dfci_source(d, grille_croisement())
  expect_true(all(terra::values(m, mat = FALSE) == 0))
})

# Le VERROU de contrat. L'incompatibilite de la v2.0.0 est nee de la derive de
# deux vocabulaires : `.mapper_classe_desserte()` s'est mis a emettre
# `hors_desserte`, que `.valider_desserte()` refusait. Chacun etait teste de son
# cote ; RIEN ne testait qu'ils parlaient la meme langue.
#
# Ce test echoue des qu'un mappeur emet une classe que le validateur rejette --
# c'est-a-dire au moment ou la chaine acquisition -> pretraitement se casse, et
# non plusieurs semaines plus tard chez un appelant.
test_that("tout ce que produit acquire_desserte() est accepte par preprocess()", {
  x <- data.frame(
    nature = c("Route à 2 chaussées", "Route à 1 chaussée", "Route empierrée",
               "Chemin", "Sentier", "Rond-point", "Escalier", "Bac ou liaison maritime"),
    importance = c(1L, 3L, 4L, 5L, 6L, 5L, 6L, 6L),
    liens_vers_route_nommee = c(NA, NA, NA, "ROUTNOMM01", NA, NA, NA, NA)
  )
  for (classification in c("accessfor", "clsvac", "heuristique")) {
    cl <- foretaccess:::.mapper_classe_desserte(x, classification, "ROUTNOMM01")
    inconnues <- setdiff(unique(cl), .classes_desserte_connues())
    expect_identical(inconnues, character(0),
      info = paste("classification", classification, "emet", toString(inconnues)))
  }
})

test_that("places_depot() ne propose pas de candidate sur un hors_desserte", {
  des <- foretaccess:::.desserte_lignes(
    ajouter_hors_desserte(toy_desserte(), seg(c(0, 250), c(250, 0))),
    toy_mnt()
  )
  expect_false("hors_desserte" %in% as.character(des$classe))
  expect_identical(nrow(des), nrow(foretaccess:::.desserte_lignes(
    toy_desserte(), toy_mnt())))
})
