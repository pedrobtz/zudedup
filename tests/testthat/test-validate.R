# Design section 12: one crafted manifest per guard in R/validate.R. The
# names match the "# GUARD: name" markers; tools/run-mutation-check removes
# each guard in turn and requires its case here to fail.

test_that("a good manifest passes", {
  m <- good_manifest()
  expect_identical(zdd_validate_manifest(m), m)
  expect_identical(zdd_validate_manifest(dedup_manifest(raw())), dedup_manifest(raw()))
})

test_that("GUARD class", {
  expect_bad(unclass(good_manifest()))
})

test_that("GUARD fields", {
  m <- unclass(good_manifest())
  m$size <- NULL
  expect_bad(structure(m, class = "dedup_manifest"))
})

test_that("GUARD algorithm", {
  expect_bad(with_field(good_manifest(), "algorithm", "md5"))
  expect_bad(with_field(good_manifest(), "algorithm", c("xxh3", "xxh3")))
})

test_that("GUARD params", {
  expect_bad(with_field(good_manifest(), "params", list(min = 64)))
  expect_bad(with_field(good_manifest(), "params", list(min = 64, avg = 300, max = 1024)))
})

test_that("GUARD hashes-type", {
  m <- good_manifest()
  h <- m$hashes
  h[2] <- NA
  expect_bad(with_field(m, "hashes", h))
  expect_bad(with_field(m, "hashes", seq_along(m$hashes)))
})

test_that("GUARD max-chunks", {
  m <- good_manifest()
  expect_zudedup_error(zdd_validate_manifest(m, max_chunks = length(m) - 1),
                       "zudedup_limit_error", limit = "max_chunks",
                       limit_value = length(m) - 1)
  expect_identical(zdd_validate_manifest(m, max_chunks = length(m)), m)
})

test_that("GUARD hashes-hex", {
  m <- good_manifest()
  h <- m$hashes
  h[1] <- toupper(h[1])
  expect_bad(with_field(m, "hashes", h))
  h[1] <- substr(m$hashes[1], 1, 31)
  expect_bad(with_field(m, "hashes", h))
  # A SHA-256 digest in an XXH3 manifest is the wrong length.
  h[1] <- strrep("a", 64)
  expect_bad(with_field(m, "hashes", h))
})

test_that("GUARD lengths-type", {
  m <- good_manifest()
  expect_bad(with_field(m, "lengths", as.numeric(m$lengths)))
  expect_bad(with_field(m, "lengths", m$lengths[-1]))
})

test_that("GUARD lengths-range", {
  m <- good_manifest()
  len <- m$lengths
  len[1] <- 0L
  len[2] <- len[2] + m$lengths[1]
  expect_bad(with_field(m, "lengths", len))
  len <- m$lengths
  len[1] <- 1025L
  len[2] <- len[2] - (1025L - m$lengths[1])
  expect_bad(with_field(m, "lengths", len))
})

test_that("GUARD size-type", {
  m <- good_manifest()
  expect_bad(with_field(m, "size", -1))
  expect_bad(with_field(m, "size", NA_real_))
  expect_bad(with_field(m, "size", "5000"))
})

test_that("GUARD size-sum", {
  expect_bad(with_field(good_manifest(), "size", 4999))
})

test_that("GUARD max-size", {
  m <- good_manifest()
  expect_zudedup_error(zdd_validate_manifest(m, max_size = 4999),
                       "zudedup_limit_error", limit = "max_size", limit_value = 4999)
  expect_identical(zdd_validate_manifest(m, max_size = 5000), m)
})

test_that("GUARD object-hash", {
  expect_bad(with_field(good_manifest(), "hash", c("a", "b")))
  expect_bad(with_field(good_manifest(), "hash", 1))
})

test_that("GUARD object-hex", {
  expect_bad(with_field(good_manifest(), "hash", strrep("z", 32)))
})

test_that("GUARD object-na", {
  expect_bad(with_field(good_manifest(), "hash", NA_character_))
  # A SHA-256 manifest may lack its object digest (design D15).
  m <- good_manifest("sha256")
  m2 <- with_field(m, "hash", NA_character_)
  expect_identical(zdd_validate_manifest(m2), m2)
})
