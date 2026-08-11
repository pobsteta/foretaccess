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


# --- Branchement dans la surface de cout (spec 029 sec.6) --------------------
# Fixture locale : testthat isole chaque fichier, `fake_pre` de
# test-desserte-cout.R n'est pas visible ici. Reduite aux champs que
# `surface_cout_construction()` lit.
pre_pente <- function(slope_pct, nrow = 4, ncol = 4) {
  mnt <- terra::rast(nrows = nrow, ncols = ncol, xmin = 0, xmax = ncol * 5,
                     ymin = 0, ymax = nrow * 5, crs = "EPSG:2154")
  terra::values(mnt) <- 100; names(mnt) <- "mnt"
  sp <- terra::rast(mnt); terra::values(sp) <- slope_pct
  names(sp) <- "slope_pct"
  ob <- terra::rast(mnt); terra::values(ob) <- 0
  names(ob) <- "obstacles_complets_mask"
  structure(list(mnt = mnt, slope_pct = sp, obstacles_complets_mask = ob),
            class = "foretaccess_preprocessing")
}

test_that("methode_pente bascule le terme de pente sans toucher au reste", {
  skip_if_not_installed("terra")
  pre <- pre_pente(30)
  cfg <- foretaccess_config()

  bar <- surface_cout_construction(pre, cfg)                       # defaut
  ter <- surface_cout_construction(pre, cfg, methode_pente = "terrassement")

  base <- cfg$desserte$cout$cout_base_m
  v_bar <- terra::values(bar$cout, mat = FALSE)[1]
  v_ter <- terra::values(ter$cout, mat = FALSE)[1]
  # A 30 % : bareme = 25 EUR/m de surcout ; terrassement = la forme fermee.
  expect_equal(v_bar, base + 25)
  expect_equal(v_ter, base + cout_terrassement(30, largeur_m = 4, config = cfg))
})

test_that("le terrassement rend infranchissable ce qu'il declare impossible", {
  skip_if_not_installed("terra")
  # 120 % : au-dela du talus de deblai. Le bareme, lui, y met Inf. Les deux
  # doivent aboutir a une cellule infranchissable -- un NA se propagerait en
  # silence dans la somme et laisserait passer le solveur.
  pre <- pre_pente(120)
  ter <- surface_cout_construction(pre, methode_pente = "terrassement")
  expect_true(all(!terra::values(ter$franchissable, mat = FALSE), na.rm = TRUE))
})

test_that("la largeur de plateforme ne joue que sur le terrassement", {
  skip_if_not_installed("terra")
  pre <- pre_pente(30)
  large <- surface_cout_construction(pre, methode_pente = "terrassement",
                                     largeur_m = 6)
  etroit <- surface_cout_construction(pre, methode_pente = "terrassement",
                                      largeur_m = 3)
  expect_gt(terra::values(large$cout, mat = FALSE)[1],
            terra::values(etroit$cout, mat = FALSE)[1])
  # Le bareme, lui, est aveugle a la largeur : c'est la raison de la spec 029.
  b6 <- surface_cout_construction(pre, largeur_m = 6)
  b3 <- surface_cout_construction(pre, largeur_m = 3)
  expect_equal(terra::values(b6$cout, mat = FALSE)[1],
               terra::values(b3$cout, mat = FALSE)[1])
})

# --- Ajouts de la relecture (2026-08-11) ------------------------------------

test_that("l'invariant ripage_max <= talus_remblai est IMPOSE", {
  # La continuite mesuree au test precedent ne tient que parce que le defaut
  # pose `ripage_max == talus_remblai`. Decouples, la demi-largeur remblayee ne
  # s'annule plus assez vite et `s_remblai` diverge juste sous `talus_remblai` :
  # 5 737 EUR/m a 59,99 % (contre 216 avec le defaut), puis NA a 60 %. C'est la
  # discontinuite que l'assiette asymetrique est censee avoir supprimee, et rien
  # ne l'interdisait en config.
  te <- list(prix_deblai_m3 = 6, prix_remblai_m3 = 4, prix_evacuation_m3 = 12,
             talus_deblai = 1.0, talus_remblai = 0.6,
             ripage_min = 0.35, ripage_max = 0.80)
  expect_error(
    validate_config(foretaccess_config(desserte = list(cout = list(terrassement = te)))),
    "ripage_max"
  )

  # L'egalite (le defaut) reste licite : c'est elle qui rend le cout continu.
  te$ripage_max <- te$talus_remblai
  expect_no_error(validate_config(
    foretaccess_config(desserte = list(cout = list(terrassement = te)))))

  # Le garde-fou NUMERIQUE de `.cout_terrassement_num()` (`r0 < 1 & p >= B`)
  # reste utile en defense de profondeur : `cout_terrassement()` ne valide pas
  # la config, et le test « terrain plus raide que les talus » ci-dessus s'en
  # sert encore avec un `ripage_max` que `validate_config()` refuse desormais.
  expect_true(is.na(cout_terrassement(60, largeur_m = 4, config = local({
    cfg <- foretaccess_config()
    cfg$desserte$cout$terrassement$ripage_max <- 0.9
    cfg
  }))))
})

test_that("le defaut de config satisfait l'invariant", {
  te <- foretaccess_config()$desserte$cout$terrassement
  expect_lte(te$ripage_max, te$talus_remblai)
})
