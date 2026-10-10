test_that("an object round-trips through every kind of store", {
  for (kind in store_kinds) {
    store <- local_store(kind, min = 64, avg = 256, max = 1024)
    x <- splitmix_bytes(60000, "1")
    m <- dedup_put(store, x)
    expect_s3_class(m, "dedup_manifest")
    expect_identical(m, dedup_manifest(x, min = 64, avg = 256, max = 1024))
    expect_identical(dedup_get(store, m), x, info = kind)
    expect_identical(dedup_get(store, m, verify = FALSE), x, info = kind)
    expect_identical(stored_count(store), length(unique(m$hashes)), info = kind)
  }
})

test_that("an empty object round-trips", {
  for (kind in store_kinds) {
    store <- local_store(kind)
    m <- dedup_put(store, raw())
    expect_identical(dedup_get(store, m), raw())
    expect_identical(stored_count(store), 0L)
  }
})

test_that("a put writes only the chunks the store lacks", {
  for (kind in store_kinds) {
    store <- local_store(kind, min = 64, avg = 256, max = 1024)
    x <- splitmix_bytes(80000, "2")
    y <- c(x[1:40000], as.raw(1:10), x[40001:80000])
    m1 <- dedup_put(store, x)
    expect_identical(dedup_missing(store, dedup_manifest(x, min = 64, avg = 256, max = 1024)),
                     character())
    m2 <- dedup_manifest(y, min = 64, avg = 256, max = 1024)
    missing <- dedup_missing(store, m2)
    expect_true(length(missing) > 0 && length(missing) < 5, info = kind)
    before <- stored_count(store)
    dedup_put(store, y)
    expect_identical(stored_count(store), before + length(missing), info = kind)
    expect_identical(dedup_missing(store, m2), character())
    expect_identical(dedup_get(store, m2), y)
  }
})

test_that("a repeated chunk is stored and checked once", {
  for (kind in store_kinds) {
    store <- local_store(kind)
    # Zero bytes cut at max, so this is the same 64 KiB chunk three times.
    x <- raw(3 * 65536)
    m <- dedup_put(store, x)
    expect_length(unique(m$hashes), 1L)
    expect_identical(stored_count(store), 1L)
    expect_identical(dedup_get(store, m), x)
  }
})

test_that("a connection and a file put in bounded blocks", {
  skip_under_torture()
  store <- local_store()
  x <- splitmix_bytes(3 * 1024^2, "3")
  path <- withr::local_tempfile()
  writeBin(x, path)
  calls <- 0L
  counted <- store
  counted$has <- function(hashes) {
    calls <<- calls + 1L
    store$has(hashes)
  }
  m <- dedup_put(counted, path)
  # One has() per 1 MiB block (design D18), not one for the whole object.
  expect_identical(calls, 4L)
  expect_identical(m, dedup_manifest(x))
  out <- withr::local_tempfile()
  expect_identical(dedup_get(store, m, file = out), out)
  expect_identical(readBin(out, "raw", n = length(x) + 1), x)
})

test_that("dedup_has() and dedup_delete() act on digests", {
  for (kind in store_kinds) {
    store <- local_store(kind, min = 64, avg = 256, max = 1024)
    m <- dedup_put(store, splitmix_bytes(5000, "4"))
    expect_identical(dedup_has(store, m$hashes), rep(TRUE, length(m)))
    expect_identical(dedup_has(store, character()), logical())
    dedup_delete(store, m$hashes[1:2])
    expect_identical(dedup_has(store, m$hashes[1:3]), c(FALSE, FALSE, TRUE))
    expect_invisible(dedup_delete(store, character()))
  }
})

test_that("a store records and enforces its algorithm and parameters", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "s")
  s <- dedup_store(path, create = TRUE, min = 64, avg = 256, max = 1024)
  meta <- zujson::json_parse_file(file.path(path, "zudedup.json"))
  expect_identical(meta, list(format = 1L, algorithm = "xxh3", min = 64L,
                              avg = 256L, max = 1024L))
  expect_true(dir.exists(file.path(path, c("objects", "tmp"))) |> all())
  # Reopening takes the store's own settings, and refuses different ones.
  s2 <- dedup_store(path)
  expect_identical(s2$params, list(min = 64, avg = 256, max = 1024))
  expect_identical(dedup_store(path, avg = 256)$hash, "xxh3")
  expect_identical(dedup_store(path, avg = 256L, hash = "xxh3")$hash, "xxh3")
  expect_error(dedup_store(path, avg = 512, max = 1024), class = "zudedup_algorithm_error")
  expect_error(dedup_store(path, hash = "sha256"), class = "zudedup_algorithm_error")
})

test_that("GUARD store-algorithm", {
  for (kind in store_kinds) {
    store <- local_store(kind, min = 64, avg = 256, max = 1024)
    x <- splitmix_bytes(3000, "5")
    m <- dedup_manifest(x)
    expect_error(dedup_get(store, m), class = "zudedup_algorithm_error")
    expect_error(dedup_missing(store, m), class = "zudedup_algorithm_error")
  }
  skip_if_not_installed("zucrypt")
  store <- local_store(min = 64, avg = 256, max = 1024)
  m <- dedup_manifest(splitmix_bytes(3000, "5"), min = 64, avg = 256, max = 1024,
                      hash = "sha256")
  expect_error(dedup_get(store, m), class = "zudedup_algorithm_error")
})

test_that("GUARD chunk-missing", {
  for (kind in store_kinds) {
    store <- local_store(kind, min = 64, avg = 256, max = 1024)
    m <- dedup_put(store, splitmix_bytes(5000, "6"))
    dedup_delete(store, m$hashes[3])
    expect_zudedup_error(dedup_get(store, m), "zudedup_store_error",
                         hash = m$hashes[3], index = 3L, problem = "missing")
  }
})

test_that("GUARD chunk-length", {
  for (kind in store_kinds) {
    store <- local_store(kind, min = 64, avg = 256, max = 1024)
    m <- dedup_put(store, splitmix_bytes(5000, "7"))
    corrupt_chunk(store, m$hashes[2], as.raw(1:10))
    expect_zudedup_error(dedup_get(store, m, verify = FALSE), "zudedup_store_error",
                         hash = m$hashes[2], index = 2L, problem = "corrupt")
  }
})

test_that("GUARD chunk-digest", {
  for (kind in store_kinds) {
    store <- local_store(kind, min = 64, avg = 256, max = 1024)
    x <- splitmix_bytes(5000, "8")
    m <- dedup_put(store, x)
    bad <- splitmix_bytes(m$lengths[4], "0bad")
    corrupt_chunk(store, m$hashes[4], bad)
    expect_zudedup_error(dedup_get(store, m), "zudedup_store_error",
                         hash = m$hashes[4], index = 4L, problem = "corrupt")
    # verify = FALSE is what lets substituted bytes through.
    expect_identical(length(dedup_get(store, m, verify = FALSE)), length(x))
  }
})

test_that("an oversized chunk file is refused before it is read", {
  store <- local_store(min = 64, avg = 256, max = 1024)
  m <- dedup_put(store, splitmix_bytes(5000, "9"))
  corrupt_chunk(store, m$hashes[1], raw(2000))
  # Defence in depth: refused by the backend, so index is not known there.
  expect_zudedup_error(dedup_get(store, m), "zudedup_store_error",
                       hash = m$hashes[1], index = NA_integer_, problem = "corrupt")
})

test_that("GUARD has-shape", {
  inner <- local_store("environment")
  for (bad in list(function(h) TRUE, function(h) rep(NA, length(h)),
                   function(h) rep(1L, length(h)))) {
    store <- inner
    store$has <- bad
    expect_zudedup_error(dedup_put(store, splitmix_bytes(50000, "10")),
                         "zudedup_store_error")
  }
})

test_that("a failed get to a file leaves no file", {
  store <- local_store(min = 64, avg = 256, max = 1024)
  m <- dedup_put(store, splitmix_bytes(5000, "11"))
  dedup_delete(store, m$hashes[length(m)])
  out <- withr::local_tempfile()
  expect_error(dedup_get(store, m, file = out), class = "zudedup_store_error")
  expect_false(file.exists(out))
})

test_that("limits are checked before any chunk is read", {
  store <- local_store(min = 64, avg = 256, max = 1024)
  m <- dedup_put(store, splitmix_bytes(5000, "12"))
  reads <- 0L
  counted <- store
  counted$get <- function(hash) {
    reads <<- reads + 1L
    store$get(hash)
  }
  expect_zudedup_error(dedup_get(counted, m, max_chunks = 2), "zudedup_limit_error",
                       limit = "max_chunks")
  expect_zudedup_error(dedup_get(counted, m, max_size = 100), "zudedup_limit_error",
                       limit = "max_size")
  expect_identical(reads, 0L)
  # max_size bounds memory, so it does not apply when writing to a file.
  out <- withr::local_tempfile()
  expect_identical(dedup_get(counted, m, file = out, max_size = 100), out)
})

test_that("bad arguments are refused", {
  store <- local_store()
  m <- dedup_put(store, raw(10))
  expect_zudedup_error(dedup_get(list(), m), "zudedup_invalid_argument", arg = "store")
  expect_zudedup_error(dedup_get(store, unclass(m)), "zudedup_invalid_argument", arg = "manifest")
  expect_zudedup_error(dedup_get(store, m, verify = NA), "zudedup_invalid_argument", arg = "verify")
  expect_zudedup_error(dedup_get(store, m, file = 1), "zudedup_invalid_argument", arg = "file")
  expect_zudedup_error(dedup_get(store, m, max_chunks = -1), "zudedup_invalid_argument", arg = "max_chunks")
  expect_zudedup_error(dedup_has(store, "xyz"), "zudedup_invalid_argument", arg = "hashes")
  expect_zudedup_error(dedup_has(store, NA_character_), "zudedup_invalid_argument", arg = "hashes")
  expect_zudedup_error(dedup_store(c("a", "b")), "zudedup_invalid_argument", arg = "path")
  expect_zudedup_error(dedup_store(tempfile(), create = NA), "zudedup_invalid_argument", arg = "create")
})

test_that("a missing or unusable store is refused", {
  dir <- withr::local_tempdir()
  expect_error(dedup_store(file.path(dir, "none")), class = "zudedup_store_error")
  writeLines("x", file.path(dir, "stray"))
  expect_error(dedup_store(dir, create = TRUE), class = "zudedup_store_error")
  bad <- file.path(dir, "bad")
  dir.create(bad)
  writeLines("{\"format\": 2}", file.path(bad, "zudedup.json"))
  expect_error(dedup_store(bad), class = "zudedup_store_error")
  writeLines("not json", file.path(bad, "zudedup.json"))
  expect_error(dedup_store(bad), class = "zudedup_store_error")
})

test_that("a backend missing delete cannot delete", {
  e <- new.env()
  store <- dedup_backend(
    has = function(h) vapply(h, exists, TRUE, envir = e, inherits = FALSE, USE.NAMES = FALSE),
    get = function(h) get0(h, envir = e, inherits = FALSE),
    put = function(h, b) assign(h, b, envir = e)
  )
  m <- dedup_put(store, splitmix_bytes(20000, "13"))
  expect_zudedup_error(dedup_delete(store, m$hashes), "zudedup_invalid_argument", arg = "store")
})

test_that("dedup_backend() checks its functions", {
  f1 <- function(x) TRUE
  f2 <- function(h, b) NULL
  expect_zudedup_error(dedup_backend(1, f1, f2), "zudedup_invalid_argument", arg = "has")
  expect_zudedup_error(dedup_backend(f1, f1, f1), "zudedup_invalid_argument", arg = "put")
  expect_zudedup_error(dedup_backend(f1, function() 1, f2), "zudedup_invalid_argument", arg = "get")
  expect_zudedup_error(dedup_backend(f1, f1, f2, delete = "x"), "zudedup_invalid_argument", arg = "delete")
  expect_zudedup_error(dedup_backend(f1, f1, f2, avg = 3), "zudedup_invalid_argument", arg = "avg")
  b <- dedup_backend(f1, function(...) NULL, f2, list = function() character())
  expect_s3_class(b, "dedup_backend")
  expect_output(print(b), "not cryptographic")
  expect_output(print(local_store()), "filesystem")
})

test_that("two puts of the same chunk leave one file", {
  store <- local_store(min = 64, avg = 256, max = 1024)
  x <- splitmix_bytes(3000, "14")
  m <- dedup_put(store, x)
  # A second put of a present chunk, as a concurrent writer would make.
  store$put(m$hashes[1], dedup_get(store, m)[seq_len(m$lengths[1])])
  expect_identical(dedup_get(store, m), x)
  expect_length(list.files(file.path(store$path, "tmp")), 0L)
  expect_identical(stored_count(store), length(unique(m$hashes)))
})

test_that("SHA-256 stores round-trip and check SHA-256 digests", {
  skip_if_not_installed("zucrypt")
  for (kind in store_kinds) {
    store <- local_store(kind, hash = "sha256", min = 64, avg = 256, max = 1024)
    x <- splitmix_bytes(10000, "15")
    m <- dedup_put(store, x)
    expect_identical(m$algorithm, "sha256")
    expect_identical(dedup_get(store, m), x)
    corrupt_chunk(store, m$hashes[2], splitmix_bytes(m$lengths[2], "0bad2"))
    expect_error(dedup_get(store, m), class = "zudedup_store_error")
  }
})
