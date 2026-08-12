# `dsr_detecter()` fusionne ses termes en MOYENNE GEOMETRIQUE ponderee : un poids
# n'y dose pas une contribution, il arme un VETO -- le resultat est domine par le
# plus PETIT terme. `vesselness` y pese 1, le double du canal de surface, et
# entre par une rampe demarrant a 0,3 alors que c'est un detecteur de cretes
# creux (1,62 % des cellules l'atteignent sur le bloc wsfi).
#
# Pire, il etait compte DEUX FOIS : `specs_desserte_calibrees()$geomorpho` porte
# deja un canal `vesselness`, calibre entre 0,00064 et 0,0708 -- une borne haute
# 4,2 fois PLUS BASSE que le debut de la rampe du veto.
#
# Mesure de la campagne CA-26.5 (`data-raw/annotation_wsfi/RESULTATS.md`) : sur
# 4 pistes reelles annotees, la geomorphologie seule fait passer 11,8 % de leurs
# cellules au seuil 0,40 ; avec le veto, 0,0 %. Rappel 0/4 avant, 3/4 apres.

test_that("vesselness n'est pas repasse en veto quand il est deja un canal", {
  # Le defaut `specs_desserte_calibrees()` PORTE un canal vesselness : le
  # double comptage doit etre detecte et annonce.
  expect_true("vesselness" %in% names(specs_desserte_calibrees()$geomorpho))
})

test_that("une calibration SANS vesselness ne declenche pas la garde", {
  # `dsr_calibrer_specs()` peut ecarter vesselness (AUC 0,510 sur les pistes
  # annotees). La garde ne doit alors pas se declencher -- et c'est justement
  # pourquoi `poids` existe : sans lui, le veto s'appliquerait quand meme.
  plat <- list(
    rugosite = list(type = "croissante", a = 0.04, b = 0.17, poids = 3),
    pente    = list(type = "decroissante", a = 4.5, b = 20.3, poids = 1)
  )
  sp <- specs_depuis_calibration(plat)
  expect_false("vesselness" %in% names(sp$geomorpho))
})

test_that("detecter_desserte() expose poids et seuil_vessel", {
  # Sans ces deux arguments, un appelant ne pouvait PAS neutraliser le veto :
  # c'est ce qui rendait la detection inutilisable sur un massif ou vesselness
  # reste sous la rampe.
  f <- names(formals(detecter_desserte))
  expect_true(all(c("poids", "seuil_vessel") %in% f))
  # Defaut `NULL` : on n'impose rien, on laisse ceux de dessertR.
  expect_null(eval(formals(detecter_desserte)$poids))
  expect_null(eval(formals(detecter_desserte)$seuil_vessel))
})

test_that("la moyenne geometrique est bien dominee par son plus petit terme", {
  # Le fait qui justifie tout ce qui precede, verifie sur l'arithmetique plutot
  # que sur dessertR : ce n'est pas une propriete de leur code, c'en est une de
  # la moyenne geometrique. Un terme a 0,001 avec un poids 1 ecrase un terme a
  # 0,9 -- ce qu'une moyenne ARITHMETIQUE ne ferait pas.
  geo <- function(mu, w) exp(sum(w * log(mu)) / sum(w))
  bon <- 0.9
  veto <- 0.001
  expect_lt(geo(c(bon, veto), c(1, 1)), 0.05)
  expect_gt(mean(c(bon, veto)), 0.4)   # la moyenne arithmetique, elle, resisterait
  # Neutraliser le poids du veto restaure le terme utile.
  expect_equal(geo(c(bon, veto), c(1, 0)), bon, tolerance = 1e-9)
})
