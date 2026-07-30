# Garde-fous des defauts que SEUL R CMD check leve, et qui ne tournent qu'en CI.
# Chacun a deja coute un aller-retour de vingt-quatre minutes :
#   * caracteres non-ASCII dans du CODE (PR #139) ;
#   * arguments exportes non documentes (PR #128).
# `devtools::test()` ne voit ni l'un ni l'autre. Les ramener ici coute quelques
# secondes.

test_that("aucun caractere non-ASCII dans le CODE R", {
  # R CMD check TOLERE le non-ASCII en commentaire, pas dans un litteral de
  # chaine : « Portable packages must use only ASCII characters in their R code
  # [...] except perhaps in comments ». Un message cli avec des guillemets
  # francais casse donc le check sans casser aucun test.
  dossier <- testthat::test_path("..", "..", "R")
  skip_if_not(dir.exists(dossier), "hors arborescence source")
  fautifs <- character(0)
  for (f in list.files(dossier, pattern = "[.]R$", full.names = TRUE)) {
    l <- readLines(f, warn = FALSE)
    # Hors commentaires : ni `#` de commentaire, ni roxygen `#'`.
    code <- sub("#.*$", "", l)
    idx <- which(vapply(code, function(x) any(utf8ToInt(x) > 127), logical(1),
      USE.NAMES = FALSE))
    if (length(idx)) {
      fautifs <- c(fautifs, sprintf("%s:%s", basename(f), paste(idx, collapse = ",")))
    }
  }
  expect_identical(fautifs, character(0))
})

test_that("le garde-fou non-ASCII DETECTE bien un litteral fautif", {
  # Un test qui passe ne prouve rien s'il ne peut pas echouer.
  faux <- 'x <- "citation « test »"'
  vrai <- 'x <- "citation ASCII" # commentaire avec é et « »'
  sans_com <- function(s) sub("#.*$", "", s)
  expect_true(any(utf8ToInt(sans_com(faux)) > 127))
  expect_false(any(utf8ToInt(sans_com(vrai)) > 127))
})

test_that("aucun argument exporte non documente", {
  # `tools::checkDocFiles()` est ce que R CMD check execute. L'appeler ici le
  # rend visible avant le push -- il a bloque la PR #128 sur un `deviation_max`
  # ajoute sans @param.
  racine <- testthat::test_path("..", "..")
  skip_if_not(file.exists(file.path(racine, "DESCRIPTION")), "hors source")
  skip_if_not(dir.exists(file.path(racine, "man")), "man/ absent")
  r <- suppressWarnings(tools::checkDocFiles(dir = racine))
  expect_length(unlist(r), 0L)
})
