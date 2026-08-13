# `.dsr_canaux_dalles()` lit CHAQUE fichier qu'on lui passe, sans verifier qu'il
# sert. Sur le bloc `ltcp`, cela faisait relire 25 dalles couvrant 2 500 ha pour
# produire un raster de 100 ha : plus de 46 min sans aboutir. Le catalogue de
# `dsr_catalog()` porte pourtant deja l'emprise de chaque dalle.
#
# 25 -> 7 dalles, et la detection passe a 846 s.

grille_test <- function(xmin = 0, ymin = 0, cote = 1000) {
  terra::rast(terra::ext(xmin, xmin + cote, ymin, ymin + cote),
              resolution = 1, crs = "EPSG:2154")
}

catalogue <- function(...) {
  d <- do.call(rbind, lapply(list(...), function(x) as.data.frame(x)))
  d
}

test_that("seules les dalles qui touchent la grille sont retenues", {
  cat <- catalogue(
    list(laz = "dedans.laz",   xmin = 100,   ymin = 100,   xmax = 900,   ymax = 900),
    list(laz = "chevauche.laz", xmin = 800,  ymin = 800,   xmax = 1800,  ymax = 1800),
    list(laz = "loin.laz",     xmin = 50000, ymin = 50000, xmax = 51000, ymax = 51000)
  )
  u <- suppressMessages(foretaccess:::.dalles_utiles(cat, grille_test()))
  expect_setequal(u, c("dedans.laz", "chevauche.laz"))
})

test_that("une dalle qui touche par le bord compte", {
  # Bord commun exactement : elle porte des points de la grille, on la garde.
  cat <- catalogue(list(laz = "bord.laz", xmin = 1000, ymin = 0,
                        xmax = 2000, ymax = 1000))
  expect_equal(suppressMessages(foretaccess:::.dalles_utiles(cat, grille_test())),
               "bord.laz")
})

test_that("sans colonnes d'emprise, on rend TOUT plutot que d'amputer", {
  # Garde-fou conservateur : une convention de nommage inconnue donne un
  # catalogue sans bornes. Un calcul lent vaut mieux qu'un canal de surface
  # silencieusement ampute -- c'est LUI qui porte le signal (AUC 0,870).
  cat <- data.frame(laz = c("a.laz", "b.laz"))
  expect_setequal(foretaccess:::.dalles_utiles(cat, grille_test()),
                  c("a.laz", "b.laz"))
})

test_that("aucune dalle ne touchant, on rend TOUT plutot que rien", {
  # Un filtre qui ecarte tout est plus probablement faux (CRS divergent, bornes
  # mal decodees) qu'exact. Rendre une liste vide priverait la detection de son
  # meilleur canal SANS le dire.
  cat <- catalogue(list(laz = "ailleurs.laz", xmin = 9e5, ymin = 9e5,
                        xmax = 9.1e5, ymax = 9.1e5))
  expect_equal(foretaccess:::.dalles_utiles(cat, grille_test()), "ailleurs.laz")
})

test_that("un catalogue vide ou sans laz rend un vecteur vide", {
  expect_length(foretaccess:::.dalles_utiles(NULL, grille_test()), 0L)
  expect_length(foretaccess:::.dalles_utiles(data.frame(x = 1), grille_test()), 0L)
})

test_that("une borne NA ne fait pas ecarter la dalle", {
  # Doute -> on garde. Meme regle que ci-dessus : le silence coute plus cher que
  # la lenteur.
  cat <- catalogue(
    list(laz = "ok.laz",  xmin = 100, ymin = 100, xmax = 900, ymax = 900),
    list(laz = "flou.laz", xmin = NA, ymin = NA, xmax = NA, ymax = NA)
  )
  u <- suppressMessages(foretaccess:::.dalles_utiles(cat, grille_test()))
  expect_true("flou.laz" %in% u)
})
