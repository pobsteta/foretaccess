# classes_debardage() : classement de la distance de debardage en bandes facon
# Sylvaccess (6 bandes + inaccessible + inexploitable + hors_foret).

cd_setup <- function() {
  toy <- system.file("extdata", "toy", package = "foretaccess")
  pre <- preprocess(
    file.path(toy, "mnt.tif"),
    file.path(toy, "desserte.gpkg"),
    file.path(toy, "foret.gpkg")
  )
  list(pre = pre, sk = skidder(pre))
}

test_that("la sortie est un raster categoriel a 9 classes, colore", {
  s <- cd_setup()
  cl <- classes_debardage(s$sk, s$pre)
  expect_s4_class(cl, "SpatRaster")
  expect_true(terra::is.factor(cl))
  expect_true(terra::has.colors(cl))
  expect_identical(names(cl), "classe_debardage")
  labs <- as.character(terra::levels(cl)[[1]][[2]])
  expect_equal(labs, c("0-250", "250-500", "500-1000", "1000-1500",
                       "1500-2000", "> 2000", "inaccessible",
                       "inexploitable", "hors_foret"))
})

test_that("chaque distance tombe dans la bonne bande (1..6)", {
  s <- cd_setup()
  acc <- as.numeric(terra::values(s$sk$accessibilite))
  niv <- terra::levels(s$sk$accessibilite)[[1]]
  code_parc <- niv[[1]][as.character(niv[[2]]) == "parcourable"]
  idx <- which(acc == code_parc)[1:6]

  # Injecte une distance par bande sur six cellules atteignables.
  milieux <- c(100, 300, 700, 1200, 1700, 2500) # -> bandes 1,2,3,4,5,6
  d <- s$sk$distance_debardage
  vals <- as.numeric(terra::values(d))
  vals[idx] <- milieux
  terra::values(d) <- vals
  s$sk$distance_debardage <- d

  cl <- classes_debardage(s$sk, s$pre)
  expect_equal(as.numeric(terra::values(cl))[idx], 1:6)
})

test_that("une cellule forestiere trop raide devient inexploitable (classe 8)", {
  s <- cd_setup()
  acc <- as.numeric(terra::values(s$sk$accessibilite))
  niv <- terra::levels(s$sk$accessibilite)[[1]]
  code_parc <- niv[[1]][as.character(niv[[2]]) == "parcourable"]
  foret <- as.numeric(terra::values(s$pre$foret_mask)) > 0
  # Une cellule atteignable ET forestiere (l'inexploitable ne vaut qu'en foret).
  cible <- which(acc == code_parc & foret)[1]

  # Force l'exclusion (pente d'abattage) sur cette cellule forestiere.
  em <- s$pre$exclusion_mask
  vals <- as.numeric(terra::values(em))
  vals[cible] <- 1
  terra::values(em) <- vals
  s$pre$exclusion_mask <- em

  cl <- classes_debardage(s$sk, s$pre)
  # 8 = inexploitable, prioritaire sur la bande de distance.
  expect_equal(as.numeric(terra::values(cl))[cible], 8)

  # Sans `pre`, pas de classe inexploitable : la cellule garde sa bande.
  cl2 <- classes_debardage(s$sk)
  expect_lt(as.numeric(terra::values(cl2))[cible], 7)
})

test_that("la sortie se recapitule (surfaces par classe)", {
  s <- cd_setup()
  cl <- classes_debardage(s$sk, s$pre)
  rec <- recapituler(cl)
  expect_s3_class(rec, "data.frame")
  expect_true(all(c("classe", "surface_ha") %in% names(rec)))
  # La somme des surfaces couvre toute la grille (indetermine compris).
  total <- prod(terra::res(s$pre$mnt)) * terra::ncell(s$pre$mnt) / 1e4
  expect_equal(sum(rec$surface_ha), total, tolerance = 1e-6)
})
