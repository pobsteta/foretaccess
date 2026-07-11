# Certificat d'exactitude d'une propagation sur une fenetre (spec 007 §4.3).
#
# Le certificat est *suffisant*, pas necessaire : une cellule exacte peut n'etre pas
# certifiee. Ce qui est interdit, c'est l'inverse -- une cellule certifiee mais fausse
# (CA-7.3). C'est ce que verifie le test central de ce fichier.

grille <- function(nr, nc) {
  terra::rast(
    nrows = nr, ncols = nc, xmin = 0, xmax = nc, ymin = 0, ymax = nr,
    crs = "EPSG:2154"
  )
}

cout_uniforme <- function(nr, nc) {
  r <- grille(nr, nc)
  terra::values(r) <- 1
  r
}

source_en <- function(gabarit, l, c, id = 1) {
  s <- terra::rast(gabarit)
  v <- rep(NA_real_, terra::ncell(s))
  v[(l - 1) * terra::ncol(gabarit) + c] <- id
  terra::values(s) <- v
  s
}

test_that("une fenetre fermee certifie tout : rien ne peut entrer", {
  cout <- cout_uniforme(7, 7)
  cert <- certifier_propagation(cout, source_en(cout, 4, 4), bord = character(0))

  expect_equal(cert$n_non_certifie, 0)
  expect_true(all(terra::values(cert$certifie) == 1))
  # Aucune entree : aucun chemin exterieur, donc l'allocation est exacte partout.
  expect_true(all(terra::values(cert$certifie_allocation) == 1))
})

test_that("le bord ouvert deprecie les cellules qu'il atteint a moindre cout", {
  cout <- cout_uniforme(9, 9)
  cert <- certifier_propagation(cout, source_en(cout, 5, 5))

  # Le centre est loin du bord : certifie. Les cellules de l'anneau ne le sont pas,
  # le bord les atteignant a cout nul.
  expect_equal(terra::values(cert$certifie)[[5 * 9 - 4]], 1)
  expect_equal(terra::values(cert$certifie)[[1]], 0)
  expect_gt(cert$n_non_certifie, 0)
})

test_that("aucun faux positif : toute cellule certifiee est exacte (CA-7.3)", {
  # Territoire global : un mur couteux barre les colonnes 4, sauf par le bas. Le
  # chemin optimal vers la droite du mur contourne donc par en dessous.
  nr <- 15
  nc <- 15
  global <- grille(nr, nc)
  v <- rep(1, nr * nc)
  mur <- as.vector(outer(1:11, 4, function(l, c) (l - 1) * nc + c))
  v[mur] <- 500
  terra::values(global) <- v

  src_global <- source_en(global, 1, 1)
  ref <- propager_cout(global, src_global)

  # Fenetre : le quart haut-gauche. Elle contient la source et une partie du mur,
  # mais pas le passage du bas. Elle touche le haut et la gauche de l'emprise.
  fen <- terra::ext(0, 8, nr - 8, nr)
  cout_f <- terra::crop(global, fen)
  src_f <- terra::crop(src_global, fen)

  cert <- certifier_propagation(cout_f, src_f, bord = c("bas", "droite"))

  d_local <- terra::values(cert$propagation$cout_cumule)
  d_global <- terra::values(terra::crop(ref$cout_cumule, fen))
  certifie <- terra::values(cert$certifie) == 1

  # Le cas est bien discriminant : la fenetre se trompe quelque part.
  expect_gt(sum(abs(d_local - d_global) > 1e-9), 0)
  # Et jamais la ou elle certifie.
  expect_equal(d_local[certifie], d_global[certifie])
})

test_that("une cellule inaccessible des deux cotes est certifiee inaccessible", {
  # Une cellule enclavee par des couts NA : ni la source ni le bord ne l'atteignent.
  cout <- cout_uniforme(7, 7)
  centre <- 4 * 7 - 3
  anneau <- c(centre - 8, centre - 7, centre - 6, centre - 1,
              centre + 1, centre + 6, centre + 7, centre + 8)
  cout[anneau] <- NA

  cert <- certifier_propagation(cout, source_en(cout, 1, 1))

  expect_true(is.na(terra::values(cert$propagation$cout_cumule)[[centre]]))
  expect_equal(terra::values(cert$certifie)[[centre]], 1)
  # `Inf <= Inf` : l'allocation `NA` est exacte elle aussi.
  expect_equal(terra::values(cert$certifie_allocation)[[centre]], 1)
})

test_that("a egalite, la distance est certifiee mais pas l'allocation", {
  # La source est sur le bord gauche, lui-meme ouvert : le bord l'atteint a cout nul.
  cout <- cout_uniforme(5, 5)
  cert <- certifier_propagation(cout, source_en(cout, 3, 1), bord = "gauche")

  src <- 3 * 5 - 4
  expect_equal(terra::values(cert$certifie)[[src]], 1)
  expect_equal(terra::values(cert$certifie_allocation)[[src]], 0)
})

test_that("une entree infranchissable n'est pas une entree", {
  # Bord gauche entierement infranchissable : rien ne peut entrer par la.
  cout <- cout_uniforme(5, 5)
  cout[, 1] <- NA
  cert <- certifier_propagation(cout, source_en(cout, 3, 3), bord = "gauche")

  expect_equal(cert$n_non_certifie, 0)
})

test_that("la connexite est le cas cout nul", {
  # Cout constant : la certification ne depend que de l'atteignabilite.
  cout <- cout_uniforme(9, 9)
  zone <- terra::rast(cout)
  terra::values(zone) <- 1
  # Une bande infranchissable isole les trois dernieres lignes de la source.
  zone[6, ] <- 0

  cert <- certifier_propagation(cout, source_en(cout, 1, 1), zone = zone, bord = "bas")

  # Les lignes 7 a 9 sont inaccessibles depuis la source, mais le bord bas les atteint :
  # elles pourraient l'etre depuis l'exterieur. Non certifiees, comme il se doit.
  expect_equal(terra::values(cert$certifie)[[8 * 9 - 4]], 0)
  # La ligne 1, elle, est atteinte par la source et hors de portee du bord bas.
  expect_equal(terra::values(cert$certifie)[[1]], 1)
})

test_that("zone_majorante permet a d_bord de minorer malgre une zone sous-estimee", {
  cout <- cout_uniforme(7, 7)
  # `zone` sous-estime la traversabilite : elle ignore la colonne 7, que le monde
  # exterieur, lui, sait franchissable. Sans `zone_majorante`, d_bord ne l'explorerait
  # pas et certifierait a tort.
  zone <- terra::rast(cout)
  terra::values(zone) <- 1
  zone[, 7] <- 0
  majorante <- terra::rast(cout)
  terra::values(majorante) <- 1

  etroit <- certifier_propagation(cout, source_en(cout, 1, 1), zone = zone, bord = "droite")
  large <- certifier_propagation(
    cout, source_en(cout, 1, 1),
    zone = zone, zone_majorante = majorante, bord = "droite"
  )

  expect_lt(etroit$n_non_certifie, large$n_non_certifie)
})

test_that("cout_max s'applique aux deux propagations", {
  cout <- cout_uniforme(11, 11)
  # Sous plafond, ce que le bord n'atteint pas ne peut pas venir de l'exterieur.
  cert <- certifier_propagation(cout, source_en(cout, 6, 6), cout_max = 2)

  centre <- 6 * 11 - 5
  expect_equal(terra::values(cert$certifie)[[centre]], 1)

  # La cellule (4,4) est a plus de 2 de la source comme du bord : les deux propagations
  # s'y arretent, et `Inf <= Inf` la certifie inaccessible *sous ce plafond*.
  loin <- 3 * 11 + 4
  expect_true(is.na(terra::values(cert$propagation$cout_cumule)[[loin]]))
  expect_equal(terra::values(cert$certifie)[[loin]], 1)

  # Un coin est lui-meme une entree : `d_bord = 0` l'y attend. Jamais certifie.
  expect_equal(terra::values(cert$certifie)[[1]], 0)
})

test_that("un masque de bord explicite est accepte, et sa grille validee", {
  cout <- cout_uniforme(5, 5)
  masque <- terra::rast(cout)
  v <- rep(NA_real_, 25)
  v[1] <- 1
  terra::values(masque) <- v

  cert <- certifier_propagation(cout, source_en(cout, 5, 5), bord = masque)
  expect_equal(terra::values(cert$certifie)[[1]], 0)

  autre <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 4)
  terra::crs(autre) <- "EPSG:2154"
  terra::values(autre) <- 1
  expect_error(certifier_propagation(cout, source_en(cout, 1, 1), bord = autre))
})

test_that("un cote inconnu leve une erreur", {
  cout <- cout_uniforme(5, 5)
  expect_error(certifier_propagation(cout, source_en(cout, 1, 1), bord = "nord"))
})

test_that("print.foretaccess_certificat resume le certificat", {
  cout <- cout_uniforme(5, 5)
  cert <- certifier_propagation(cout, source_en(cout, 3, 3))
  expect_message(print(cert), regexp = "Certificat ForetAccess")
})
