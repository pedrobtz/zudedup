test_that("dedup_gc() keeps what the manifests need and nothing else", {
  for (kind in store_kinds) {
    store <- local_store(kind, min = 64, avg = 256, max = 1024)
    x <- splitmix_bytes(30000, "1")
    y <- c(x[1:15000], splitmix_bytes(15000, "2"))
    mx <- dedup_put(store, x)
    my <- dedup_put(store, y)
    only_x <- setdiff(mx$hashes, my$hashes)
    deleted <- dedup_gc(store, keep = my)
    expect_setequal(deleted, only_x)
    expect_identical(dedup_get(store, my), y, info = kind)
    expect_identical(sort(store$list()), sort(unique(my$hashes)))
    # Keeping both, or keeping a list, deletes nothing more.
    expect_identical(dedup_gc(store, keep = list(my)), character())
    expect_error(dedup_get(store, mx), class = "zudedup_store_error")
  }
})

test_that("dedup_gc() with nothing to keep empties the store", {
  store <- local_store()
  dedup_put(store, splitmix_bytes(20000, "3"))
  dedup_gc(store, keep = list())
  expect_identical(store$list(), character())
})

test_that("dedup_gc() removes partial writes a crash left in tmp/", {
  store <- local_store()
  m <- dedup_put(store, splitmix_bytes(20000, "4"))
  # A put interrupted between write and rename leaves its temporary file.
  stray <- file.path(store$path, "tmp", "chunk-interrupted")
  writeBin(as.raw(1:100), stray)
  expect_identical(dedup_get(store, m), splitmix_bytes(20000, "4"))
  dedup_gc(store, keep = m)
  expect_false(file.exists(stray))
  expect_identical(dedup_get(store, m), splitmix_bytes(20000, "4"))
})

test_that("dedup_gc() refuses foreign manifests and incapable backends", {
  store <- local_store(min = 64, avg = 256, max = 1024)
  m <- dedup_manifest(splitmix_bytes(1000, "5"))
  expect_error(dedup_gc(store, keep = m), class = "zudedup_algorithm_error")
  expect_zudedup_error(dedup_gc(store, keep = "x"), "zudedup_invalid_argument", arg = "keep")
  expect_zudedup_error(dedup_gc(store, keep = list(1)), "zudedup_invalid_argument", arg = "keep")
  bare <- store
  bare$list <- NULL
  expect_zudedup_error(dedup_gc(bare, keep = list()), "zudedup_invalid_argument", arg = "store")
  expect_zudedup_error(dedup_verify(bare), "zudedup_invalid_argument", arg = "store")
  bad <- store
  bad$list <- function() 1:3
  expect_error(dedup_gc(bad, keep = list()), class = "zudedup_store_error")
})

test_that("dedup_verify() names the corrupt chunks", {
  for (kind in store_kinds) {
    store <- local_store(kind, min = 64, avg = 256, max = 1024)
    m <- dedup_put(store, splitmix_bytes(20000, "6"))
    expect_identical(dedup_verify(store), character())
    corrupt_chunk(store, m$hashes[3], splitmix_bytes(m$lengths[3], "0bad"))
    corrupt_chunk(store, m$hashes[5], as.raw(1:3))
    expect_setequal(dedup_verify(store), m$hashes[c(3, 5)])
  }
  store <- local_store(min = 64, avg = 256, max = 1024)
  m <- dedup_put(store, splitmix_bytes(5000, "7"))
  corrupt_chunk(store, m$hashes[1], raw(5000))
  expect_identical(dedup_verify(store), m$hashes[1])
})
