# Places de depot (entree `departs` du moteur cable) : `places_depot()` derive des
# CANDIDATES de la desserte par des criteres verifiables sur la donnee (acces
# camion, demi-tour, planeite, proximite de la foret), puis les espace. Chaque
# critere est teste isolement : ce qui passe, et ce qui est ecarte.

# Desserte de test : un triangle ferme (troncons 1-3, tous TRAVERSANTS -- leurs
# deux extremites sont raccordees) et une impasse isolee (troncon 4, deux bouts
# pendants). Attributs a la carte pour tester l'ordre des preuves d'acces.
desserte_depot <- function(...) {
  ligne <- function(m) sf::st_linestring(m)
  g <- sf::st_sfc(
    ligne(rbind(c(25, 125), c(125, 225))),  # 1 : traversante
    ligne(rbind(c(125, 225), c(225, 125))), # 2 : traversante
    ligne(rbind(c(225, 125), c(25, 125))),  # 3 : traversante
    ligne(rbind(c(60, 30), c(160, 30))),    # 4 : impasse isolee
    crs = 2154
  )
  sf::st_sf(..., geometry = g)
}

foret_carre <- function(xmin, ymin, xmax, ymax) {
  sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(rbind(
    c(xmin, ymin), c(xmax, ymin), c(xmax, ymax), c(xmin, ymax), c(xmin, ymin)
  ))), crs = 2154))
}

# MNT a 5 % : toute la desserte est constructible, la pente n'ecarte rien.
mnt_doux <- function() mnt_plan(pente = 0.05, n = 50, res = 5)

# Les tests de CRITERE passent un espacement serre : c'est l'appartenance des
# troncons qu'ils verifient, pas l'eclaircissement (teste a part).
places_serrees <- function(des, ...) {
  suppressMessages(places_depot(des, mnt_doux(), espacement_min_m = 10, ...))
}

test_that("places_depot renvoie un sf de points portant le champ `cable`", {
  places <- suppressMessages(places_depot(
    desserte_depot(classe = "route"),
    mnt_doux()
  ))

  expect_s3_class(places, "sf")
  expect_true(all(sf::st_geometry_type(places) == "POINT"))
  expect_setequal(
    names(sf::st_drop_geometry(places)),
    c("id", "cable", "troncon", "acces", "largeur_m", "pente_pct")
  )
  expect_true(all(places$cable == 1L))
  expect_equal(sf::st_crs(places), sf::st_crs(2154))
})

test_that("la couche produite alimente directement potentiel_cable()", {
  mnt <- mnt_doux()
  des <- desserte_depot(classe = "route")
  foret <- foret_carre(0, 0, 250, 250)

  places <- suppressMessages(places_depot(des, mnt, espacement_min_m = 150))
  pre <- preprocess(mnt = mnt, desserte = des, foret = foret)
  cfg <- foretaccess_config(cable = list(longueur_max_m = 60, longueur_min_m = 20))

  # Aucun message de repli : la couche de places de depot est bien prise.
  expect_silent(ca <- potentiel_cable(pre, cfg, departs = places))
  expect_s3_class(ca, "foretaccess_cable")
})

# --- Critere 1 : acces camion -----------------------------------------------

test_that("la classe ecarte les pistes, retient routes et DFCI", {
  places <- places_serrees(desserte_depot(
    classe = c("route", "piste", "dfci", "route")
  ))
  expect_setequal(unique(places$troncon), c(1L, 3L, 4L))
  expect_true(all(places$acces == "classe"))
})

test_that("la largeur prime sur la classe, et le flag dfci sur la classe", {
  # Largeur connue et insuffisante : la route est ecartee malgre sa classe.
  etroite <- places_serrees(
    desserte_depot(classe = "route", largeur = c(2, 6, 6, 6)),
    largeur_min_m = 4
  )
  expect_false(1L %in% etroite$troncon)
  expect_true(all(etroite$acces == "largeur"))

  # Pas de largeur : le flag DFCI decide avant la classe.
  flag <- places_serrees(desserte_depot(classe = "piste", dfci = c(1L, 0L, 0L, 0L)))
  expect_setequal(unique(flag$troncon), 1L)
  expect_true(all(flag$acces == "dfci"))
})

test_that("une desserte sans attribut d'acces passe le filtre, mais on le dit", {
  expect_message(
    places <- places_depot(desserte_depot(), mnt_doux(), espacement_min_m = 10),
    "sans attribut d'acces"
  )
  expect_true(all(places$acces == "indetermine"))
})

# --- Critere 2 : demi-tour ---------------------------------------------------

test_that("sans couche de retournements, le critere de demi-tour n'est pas applique", {
  expect_message(
    places <- places_depot(
      desserte_depot(classe = "route"), mnt_doux(), espacement_min_m = 10
    ),
    "demi-tour n'est pas applique"
  )
  # L'impasse (troncon 4) survit : on ne devine pas ce qu'on n'a pas releve.
  expect_true(4L %in% places$troncon)
})

test_that("avec des retournements, l'impasse sans aire de retournement est ecartee", {
  # Aire de retournement au bout ouest de l'impasse seulement.
  ret <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(60, 30)), crs = 2154))
  places <- places_serrees(
    desserte_depot(classe = "route"),
    retournements = ret, rayon_retournement_m = 20
  )
  # Le triangle passe (traversant), l'impasse aussi : son bout pendant porte une
  # aire de retournement.
  expect_setequal(unique(places$troncon), c(1L, 2L, 3L, 4L))

  # Aire deplacee hors de portee : l'impasse tombe, le triangle reste.
  loin <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(60, 200)), crs = 2154))
  sans <- places_serrees(
    desserte_depot(classe = "route"),
    retournements = loin, rayon_retournement_m = 20
  )
  expect_false(4L %in% sans$troncon)
  expect_setequal(unique(sans$troncon), c(1L, 2L, 3L))
})

# --- Critere 3 : plateforme --------------------------------------------------

test_that("la pente ecarte les plateformes en devers", {
  # MNT a 60 % : aucune plateforme sous le seuil par defaut.
  expect_error(
    suppressMessages(places_depot(
      desserte_depot(classe = "route"), mnt_plan(pente = 0.6, n = 50, res = 5)
    )),
    "planeite"
  )
  # Seuil releve : les memes troncons passent.
  places <- suppressMessages(places_depot(
    desserte_depot(classe = "route"), mnt_plan(pente = 0.6, n = 50, res = 5),
    pente_max_pct = 70
  ))
  expect_gt(nrow(places), 0)
  expect_true(all(places$pente_pct <= 70))
})

# --- Critere 4 : proximite de la foret ---------------------------------------

test_that("les places loin de toute foret sont ecartees", {
  # Foret au nord seulement : l'impasse (y = 30) est trop loin.
  nord <- foret_carre(0, 100, 250, 250)
  places <- places_serrees(
    desserte_depot(classe = "route"),
    foret = nord, distance_foret_max_m = 20
  )
  expect_false(4L %in% places$troncon)
  expect_true(any(places$troncon %in% c(1L, 2L, 3L)))

  expect_error(
    suppressMessages(places_depot(
      desserte_depot(classe = "route"), mnt_doux(),
      foret = foret_carre(0, 240, 10, 250), distance_foret_max_m = 5
    )),
    "proximite de la foret"
  )
})

# --- Espacement --------------------------------------------------------------

test_that("deux places retenues sont distantes d'au moins espacement_min_m", {
  for (esp in c(50, 120)) {
    places <- suppressMessages(places_depot(
      desserte_depot(classe = "route"), mnt_doux(), espacement_min_m = esp
    ))
    m <- matrix(as.numeric(sf::st_distance(places)), nrow(places))
    expect_true(all(m[upper.tri(m)] >= esp))
  }
})

test_that("un espacement plus serre donne plus de places", {
  n <- function(esp) {
    nrow(suppressMessages(places_depot(
      desserte_depot(classe = "route"), mnt_doux(), espacement_min_m = esp
    )))
  }
  expect_gt(n(40), n(120))
})

# --- Sortie troncons ---------------------------------------------------------

test_that("sortie = 'troncons' renvoie les lignes porteuses", {
  tr <- suppressMessages(places_depot(
    desserte_depot(classe = c("route", "piste", "route", "route")), mnt_doux(),
    espacement_min_m = 10, sortie = "troncons"
  ))
  expect_true(all(sf::st_geometry_type(tr) == "LINESTRING"))
  expect_setequal(
    names(sf::st_drop_geometry(tr)),
    c("troncon", "cable", "acces", "largeur_m", "pente_pct", "n_places")
  )
  expect_false(2L %in% tr$troncon)
  expect_true(all(tr$n_places >= 1L))
})

# --- Garde-fous --------------------------------------------------------------

test_that("le CRS doit correspondre a celui du MNT, sans reprojection implicite", {
  des <- desserte_depot(classe = "route")
  sans_crs <- sf::st_set_crs(des, NA)
  expect_error(places_depot(sans_crs, mnt_doux()), "CRS")

  autre <- sf::st_transform(des, 4326)
  expect_error(places_depot(autre, mnt_doux()), "CRS")

  foret_4326 <- sf::st_transform(foret_carre(0, 0, 250, 250), 4326)
  expect_error(
    suppressMessages(places_depot(des, mnt_doux(), foret = foret_4326)),
    "CRS"
  )
})

test_that("une desserte vide ou non lineaire est refusee", {
  vide <- desserte_depot(classe = "route")[0, ]
  expect_error(places_depot(vide, mnt_doux()), "vide")

  points <- sf::st_sf(
    classe = "route",
    geometry = sf::st_sfc(sf::st_point(c(125, 125)), crs = 2154)
  )
  expect_error(places_depot(points, mnt_doux()), "couche de lignes")
})

test_that("un critere qui elimine tout est une erreur actionnable", {
  expect_error(
    suppressMessages(places_depot(
      desserte_depot(classe = "piste"), mnt_doux()
    )),
    "acces camion"
  )
})
