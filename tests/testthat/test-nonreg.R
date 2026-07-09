test_that("compare_to_oracle valide en-deçà de la tolérance", {
  res <- compare_to_oracle(c(1, 2, 3), c(1, 2, 3.0000001), tol_rel = 1e-3)
  expect_s3_class(res, "foretaccess_nonreg")
  expect_true(res$ok)
})

test_that("compare_to_oracle détecte un écart au-delà de la tolérance", {
  res <- compare_to_oracle(c(1, 2, 3), c(1, 2, 3.5), tol_abs = 0, tol_rel = 1e-6)
  expect_false(res$ok)
  expect_gt(res$max_abs, 0.4)
})

test_that("test à blanc : un oracle est identique à lui-même", {
  mnt <- terra::rast(system.file("extdata/toy/mnt.tif", package = "foretaccess"))
  res <- compare_to_oracle(mnt, mnt, tol_abs = 0, tol_rel = 0)
  expect_true(res$ok)
  expect_equal(res$max_abs, 0)
})

test_that("formes incompatibles -> erreur", {
  expect_error(compare_to_oracle(c(1, 2), c(1, 2, 3)), regexp = "incompatibles")
})

test_that("positions des NA divergentes -> erreur", {
  expect_error(
    compare_to_oracle(c(1, NA, 3), c(1, 2, NA)),
    regexp = "NA"
  )
})
