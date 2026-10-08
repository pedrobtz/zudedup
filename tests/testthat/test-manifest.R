test_that("a manifest records the chunks, the size and what made them", {
  x <- splitmix_bytes(100000, "1")
  m <- dedup_manifest(x, min = 64, avg = 256, max = 1024)
  t <- dedup_chunk(x, min = 64, avg = 256, max = 1024)
  expect_s3_class(m, "dedup_manifest")
  expect_identical(names(unclass(m)),
                   c("hashes", "lengths", "size", "hash", "algorithm", "params"))
  expect_identical(m$hashes, t$hash)
  expect_identical(m$lengths, t$length)
  expect_identical(m$size, 100000)
  expect_identical(m$algorithm, "xxh3")
  expect_identical(m$params, list(min = 64, avg = 256, max = 1024))
  expect_identical(length(m), nrow(t))
  expect_identical(as.data.frame(m), t)
})

test_that("raw, path and connection give the same manifest", {
  x <- splitmix_bytes(150000, "2")
  path <- withr::local_tempfile()
  writeBin(x, path)
  m <- dedup_manifest(x)
  expect_identical(dedup_manifest(path), m)
  con <- file(path)
  expect_identical(dedup_manifest(con), m)
})

test_that("SHA-256 over a connection has no object digest", {
  skip_if_not_installed("zucrypt")
  x <- splitmix_bytes(50000, "3")
  path <- withr::local_tempfile()
  writeBin(x, path)
  m <- dedup_manifest(x, hash = "sha256")
  expect_identical(dedup_manifest(path, hash = "sha256"), m)
  con <- rawConnection(x)
  on.exit(close(con))
  mc <- dedup_manifest(con, hash = "sha256")
  expect_true(is.na(mc$hash))
  expect_identical(mc$hashes, m$hashes)
  expect_identical(nchar(m$hashes[1]), 64L)
})

test_that("an empty object has an empty manifest with a digest", {
  m <- dedup_manifest(raw())
  expect_identical(length(m), 0L)
  expect_identical(m$size, 0)
  expect_identical(m$hash, "99aa06d3014798d86001c324468d497f")
  expect_identical(nrow(as.data.frame(m)), 0L)
})

test_that("a manifest prints as a summary", {
  m <- dedup_manifest(splitmix_bytes(20000, "4"))
  out <- format(m)
  expect_length(out, 3L)
  expect_match(out[1], "20,000 bytes in [0-9]+ chunks")
  expect_output(print(m), "dedup_manifest")
  expect_output(expect_invisible(print(m)))
  expect_match(format(dedup_manifest(raw(10)))[1], "1 chunk$")
})

test_that("bad arguments are refused", {
  x <- raw(10)
  expect_zudedup_error(dedup_manifest(x, 2048), "zudedup_invalid_argument", arg = "...")
  expect_zudedup_error(dedup_manifest(x, mn = 2048), "zudedup_invalid_argument", arg = "...")
  expect_zudedup_error(dedup_manifest(x, avg = 1000), "zudedup_invalid_argument", arg = "avg")
  expect_zudedup_error(dedup_manifest(x, hash = "md5"), "zudedup_invalid_argument", arg = "hash")
  expect_zudedup_error(dedup_manifest(x, hash = NA_character_), "zudedup_invalid_argument", arg = "hash")
  expect_zudedup_error(dedup_manifest(x, hash = 1), "zudedup_invalid_argument", arg = "hash")
  expect_zudedup_error(dedup_chunk(x, hash = c("sha256", "xxh3")), "zudedup_invalid_argument", arg = "hash")
})

test_that("the finish entry point refuses a state that does not hash", {
  st <- .Call(zudedup_cdc_init, 64, 256, 1024, FALSE)$state
  expect_identical(.Call(zudedup_cdc_finish, st)$status, "ZDD_ERR_STATE")
  expect_null(.Call(zudedup_xxh3, 1:3))
})
