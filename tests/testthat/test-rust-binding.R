test_that("le binding Rust cablehelp_version() répond", {
  v <- cablehelp_version()
  expect_type(v, "character")
  expect_length(v, 1)
  expect_true(nzchar(v))
})
