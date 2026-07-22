# Correspondance ACCESSFOR (IGN) <-> classes_debardage(). Le domaine ACCESSFOR a
# ete verifie au WFS sur le departement 48 (cf. data-raw/accessfor.R) : bandes
# 3..8 = nos 6 bandes, class 1 = inaccessible, class 2 = inexploitable (pente).

test_that("la table couvre les 9 classes, jointure sur l'entier `class`", {
  co <- accessfor_correspondance()
  expect_s3_class(co, "data.frame")
  expect_setequal(
    names(co),
    c("fa_value", "fa_classe", "accessfor_class", "accessfor_cat")
  )
  expect_equal(nrow(co), 9L)
  expect_equal(co$fa_value, 1:9)
})

test_that("la correspondance encode exactement le domaine ACCESSFOR observe", {
  co <- accessfor_correspondance()
  # Bandes : ACCESSFOR 3..8 -> nos valeurs 1..6.
  bandes <- co[co$fa_value %in% 1:6, ]
  expect_equal(bandes$accessfor_class, 3:8)
  expect_equal(bandes$fa_classe,
    c("0-250", "250-500", "500-1000", "1000-1500", "1500-2000", "> 2000"))
  # Hors bande.
  expect_equal(co$accessfor_class[co$fa_classe == "inaccessible"], 1L)
  expect_equal(co$accessfor_class[co$fa_classe == "inexploitable"], 2L)
  # hors_foret : aucun code ACCESSFOR (ses polygones SONT la foret).
  expect_true(is.na(co$accessfor_class[co$fa_classe == "hors_foret"]))
})

test_that("les codes ACCESSFOR non-NA sont une bijection (1,2,3..8)", {
  co <- accessfor_correspondance()
  cls <- co$accessfor_class[!is.na(co$accessfor_class)]
  expect_equal(sort(cls), 1:8)
  expect_false(any(duplicated(cls)))
})

test_that("la table colle a la sortie reelle de classes_debardage() (skidder)", {
  # Ancrage : `fa_value`/`fa_classe` doivent etre EXACTEMENT les niveaux que
  # classes_debardage() produit sous la config par defaut. Si l'un des deux
  # change, ce test tombe -- la correspondance ne doit jamais deriver en silence.
  toy <- system.file("extdata", "toy", package = "foretaccess")
  pre <- preprocess(
    file.path(toy, "mnt.tif"),
    file.path(toy, "desserte.gpkg"),
    file.path(toy, "foret.gpkg")
  )
  cl <- classes_debardage(skidder(pre), pre)
  niv <- terra::levels(cl)[[1]]

  co <- accessfor_correspondance()
  expect_equal(co$fa_value, as.integer(niv[[1]]))
  expect_equal(co$fa_classe, as.character(niv[[2]]))
})

test_that("des bandes non-Sylvaccess sont refusees (correspondance indefinie)", {
  cfg <- foretaccess_config(skidder = list(classes_distance_m = c(0, 100, 200)))
  expect_error(accessfor_correspondance(cfg), "ACCESSFOR")
})

# --- Generalisation de classes_debardage() au porteur -----------------------
# ACCESSFOR publie `acces_skidder` ET `acces_porteur` avec le meme schema. Le
# porteur porte les memes niveaux d'accessibilite et une `distance_debardage` :
# classes_debardage() doit accepter les deux pour que le porteur soit comparable.

test_that("classes_debardage() accepte un objet porteur", {
  pre <- pre_plan(pente = 0.20, n = 61)
  po <- porteur(pre)
  expect_s3_class(po, "foretaccess_porteur")

  cl <- classes_debardage(po, pre)
  expect_s4_class(cl, "SpatRaster")
  expect_true(terra::is.factor(cl))
  expect_identical(names(cl), "classe_debardage")
  labs <- as.character(terra::levels(cl)[[1]][[2]])
  expect_equal(labs, c("0-250", "250-500", "500-1000", "1000-1500",
                       "1500-2000", "> 2000", "inaccessible",
                       "inexploitable", "hors_foret"))
})

test_that("classes_debardage() refuse un objet qui n'est ni skidder ni porteur", {
  expect_error(classes_debardage(list(config = foretaccess_config())),
    "foretaccess_skidder|foretaccess_porteur|Must inherit")
})
