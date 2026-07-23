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

# MNT a 3 % : toute la desserte reste sous le seuil de pente EN LONG par defaut
# (6 %), la planeite n'ecarte rien.
mnt_doux <- function() mnt_plan(pente = 0.03, n = 50, res = 5)

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

test_that("ni la classe ni le flag dfci ne rejettent (confrontation ColduPre)", {
  # Trouve sur l'oracle : l'une des deux vraies places de depot de ColduPre est
  # une PISTE forestiere a CL_DFCI = 0. Rejeter sur ces attributs elimine une
  # vraie place sur deux -- ils informent, ils ne tranchent pas.
  places <- places_serrees(desserte_depot(
    classe = c("route", "piste", "dfci", "route"), dfci = c(1L, 0L, 0L, 0L)
  ))
  expect_true(2L %in% places$troncon) # la piste non DFCI survit
  expect_setequal(unique(places$troncon), 1:4)
  # ... mais les attributs sont rapportes.
  expect_equal(unique(places$acces[places$troncon == 1L]), "dfci")
  expect_equal(unique(places$acces[places$troncon == 2L]), "classe:piste")
})

test_that("seule une largeur mesuree et insuffisante rejette", {
  etroite <- places_serrees(
    desserte_depot(classe = "route", largeur = c(2, 6, 6, 6)),
    largeur_min_m = 4
  )
  expect_false(1L %in% etroite$troncon)
  expect_setequal(unique(etroite$troncon), c(2L, 3L, 4L))
  expect_true(all(etroite$acces == "largeur"))
})

test_that("places_depot compose avec la largeur LiDAR (largeur_carrossable_m)", {
  # qualifier_desserte()/acquire_desserte_lidar() sortent `largeur_carrossable_m` ;
  # places_depot doit la reconnaitre comme largeur mesuree (B2, brief foretaccess).
  etroite <- places_serrees(
    desserte_depot(classe = "route", largeur_carrossable_m = c(2, 6, 6, 6)),
    largeur_min_m = 4
  )
  expect_false(1L %in% etroite$troncon) # 2 m < 4 m -> rejete
  expect_true(all(etroite$acces == "largeur"))
})

test_that("largeur_champ force la colonne de largeur", {
  # Une colonne au nom non standard n'est lue que si on la nomme explicitement.
  des <- desserte_depot(classe = "route", ma_largeur = c(2, 6, 6, 6))
  # Sans largeur_champ : aucune largeur mesuree -> rien n'est rejete sur l'acces.
  sans <- suppressMessages(places_serrees(des, largeur_min_m = 4))
  expect_true(all(sans$acces != "largeur"))
  # Avec largeur_champ : le troncon etroit (2 m) est ecarte.
  avec <- places_serrees(des, largeur_min_m = 4, largeur_champ = "ma_largeur")
  expect_false(1L %in% avec$troncon)
  expect_true(all(avec$acces == "largeur"))
})

test_that("une desserte sans largeur mesuree ne se fait pas filtrer sur l'acces", {
  expect_message(
    places <- places_depot(desserte_depot(), mnt_doux(), espacement_min_m = 10),
    "Aucune largeur mesuree"
  )
  expect_true(all(places$acces == "indetermine"))
  expect_setequal(unique(places$troncon), 1:4)
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

test_that("la pente en long ecarte les routes qui montent", {
  # Le plan monte vers l'est : les troncons du triangle la remontent, de 42 a
  # 60 % EN LONG. Aucun ne passe le seuil par defaut.
  raide <- function() mnt_plan(pente = 0.6, n = 50, res = 5)
  expect_error(
    suppressMessages(places_depot(desserte_depot(classe = "route"), raide())),
    "planeite"
  )
  # Seuil releve : les memes troncons passent.
  places <- suppressMessages(places_depot(
    desserte_depot(classe = "route"), raide(), pente_max_pct = 70
  ))
  expect_gt(nrow(places), 0)
  expect_true(all(places$pente_pct <= 70))
})

test_that("une route de niveau sur un versant raide est RETENUE (regression v1.6.0)", {
  # Le bug de la v1.6.0 : la planeite etait mesuree par la pente omnidirection-
  # nelle du MNT, donc par le VERSANT. Sur ColduPre, l'une des deux vraies places
  # de depot est sur un versant a 65 % -- le troncon le plus raide du reseau --
  # et etait ecartee. Une route de niveau a 0 % en long doit passer, quel que
  # soit le versant qu'elle traverse.
  versant <- mnt_plan(pente = 0.6, n = 50, res = 5) # versant a 60 %
  niveau <- sf::st_sf(
    classe = "route",
    geometry = sf::st_sfc(
      sf::st_linestring(rbind(c(125, 25), c(125, 225))), # plein nord : x constant
      crs = 2154
    )
  )
  places <- suppressMessages(places_depot(niveau, versant, espacement_min_m = 50))
  expect_gt(nrow(places), 0)
  expect_true(all(places$pente_pct < 1)) # de niveau, malgre les 60 % de versant

  # Et la pente du MNT sous cette route vaut bien ~60 % : c'est ce que l'ancienne
  # version mesurait, et pourquoi elle rejetait.
  pente_mnt <- terra::extract(
    calculer_terrain(versant)$slope_pct, terra::vect(places)
  )[, 2]
  expect_true(all(pente_mnt > 50))
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

test_that("l'espacement vaut LE LONG d'un troncon, pas entre troncons", {
  # Trouve sur l'oracle ColduPre : un eclaircissement glouton inter-troncons
  # evincait les DEUX vraies places de depot, chacune battue par un point plus
  # plat a 18 m et 93 m sur une route voisine. On espace donc le long d'une
  # ligne, jamais entre lignes.
  for (esp in c(50, 120)) {
    places <- suppressMessages(places_depot(
      desserte_depot(classe = "route"), mnt_doux(), espacement_min_m = esp
    ))
    for (t in unique(places$troncon)) {
      p <- places[places$troncon == t, ]
      if (nrow(p) < 2) next
      m <- matrix(as.numeric(sf::st_distance(p)), nrow(p))
      expect_true(all(m[upper.tri(m)] >= esp * 0.99))
    }
  }
})

test_that("chaque troncon retenu garde au moins une place", {
  # Corollaire du point precedent : aucun troncon ne disparait parce qu'un
  # voisin est mieux place.
  places <- suppressMessages(places_depot(
    desserte_depot(classe = "route"), mnt_doux(), espacement_min_m = 5000
  ))
  expect_setequal(unique(places$troncon), 1:4)
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
  # Le troncon 2 est trop etroit (largeur mesuree) : seul lui doit manquer.
  tr <- suppressMessages(places_depot(
    desserte_depot(classe = "route", largeur = c(6, 2, 6, 6)), mnt_doux(),
    espacement_min_m = 10, sortie = "troncons"
  ))
  expect_true(all(sf::st_geometry_type(tr) == "LINESTRING"))
  expect_setequal(
    names(sf::st_drop_geometry(tr)),
    c("troncon", "cable", "acces", "largeur_m", "pente_pct", "n_places")
  )
  expect_false(2L %in% tr$troncon)
  expect_setequal(tr$troncon, c(1L, 3L, 4L))
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

test_that("les troncons de longueur nulle sont ecartes (ColduPre en contient)", {
  # Le reseau ColduPre porte des troncons de longueur 0 m : ni abscisse, ni
  # pente en long. Ils doivent etre ecartes proprement, avec un message.
  nul <- sf::st_linestring(rbind(c(125, 125), c(125, 125)))
  des <- desserte_depot(classe = "route")
  des <- rbind(
    des,
    sf::st_sf(classe = "route", geometry = sf::st_sfc(nul, crs = 2154))
  )
  expect_message(
    places <- places_depot(des, mnt_doux(), espacement_min_m = 10),
    "longueur nulle"
  )
  # Le troncon nul (5e) est absent ; les 4 autres restent.
  expect_false(5L %in% places$troncon)
  expect_setequal(unique(places$troncon), 1:4)
})

test_that("une desserte reduite a des troncons nuls est refusee", {
  nul <- sf::st_sfc(
    sf::st_linestring(rbind(c(0, 0), c(0, 0))),
    sf::st_linestring(rbind(c(5, 5), c(5, 5))),
    crs = 2154
  )
  des <- sf::st_sf(classe = "route", geometry = nul)
  expect_error(
    suppressMessages(places_depot(des, mnt_doux())),
    "longueur non nulle"
  )
})

test_that("un critere qui elimine tout est une erreur actionnable", {
  expect_error(
    suppressMessages(places_depot(
      desserte_depot(classe = "route", largeur = 2), mnt_doux()
    )),
    "acces camion"
  )
})

# --- Non-regression sur l'oracle ColduPre ------------------------------------
# La couche de desserte du jeu officiel Sylvaccess porte l'attribut CABLE : la
# VERITE TERRAIN des places de depot (2 troncons sur 125). C'est le seul oracle
# dont on dispose, et il a invalide la v1.6.0 (rappel 0/2). Opt-in : le jeu vit
# hors du depot (cf. data-raw/oracle_places_depot.R).

coldupre_input <- function() {
  d <- file.path(path.expand(Sys.getenv("SYLVA", "~/dev/sylvaccess-upstream")),
    "test", "ColduPre", "Input")
  if (!file.exists(file.path(d, "forest_roadnetwork.gpkg"))) {
    testthat::skip("jeu ColduPre absent (definir SYLVA)")
  }
  d
}

test_that("les 2 vraies places de depot de ColduPre sont retrouvees (CA-depot.1)", {
  IN <- coldupre_input()
  res <- sf::st_read(file.path(IN, "forest_roadnetwork.gpkg"), quiet = TRUE)
  mnt <- terra::rast(file.path(IN, "mnt.tif"))
  vrai <- which(res$CABLE != 0)
  expect_length(vrai, 2) # l'oracle est bien celui qu'on croit

  res$dfci <- res$CL_DFCI
  res$classe <- c(
    "Route forestiere" = "route", "Piste forestiere" = "piste",
    "Reseau public" = "route"
  )[res$TYPE_FR]

  places <- suppressMessages(places_depot(res, mnt))
  retenus <- unique(places$troncon)

  # Rappel : les deux, sans exception.
  expect_true(all(vrai %in% retenus))
  # Precision : mediocre par nature (~4 %), mais le pre-filtre doit filtrer --
  # sinon il ne sert a rien. La v1.6.0 sans seuil en gardait 86 %.
  expect_lt(length(retenus), 0.6 * nrow(res))
})

test_that("ColduPre : la pente du MNT aurait rejete une vraie place, pas la pente en long", {
  IN <- coldupre_input()
  res <- sf::st_read(file.path(IN, "forest_roadnetwork.gpkg"), quiet = TRUE)
  mnt <- terra::rast(file.path(IN, "mnt.tif"))
  vrai <- which(res$CABLE != 0)

  # Le versant sous les vraies places : 24 % et 65 %. C'est ce que mesurait la
  # v1.6.0, et pourquoi elle les rejetait toutes les deux.
  versant <- terra::extract(calculer_terrain(mnt)$slope_pct,
    terra::vect(res[vrai, ]), fun = stats::median, na.rm = TRUE)[, 2]
  expect_true(all(versant > 20))
  expect_true(any(versant > 60))

  # La pente en long des memes troncons : quelques pourcents.
  lg <- as.numeric(sf::st_length(res[vrai, ]))
  z <- t(vapply(sf::st_geometry(res[vrai, ]), function(g) {
    m <- sf::st_coordinates(g)[, 1:2, drop = FALSE]
    as.numeric(terra::extract(mnt, rbind(m[1, ], m[nrow(m), ]))[, 1])
  }, numeric(2)))
  en_long <- 100 * abs(z[, 2] - z[, 1]) / lg
  expect_true(all(en_long < 6))
})
