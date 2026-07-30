# Garde-fou : toute fonction exportee doit figurer dans l'index de reference
# `_pkgdown.yml`. Sinon pkgdown echoue en `check_missing_topics()` -- ce qui a
# bloque DEUX PR de suite (2026-07-29 et 30), a chaque fois apres l'ajout d'une
# fonction exportee. `devtools::test()` ne voit pas cette classe de defaut ;
# seuls pkgdown et R CMD check la levent, et tous deux ne tournent qu'en CI.
#
# Ce test la ramene en local, ou elle coute quelques secondes au lieu d'un
# aller-retour de vingt minutes.

test_that("toute fonction exportee est indexee dans _pkgdown.yml", {
  yml <- testthat::test_path("..", "..", "_pkgdown.yml")
  nsp <- testthat::test_path("..", "..", "NAMESPACE")
  skip_if_not(file.exists(yml) && file.exists(nsp), "hors arborescence source")

  exports <- grep("^export\\(", readLines(nsp), value = TRUE)
  exports <- sub("^export\\(", "", sub("\\)$", "", exports))
  exports <- gsub("^`|`$", "", exports)
  skip_if(length(exports) == 0, "aucun export")

  y <- readLines(yml, warn = FALSE)
  # Deux formes coexistent dans l'index : l'entree nominative `- fonction` et le
  # motif `- starts_with("prefixe")`, utilise pour les bindings Rust `cable_*`.
  nominatifs <- trimws(sub("^\\s*-\\s*", "", grep("^\\s*-\\s*[A-Za-z.][A-Za-z0-9._]*\\s*$",
    y, value = TRUE)))
  motifs <- regmatches(y, regexpr("starts_with\\(\"[^\"]+\"\\)", y))
  prefixes <- gsub("^starts_with\\(\"|\"\\)$", "", motifs)

  couvert <- function(f) {
    f %in% nominatifs || any(vapply(prefixes, function(p) startsWith(f, p), logical(1)))
  }
  manquants <- exports[!vapply(exports, couvert, logical(1))]
  expect_identical(manquants, character(0),
    info = paste("exportees mais absentes de _pkgdown.yml :",
      paste(manquants, collapse = ", ")))
})

test_that("le garde-fou DETECTE bien une exportee non indexee", {
  # Un test qui passe ne prouve rien s'il ne peut pas echouer. On rejoue la
  # logique de couverture sur un index fictif : `starts_with()` doit couvrir le
  # prefixe, et une fonction absente doit ressortir.
  nominatifs <- c("acquire_mnt", "verifier_integrite_desserte")
  prefixes <- "cable_"
  couvert <- function(f) {
    f %in% nominatifs || any(vapply(prefixes, function(p) startsWith(f, p), logical(1)))
  }
  expect_true(couvert("acquire_mnt"))          # entree nominative
  expect_true(couvert("cable_scan"))           # couvert par starts_with()
  expect_false(couvert("fonction_oubliee"))    # LE cas qui a casse deux PR
  expect_false(couvert("acquire_mnt_rgealti")) # piege : prefixe d'une indexee
})
