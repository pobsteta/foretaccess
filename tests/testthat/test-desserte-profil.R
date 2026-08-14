# Profil en travers au clic (spec 030). Le lecteur de nuage (`rlas`) est une
# dependance OPTIONNELLE absente en CI : les tests exercent le REPLI (NULL, jamais
# d'erreur) et toute la geometrie, sur un nuage de SYNTHESE injecte a la place de
# la lecture LAS.
#
# La route de synthese porte les quatre ruptures que les familles doivent
# retrouver : chaussee bombee de 4 m, accotements a 12 %, banquette a 8 %
# (franchissable), talus a 60 % (non franchissable) -- et, au-dessus, un couvert
# ferme QUI RECOUVRE LA ROUTE, avec des troncs a partir de 7 m de l'axe. C'est ce
# dernier point qui verrouille le choix de conception : l'emprise se lit sur les
# troncs, pas sur le couvert.

# Surface de la route de synthese : z(dy), dy = distance signee a l'axe.
.z_route <- function(dy) {
  a <- abs(dy)
  z <- 100 - 0.005 * dy^2 # chaussee bombee (fleche 2 cm a 2 m)
  ep <- 100 - 0.005 * 2^2
  z[a > 2] <- ep - 0.12 * (a[a > 2] - 2) # accotement a 12 %
  eb <- ep - 0.12 * 1
  z[a > 3] <- eb - 0.08 * (a[a > 3] - 3) # banquette a 8 %, franchissable
  et <- eb - 0.08 * 3
  z[a > 6] <- et - 0.60 * (a[a > 6] - 6) # talus a 60 %
  z
}

.mnt_route <- function() {
  r <- terra::rast(xmin = 0, xmax = 60, ymin = 0, ymax = 100,
    resolution = 0.5, crs = "EPSG:2154")
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  terra::values(r) <- .z_route(xy[, 2] - 50)
  names(r) <- "mnt"
  r
}

.desserte_route <- function() {
  sf::st_sf(classe = "piste", largeur = NA_real_,
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(5, 50), c(55, 50))),
      crs = 2154))
}

# Nuage de synthese sur la tranche : points sol sur la surface, couvert ferme
# PARTOUT (y compris au-dessus de la route), troncs a partir de 7 m de l'axe.
.nuage_route <- function(x0 = 30) {
  dy <- seq(-20, 20, by = 0.2)
  xs <- seq(x0 - 1, x0 + 1, by = 0.5)
  g <- expand.grid(X = xs, dy = dy)
  sol <- data.frame(X = g$X, Y = 50 + g$dy, Z = .z_route(g$dy),
    Intensity = 900, Classification = 2L)
  couvert <- data.frame(X = g$X, Y = 50 + g$dy, Z = .z_route(g$dy) + 12,
    Intensity = 150, Classification = 5L)
  tr <- g[abs(g$dy) >= 7, ]
  troncs <- do.call(rbind, lapply(seq(1, 5, by = 1), function(h) {
    data.frame(X = tr$X, Y = 50 + tr$dy, Z = .z_route(tr$dy) + h,
      Intensity = 300, Classification = 5L)
  }))
  out <- rbind(sol, couvert, troncs)
  attr(out, "n_dalles") <- 1L
  out
}

# Profil calcule sur la route de synthese, nuage injecte a la place du LAS.
.profil_synthese <- function(xy = c(30, 52), ...) {
  nuage <- .nuage_route()
  testthat::local_mocked_bindings(
    .las_fichiers = function(las_source) "dalle.laz",
    .lire_nuage_rect = function(fichiers, bbox) nuage
  )
  withr::with_tempdir(
    profil_travers(.desserte_route(), xy, las_source = "nuage", mnt = .mnt_route(),
      cache_dir = "cache", ...)
  )
}


# --- 1. Accrochage -----------------------------------------------------------

test_that("un clic a moins de tolerance_m accroche le troncon, au-dela : NULL", {
  p <- .profil_synthese(c(30, 52))
  expect_type(p, "list")
  expect_s3_class(p$troncon, "sf")
  expect_identical(nrow(p$troncon), 1L)
  expect_identical(p$troncon$classe, "piste")

  # 40 m de l'axe, tolerance 25 : rien ici, et on le DIT (message, pas erreur).
  expect_message(
    loin <- .profil_synthese(c(30, 90)),
    "Aucun troncon"
  )
  expect_null(loin)
})

test_that("la station est la projection du clic sur l'axe", {
  p <- .profil_synthese(c(30, 52))
  expect_equal(p$station$xy, c(30, 50), tolerance = 1e-6)
  expect_equal(p$station$chainage_m, 25, tolerance = 1e-6) # axe de 5 a 55
})


# --- 2. Centrage -------------------------------------------------------------

test_that("x_travers est signe et centre sur l'axe", {
  p <- .profil_synthese()
  expect_lt(min(p$points$x_travers), 0)
  expect_gt(max(p$points$x_travers), 0)
  expect_true(any(abs(p$points$x_travers) < 0.5))
  # L'axe est en 0 : le sol y est a z = 0 par construction du referentiel.
  i0 <- which.min(abs(p$sol$x_travers))
  expect_equal(p$sol$x_travers[i0], 0, tolerance = 1e-9)
  expect_equal(p$sol$z[i0], 0, tolerance = 0.02)
  expect_equal(p$meta$z_ref, 100, tolerance = 0.02)
})

test_that("la tranche est bornee par epaisseur_m et demi_largeur", {
  p <- .profil_synthese(epaisseur_m = 2, demi_largeur = 15)
  expect_lte(max(abs(p$points$abscisse)), 1)
  expect_lte(max(abs(p$points$x_travers)), 15)
  expect_equal(range(p$sol$x_travers), c(-15, 15))
  expect_identical(p$meta$n_points, nrow(p$points))
})


# --- 3. Vocabulaire ----------------------------------------------------------

test_that("bords$type reste dans les cinq cles techniques, non traduites", {
  p <- .profil_synthese()
  expect_true(all(p$bords$type %in% foretaccess:::.TYPES_BORDS))
  expect_setequal(unique(p$bords$type), foretaccess:::.TYPES_BORDS)
  expect_identical(names(p$bords),
    c("type", "cote", "x_gauche", "x_droite", "largeur_m"))
  # Aucun libelle traduit ne doit fuir : l'app traduit, le coeur ne traduit pas.
  expect_false(any(grepl("largeur|emprise|accotement|secours", p$bords$type)))
})


# --- 4. Ordre des familles ---------------------------------------------------

test_that("drivable <= road <= rescue <= right_of_way, par construction", {
  p <- .profil_synthese()
  l <- stats::setNames(p$bords$largeur_m, p$bords$type)
  expect_lte(l[["drivable"]], l[["road"]])
  expect_lte(l[["road"]], l[["rescue"]])
  expect_lte(l[["rescue"]], l[["right_of_way"]])
  # Les bords s'emboitent, pas seulement les largeurs.
  b <- split(p$bords, p$bords$type)
  emboite <- function(dedans, dehors) {
    expect_gte(dedans$x_gauche, dehors$x_gauche)
    expect_lte(dedans$x_droite, dehors$x_droite)
  }
  emboite(b$drivable, b$road)
  emboite(b$road, b$rescue)
  emboite(b$rescue, b$right_of_way)
})

test_that("les bords retrouvent la geometrie de la route de synthese", {
  p <- .profil_synthese()
  l <- stats::setNames(p$bords$largeur_m, p$bords$type)
  # Chaussee de 4 m : la rupture chaussee/accotement (12 %) est resolue.
  expect_gt(l[["drivable"]], 3.5)
  expect_lt(l[["drivable"]], 6)
  # Plateforme = chaussee + accotements, soit environ 6 m.
  expect_gt(l[["road"]], l[["drivable"]])
  expect_lt(l[["road"]], 8)
  # Secours : la banquette a 8 % est franchissable jusqu'au talus, a 6 m.
  expect_gt(l[["rescue"]], 9)
  expect_lt(l[["rescue"]], 13)
  # Emprise : les troncs sont a 7 m, soit environ 13,5 m de couloir -- et le
  # couvert ferme AU-DESSUS de la route ne la reduit pas.
  expect_gt(l[["right_of_way"]], 12)
  expect_lt(l[["right_of_way"]], 15)
  # Deux accotements, un par cote, jamais negatifs.
  ac <- p$bords[p$bords$type == "shoulder", ]
  expect_identical(sort(ac$cote), c("droite", "gauche"))
  expect_true(all(ac$largeur_m >= 0))
  expect_equal(sum(ac$largeur_m), l[["road"]] - l[["drivable"]], tolerance = 1e-9)
})

test_that("un couvert ferme au-dessus de la route ne ferme pas l'emprise", {
  # Regression de conception : lire l'emprise sur le COUVERT rendrait ici une
  # trouee nulle (les houppiers recouvrent la route) et une emprise egale a la
  # plateforme. C'est ce qu'on a mesure sur la dalle d'exemple dessertR.
  p <- .profil_synthese()
  b <- split(p$bords, p$bords$type)
  h <- p$points$hauteur_sol
  expect_true(any(is.finite(h) & h > 10 & abs(p$points$x_travers) < 1))
  expect_gt(b$right_of_way$largeur_m, 2 * b$road$largeur_m)
})

test_that("la parabole ajustee retrouve le bombement de la chaussee", {
  p <- .profil_synthese()
  expect_type(p$ajustement, "list")
  # Le bombement est retrouve au millieme pres : l'ajustement porte sur la bande
  # roulable, qui mord un peu sur l'accotement -- il cambre donc legerement.
  # (-0,0096 mesure pour -0,005 vrai : la bande roulable deborde de 0,5 m sur
  # l'accotement, l'ajustement se cambre d'autant. C'est le bon ordre de
  # grandeur, pas une mesure de bombement au millimetre.)
  expect_lt(abs(p$ajustement$a - (-0.005)), 0.008)
  expect_lt(abs(p$ajustement$b), 0.01)
  expect_lt(p$ajustement$rmse, 0.05)
  expect_identical(p$ajustement$source, "points_sol")
})


# --- 5. Degrade --------------------------------------------------------------

test_that("sans dalle LiDAR : NULL, un message, aucune erreur", {
  expect_message(
    p <- withr::with_tempdir(profil_travers(.desserte_route(), c(30, 52),
      las_source = tempfile(), mnt = .mnt_route(), cache_dir = "cache")),
    "Aucune dalle"
  )
  expect_null(p)
})

test_that("sans rlas : NULL et un avertissement, pas une erreur", {
  testthat::local_mocked_bindings(
    .las_fichiers = function(las_source) "dalle.laz",
    .rlas_dispo = function() FALSE
  )
  expect_warning(
    p <- withr::with_tempdir(profil_travers(.desserte_route(), c(30, 52),
      las_source = "nuage", mnt = .mnt_route(), cache_dir = "cache")),
    "rlas"
  )
  expect_null(p)
})

test_that("coupe vide (nuage hors tranche) : NULL, pas une liste a moitie pleine", {
  testthat::local_mocked_bindings(
    .las_fichiers = function(las_source) "dalle.laz",
    .lire_nuage_rect = function(fichiers, bbox) {
      data.frame(X = 30, Y = 200, Z = 100, Intensity = 1, Classification = 2L)
    }
  )
  expect_message(
    p <- withr::with_tempdir(profil_travers(.desserte_route(), c(30, 52),
      las_source = "nuage", mnt = .mnt_route(), cache_dir = "cache")),
    "Coupe vide"
  )
  expect_null(p)
})

test_that("un CRS de clic different de la desserte est refuse, pas reprojete", {
  expect_error(
    profil_travers(.desserte_route(), c(3, 45), las_source = ".",
      mnt = .mnt_route(), crs = 4326),
    "CRS"
  )
})


# --- Cache -------------------------------------------------------------------

test_that("le second clic identique sort du cache", {
  nuage <- .nuage_route()
  testthat::local_mocked_bindings(
    .las_fichiers = function(las_source) "dalle.laz",
    .lire_nuage_rect = function(fichiers, bbox) nuage
  )
  withr::with_tempdir({
    a <- profil_travers(.desserte_route(), c(30, 52), "nuage", .mnt_route(),
      cache_dir = "cache")
    b <- profil_travers(.desserte_route(), c(30, 52), "nuage", .mnt_route(),
      cache_dir = "cache")
    expect_false(a$meta$cache)
    expect_true(b$meta$cache)
    expect_identical(a$bords, b$bords)
    expect_identical(length(list.files("cache/profil_travers")), 1L)
  })
})

test_that("changer un seuil de bord change la cle de cache", {
  # Un cache indexe sur le seul clic servirait un profil calcule avec d'autres
  # reglages a qui vient justement de les changer (spec 027).
  pt <- sf::st_sfc(sf::st_point(c(30, 52)), crs = 2154)
  base <- foretaccess:::.cle_profil(pt, 20, 2, 0.25, 25, c(0.5, 5), 0.2, 0.05, 0.15)
  expect_false(base ==
    foretaccess:::.cle_profil(pt, 20, 2, 0.25, 25, c(0.5, 5), 0.2, 0.10, 0.15))
  expect_false(base ==
    foretaccess:::.cle_profil(pt, 20, 2, 0.25, 25, c(2, 5), 0.2, 0.05, 0.15))
  expect_false(base ==
    foretaccess:::.cle_profil(pt, 20, 2, 0.25, 40, c(0.5, 5), 0.2, 0.05, 0.15))
  # Le nom reste un nom de fichier valide, sans caractere a echapper.
  expect_match(base, "^[0-9A-Za-z_.-]+$")
})


# --- Helpers geometriques ----------------------------------------------------

test_that(".station_sur_axe projette et chaine correctement", {
  co <- rbind(c(0, 0), c(10, 0), c(10, 10))
  s <- foretaccess:::.station_sur_axe(co, c(4, 3))
  expect_equal(s$xy, c(4, 0))
  expect_equal(s$chainage, 4)
  s2 <- foretaccess:::.station_sur_axe(co, c(13, 6))
  expect_equal(s2$xy, c(10, 6))
  expect_equal(s2$chainage, 16)
})

test_that(".tangente_a_chainage lisse la quantification des sommets", {
  # Axe globalement E-O, avec un zigzag decimetrique de numerisation.
  co <- cbind(seq(0, 20, by = 1), rep(c(0, 0.1), length.out = 21))
  tg <- foretaccess:::.tangente_a_chainage(co, 10, base = 5)
  expect_equal(tg[1], 1, tolerance = 0.01)
  expect_lt(abs(tg[2]), 0.05)
})

test_that(".plage_ecart interpole le bord entre deux echantillons", {
  x <- seq(-5, 5, by = 1)
  # Plat jusqu'a |x| = 2, puis pente de 0,2 m par metre.
  z <- ifelse(abs(x) <= 2, 0, -0.2 * (abs(x) - 2))
  b <- foretaccess:::.plage_ecart(x, z, rep(0, length(x)), tol = 0.1)
  expect_equal(b, c(-2.5, 2.5), tolerance = 1e-9)
})

test_that(".plage_libre rend la plage centree libre d'occupation", {
  # Bord conservateur : borne INTERIEURE de la case contenant l'echo (0,5 m).
  b <- foretaccess:::.plage_libre(c(-6, 6, 7), demi_largeur = 10, pas = 0.5)
  expect_equal(b, c(-5.5, 5.5), tolerance = 1e-9)
  # Occupation a l'axe meme : plage nulle, jamais negative.
  expect_equal(foretaccess:::.plage_libre(0, 10, 0.5), c(0, 0))
  # Aucune occupation : toute la fenetre.
  expect_equal(foretaccess:::.plage_libre(numeric(0), 10, 0.5), c(-10, 10))
})

test_that(".ajuster_parabole retrouve les coefficients, NULL si trop peu", {
  x <- seq(-3, 3, by = 0.25)
  p <- foretaccess:::.ajuster_parabole(x, 2 - 0.05 * x^2 + 0.1 * x)
  expect_equal(c(p$a, p$b, p$c), c(-0.05, 0.1, 2), tolerance = 1e-8)
  expect_lt(p$rmse, 1e-8)
  expect_null(foretaccess:::.ajuster_parabole(c(0, 1), c(0, 1)))
})

test_that(".las_fichiers accepte dossier, fichiers et catalogue", {
  withr::with_tempdir({
    dir.create("dalles")
    file.create(c("dalles/a.laz", "dalles/b.LAS", "dalles/notes.txt"))
    expect_setequal(basename(foretaccess:::.las_fichiers("dalles")),
      c("a.laz", "b.LAS"))
    expect_identical(basename(foretaccess:::.las_fichiers("dalles/a.laz")), "a.laz")
    cat <- data.frame(laz = c("dalles/a.laz", "dalles/absente.laz"))
    expect_identical(basename(foretaccess:::.las_fichiers(cat)), "a.laz")
    expect_identical(foretaccess:::.las_fichiers(NULL), character(0))
  })
})

test_that(".dalles_intersectant garde une dalle a l'entete illisible", {
  # Entete illisible -> on ne l'ecarte pas en silence : le filtre de lecture
  # tranchera. Une dalle ecartee a tort est un profil vide inexplicable.
  withr::with_tempdir({
    file.create("fausse.laz")
    expect_identical(
      foretaccess:::.dalles_intersectant("fausse.laz", c(0, 0, 1, 1)),
      "fausse.laz"
    )
  })
})
