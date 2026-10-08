test_that("zudedup_info() reports the build and the format", {
  i <- zudedup_info()
  expect_named(i, c("version", "zufast", "gear_seed", "boundary_rule",
                    "defaults", "hashes"))
  expect_identical(i$gear_seed, "0x5a5a5a5a5a5a5a5a")
  expect_match(i$zufast, "^[0-9]+\\.[0-9]+\\.[0-9]+$")
  expect_identical(i$defaults, list(min = 2048, avg = 8192, max = 65536))
  expect_true(i$hashes[["xxh3"]])
  expect_identical(i$hashes[["sha256"]], requireNamespace("zucrypt", quietly = TRUE))
})
