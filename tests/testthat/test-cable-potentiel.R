# Orchestration cable (Lot 4d) : potentiel_cable() balaie 360 deg / pixel depuis
# la desserte, extrait le profil MNT, evalue une ligne 0 support (noyau Rust) et
# marque les cellules forestieres couvertes. Teste sur un plan incline (MNT
# synthetique) avec une desserte-point et un lmax reduit (rapidite).

# Config cable a courte portee pour un balayage rapide.
config_cable_court <- function() {
  foretaccess_config(cable = list(longueur_max_m = 60, longueur_min_m = 20))
}

# Pretraitement : plan incline (altitude croissante vers l'est), foret pleine,
# desserte-point a fournir.
pre_cable <- function(x_dep, y_dep, pente = 0.2, n = 25, res = 5) {
  mnt <- mnt_plan(pente = pente, n = n, res = res)
  d0 <- sf::st_sf(classe = "route",
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(res, res), c(2 * res, res))), crs = 2154))
  pre <- preprocess(mnt = mnt, desserte = d0, foret = foret_pleine(mnt))
  pre$desserte <- desserte_point(mnt, x_dep, y_dep)
  pre
}

test_that("potentiel_cable renvoie un objet cable structure", {
  pre <- pre_cable(x_dep = 105, y_dep = 62.5)
  ca <- potentiel_cable(pre, config_cable_court())

  expect_s3_class(ca, "foretaccess_cable")
  expect_true(terra::is.factor(ca$accessibilite))
  expect_setequal(
    terra::levels(ca$accessibilite)[[1]]$classe,
    c("accessible_cable", "non_accessible", "hors_foret")
  )
})

test_that("des cellules forestieres sont accessibles au cable, bornees par lmax", {
  x_dep <- 105
  y_dep <- 62.5
  pre <- pre_cable(x_dep = x_dep, y_dep = y_dep)
  ca <- potentiel_cable(pre, config_cable_court())

  codes <- terra::values(ca$accessibilite)
  acc <- which(codes == 1L) # accessible_cable
  expect_gt(length(acc), 0)

  # Toutes les cellules accessibles sont a moins de longueur_max_m du depart.
  xy <- terra::xyFromCell(ca$accessibilite, acc)
  dist <- sqrt((xy[, 1] - x_dep)^2 + (xy[, 2] - y_dep)^2)
  expect_true(all(dist <= 60 + 5)) # + une cellule de tolerance
})

test_that("une cellule hors de portee n'est pas accessible", {
  x_dep <- 105
  y_dep <- 62.5
  pre <- pre_cable(x_dep = x_dep, y_dep = y_dep)
  ca <- potentiel_cable(pre, config_cable_court())

  # Coin oppose (bas-gauche), a plus de 60 m : non accessible.
  loin <- terra::cellFromXY(ca$accessibilite, cbind(15, 15))
  expect_equal(terra::values(ca$accessibilite)[loin], 3L) # non_accessible
})

test_that("la longueur de ligne est renseignee sur les cellules accessibles", {
  pre <- pre_cable(x_dep = 105, y_dep = 62.5)
  ca <- potentiel_cable(pre, config_cable_court())

  codes <- terra::values(ca$accessibilite)
  lg <- terra::values(ca$longueur_ligne)
  acc <- codes == 1L
  expect_true(all(!is.na(lg[acc])))
  expect_true(all(is.na(lg[!acc])))
  # Longueur dans [longueur_min, longueur_max].
  expect_true(all(lg[acc] >= 20 & lg[acc] <= 60))
})

test_that("sans desserte, potentiel_cable leve une erreur", {
  pre <- pre_cable(x_dep = 105, y_dep = 62.5)
  vide <- terra::rast(pre$mnt)
  terra::values(vide) <- NA_real_ # desserte sans aucune cellule
  pre$desserte <- vide
  expect_error(potentiel_cable(pre, config_cable_court()), "desserte")
})

# --- Places de depot (couche `departs`) --------------------------------------
# Trouve par confrontation a l'oracle : Sylvaccess ne lance ses lignes que depuis
# une couche de depart dediee, filtree sur l'attribut CABLE (2 troncons sur 125
# a ColduPre). Partir de TOUTE la desserte rend la couverture massivement trop
# optimiste -- une piste n'accueille pas un cable-mat.

test_that("sans `departs`, on retombe sur la desserte, et on le dit", {
  pre <- pre_cable(x_dep = 105, y_dep = 62.5)
  expect_message(
    potentiel_cable(pre, config_cable_court()),
    "places de depot"
  )
})

test_that("`departs` restreint le balayage aux seules places de depot", {
  # Desserte pleine (une ligne traversante) vs une place de depot ponctuelle :
  # la couverture doit etre strictement plus petite avec la place de depot.
  mnt <- mnt_plan(pente = 0.2, n = 25, res = 5)
  ligne <- sf::st_sf(
    classe = "route",
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(12.5, 12.5), c(12.5, 112.5))), crs = 2154)
  )
  pre <- preprocess(mnt = mnt, desserte = ligne, foret = foret_pleine(mnt))

  place <- sf::st_sf(
    cable = 1L,
    geometry = sf::st_sfc(sf::st_point(c(12.5, 62.5)), crs = 2154)
  )

  couvre <- function(ca) sum(terra::values(ca$accessibilite) ==
    terra::levels(ca$accessibilite)[[1]]$value[
      terra::levels(ca$accessibilite)[[1]]$classe == "accessible_cable"
    ], na.rm = TRUE)

  tout <- suppressMessages(potentiel_cable(pre, config_cable_court()))
  depuis_place <- potentiel_cable(pre, config_cable_court(), departs = place)

  expect_lt(couvre(depuis_place), couvre(tout))
  expect_gt(couvre(depuis_place), 0)
})

test_that("le champ `cable` filtre les entites non cable-aptes", {
  pre <- pre_cable(x_dep = 105, y_dep = 62.5)
  # Deux places, une seule cable-apte.
  places <- sf::st_sf(
    cable = c(0L, 1L),
    geometry = sf::st_sfc(
      sf::st_point(c(105, 32.5)),
      sf::st_point(c(105, 62.5)),
      crs = 2154
    )
  )
  ca <- potentiel_cable(pre, config_cable_court(), departs = places)
  # Seule la place cable-apte a servi de depart.
  expect_setequal(unique(ca$lignes$depart), terra::cellFromXY(pre$mnt, cbind(105, 62.5)))

  toutes_nulles <- sf::st_sf(cable = c(0L, 0L), geometry = sf::st_geometry(places))
  expect_error(
    potentiel_cable(pre, config_cable_court(), departs = toutes_nulles),
    "cable-apte"
  )
})

test_that("`departs` exige un CRS et refuse la reprojection implicite", {
  pre <- pre_cable(x_dep = 105, y_dep = 62.5)
  sans_crs <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(105, 62.5))))
  expect_error(potentiel_cable(pre, config_cable_court(), departs = sans_crs), "CRS")

  autre_crs <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(6, 45)), crs = 4326))
  expect_error(potentiel_cable(pre, config_cable_court(), departs = autre_crs), "CRS")
})
