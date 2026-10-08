test_that("chunk tables tile the input within the size bounds", {
  for (seed in c("1", "2", "3")) {
    x <- splitmix_bytes(300000, seed)
    for (p in fixture_params) {
      t <- dedup_chunk(x, min = p$min, avg = p$avg, max = p$max)
      expect_valid_chunks(t, length(x), p$min, p$max)
    }
  }
})

test_that("an empty input has no chunks", {
  t <- dedup_chunk(raw())
  expect_identical(t, data.frame(offset = numeric(), length = integer(),
                                 hash = character()))
  con <- rawConnection(raw())
  on.exit(close(con))
  expect_identical(dedup_chunk(con), t)
})

test_that("an input no longer than min is one chunk", {
  for (n in c(1, 100, 2048)) {
    x <- splitmix_bytes(n, "9")
    expect_identical(no_hash(dedup_chunk(x)), data.frame(offset = 0, length = as.integer(n)))
  }
})

test_that("input with no boundary is cut at max", {
  # Zero bytes give h a fixed point with low bits set, so no content cut.
  t <- dedup_chunk(raw(200000))
  expect_identical(t$length, as.integer(c(65536, 65536, 65536, 200000 - 3 * 65536)))
})

test_that("min == avg == max gives fixed-size chunks", {
  t <- dedup_chunk(splitmix_bytes(5000, "4"), min = 1024, avg = 1024, max = 1024)
  expect_identical(t$length, c(rep(1024L, 4), 904L))
})

test_that("an insertion changes only the chunks around it", {
  x <- splitmix_bytes(500000, "5")
  y <- c(x[1:200000], as.raw(1:50), x[200001:500000])
  a <- dedup_chunk(x)
  b <- dedup_chunk(y)
  # Every boundary before the insertion survives, and every boundary well
  # after it survives shifted by 50.
  expect_true(all(a$offset[a$offset < 190000] %in% b$offset))
  later <- a$offset[a$offset > 270000]
  expect_true(all((later + 50) %in% b$offset))
})

test_that("an open connection is read from its position and left open", {
  x <- splitmix_bytes(100000, "6")
  con <- rawConnection(x)
  on.exit(close(con))
  readBin(con, "raw", 1000)
  t <- dedup_chunk(con)
  expect_true(isOpen(con))
  expect_identical(t, dedup_chunk(x[-(1:1000)]))
})

test_that("bad parameters are refused, naming the argument", {
  x <- raw(10)
  expect_zudedup_error(dedup_chunk(x, avg = 5000), "zudedup_invalid_argument", arg = "avg")
  expect_zudedup_error(dedup_chunk(x, avg = 128), "zudedup_invalid_argument", arg = "avg")
  expect_zudedup_error(dedup_chunk(x, min = 63), "zudedup_invalid_argument", arg = "min")
  expect_zudedup_error(dedup_chunk(x, min = 2^26 + 1), "zudedup_invalid_argument", arg = "min")
  expect_zudedup_error(dedup_chunk(x, max = 2^30 + 1), "zudedup_invalid_argument", arg = "max")
  expect_zudedup_error(dedup_chunk(x, min = 2048.5), "zudedup_invalid_argument", arg = "min")
  expect_zudedup_error(dedup_chunk(x, min = NA), "zudedup_invalid_argument", arg = "min")
  expect_zudedup_error(dedup_chunk(x, min = c(64, 128)), "zudedup_invalid_argument", arg = "min")
  expect_zudedup_error(dedup_chunk(x, min = "64"), "zudedup_invalid_argument", arg = "min")
  expect_zudedup_error(dedup_chunk(x, min = 16384), "zudedup_invalid_argument", arg = "min")
  expect_zudedup_error(dedup_chunk(x, max = 4096), "zudedup_invalid_argument", arg = "max")
})

test_that("bad inputs are refused", {
  expect_zudedup_error(dedup_chunk(1:10), "zudedup_invalid_argument", arg = "x")
  expect_zudedup_error(dedup_chunk(c("a", "b")), "zudedup_invalid_argument", arg = "x")
  expect_zudedup_error(dedup_chunk(file.path(tempdir(), "no-such-file")),
                       "zudedup_invalid_argument", arg = "x")
  path <- withr::local_tempfile()
  writeLines("text", path)
  con <- file(path, "r")
  on.exit(close(con))
  expect_zudedup_error(dedup_chunk(con), "zudedup_invalid_argument", arg = "x")
})

test_that("C refuses parameters and states the R checks would catch", {
  r <- .Call(zudedup_cdc_init, 64, 300, 1024, TRUE)
  expect_identical(r$status, "ZDD_ERR_PARAMS")
  r <- .Call(zudedup_cdc_feed, as.raw(1:10), raw(5))
  expect_identical(r$status, "ZDD_ERR_STATE")
  ok <- .Call(zudedup_cdc_init, 64, 256, 1024, TRUE)$state
  bad <- ok
  bad[1] <- as.raw(0)
  expect_identical(.Call(zudedup_cdc_feed, bad, raw(5))$status, "ZDD_ERR_STATE")
  expect_identical(.Call(zudedup_cdc_feed, ok, 1:5)$status, "ZDD_ERR_STATE")
  expect_error(zdd_raise_status("ZDD_ERR_STATE"), class = "zudedup_error")
  expect_error(zdd_raise_status("ZDD_ERR_PARAMS"), class = "zudedup_invalid_argument")
})
