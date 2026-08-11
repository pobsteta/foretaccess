# Spec 029 -- cout de terrassement. On teste contre la FORME FERMEE, pas contre
# une sortie de reference : sur un profil en travers plan, les sections en
# deblai et en remblai s'ecrivent analytiquement, et c'est le meme oracle que
# celui des tests de cubature de dessertR.

# Sections attendues sur un plan de pente `p`, plateforme `L`, talus `A` et `B`,
# ripage nul.
attendu_plan <- function(p, L, A, B) {
  d0 <- p * L / 2
  list(deblai  = p * L^2 / 8 + 0.5 * d0^2 / (A - p),
       remblai = p * L^2 / 8 + 0.5 * d0^2 / (B - p))
}

test_that("sous le seuil de ripage, le cout suit la forme fermee", {
  cfg <- foretaccess_config()
  te <- cfg$desserte$cout$terrassement
  # 30 % de pente : sous `ripage_min` = 0,35, donc ripage nul, rien a evacuer.
  p <- 0.30; L <- 4
  att <- attendu_plan(p, L, te$talus_deblai, te$talus_remblai)
  attendu <- att$deblai * te$prix_deblai_m3 + att$remblai * te$prix_remblai_m3
  expect_equal(cout_terrassement(30, largeur_m = L, config = cfg), attendu,
               tolerance = 1e-9)
})

test_that("terrain plat : aucun terrassement, donc aucun cout", {
  expect_equal(cout_terrassement(0, largeur_m = 4), 0)
})

test_that("le cout croit comme le CARRE de la largeur -- ce que le bareme ignore", {
  # A pente donnee, doubler la plateforme quadruple le terrassement : c'est la
  # raison d'etre de la spec 029, le bareme en escalier rendant la meme valeur
  # pour toutes les largeurs.
  c3 <- cout_terrassement(30, largeur_m = 3)
  c6 <- cout_terrassement(30, largeur_m = 6)
  expect_equal(c6 / c3, 4, tolerance = 1e-9)
})

test_that("le cout est croissant partout, et continu la ou l'on construit", {
  v <- cout_terrassement(seq(0, 95, by = 0.5), largeur_m = 4)
  fini <- is.finite(v)
  expect_true(all(diff(v[fini]) >= -1e-9))      # croissant

  # Continuite sur la plage ou une desserte se construit reellement : aucun
  # saut brutal, contrairement au bareme en escalier qui bondit de 65 EUR/m
  # entre 34,9 % et 35,1 %.
  usuel <- cout_terrassement(seq(0, 50, by = 0.5), largeur_m = 4)
  expect_lt(max(abs(diff(usuel))), 5)
})

test_that("le cout diverge en approchant la pente du talus de deblai", {
  # Ce n'est pas un defaut : a p -> A, le talus amont ne recoupe presque plus le
  # terrain et le volume explose. Le solveur evitera ces cellules de lui-meme,
  # ce qui est le comportement voulu -- inutile de les declarer infranchissables.
  cfg <- foretaccess_config()
  A <- cfg$desserte$cout$terrassement$talus_deblai
  proche <- cout_terrassement(100 * A - 1, largeur_m = 4, config = cfg)
  expect_true(is.finite(proche))
  expect_gt(proche, cout_terrassement(50, largeur_m = 4, config = cfg) * 10)
  expect_true(is.na(cout_terrassement(100 * A, largeur_m = 4, config = cfg)))
})

test_that("un terrain plus raide que les talus est declare inconstructible", {
  cfg <- foretaccess_config()
  # Le talus AVAL ne condamne que tant qu'il reste du remblai a poser : a
  # ripage plein (>= 60 %) la plateforme est entierement creusee, et c'est le
  # talus AMONT (100 %) qui devient la borne.
  cfg2 <- cfg
  cfg2$desserte$cout$terrassement$ripage_max <- 0.9   # remblai encore present a 60 %
  expect_true(is.na(cout_terrassement(60, largeur_m = 4, config = cfg2)))
  expect_true(is.na(cout_terrassement(150, largeur_m = 4, config = cfg)))
  # NA, et non un nombre astronomique qui se propagerait dans le solveur comme
  # un chemin merveilleusement evitable.
  expect_false(is.infinite(cout_terrassement(150, largeur_m = 4, config = cfg)))
})

test_that("le ripage fait basculer l'assiette et declenche l'evacuation", {
  cfg <- foretaccess_config()
  sans <- cout_terrassement(34, largeur_m = 4, config = cfg)   # sous ripage_min
  avec <- cout_terrassement(50, largeur_m = 4, config = cfg)   # entre les seuils
  expect_gt(avec, sans)
  # Sans evacuation, le cout serait plus bas : c'est le transport qui pique.
  cfg2 <- cfg
  cfg2$desserte$cout$terrassement$prix_evacuation_m3 <- 0
  expect_lt(cout_terrassement(50, largeur_m = 4, config = cfg2), avec)
})

test_that("cout_terrassement accepte un SpatRaster et rend la meme grille", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 20, ymin = 0,
                   ymax = 20, crs = "EPSG:2154")
  terra::values(r) <- rep(c(0, 20, 30, 120), each = 4)
  out <- cout_terrassement(r, largeur_m = 4)
  expect_s4_class(out, "SpatRaster")
  expect_equal(dim(out), dim(r))
  v <- terra::values(out, mat = FALSE)
  expect_equal(v[1], 0)                    # plat
  expect_true(is.na(v[13]))                # 120 % : au-dela du talus de deblai
  expect_equal(v[9], cout_terrassement(30, largeur_m = 4))
})

test_that("garde-fous", {
  expect_error(cout_terrassement(30, largeur_m = -1), "largeur_m")
  cfg <- foretaccess_config()
  cfg$desserte$cout$terrassement <- NULL
  expect_error(cout_terrassement(30, largeur_m = 4, config = cfg), "terrassement")
})
