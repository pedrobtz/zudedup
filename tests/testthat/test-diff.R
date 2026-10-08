test_that("dedup_diff() splits digests and bytes between two versions", {
  x <- splitmix_bytes(200000, "1")
  y <- c(x[1:100000], as.raw(1:100), x[100001:200000])
  a <- dedup_manifest(x, min = 64, avg = 256, max = 1024)
  b <- dedup_manifest(y, min = 64, avg = 256, max = 1024)
  d <- dedup_diff(a, b)
  expect_named(d, c("shared", "added", "removed", "bytes_shared", "bytes_added",
                    "bytes_removed", "ratio"))
  expect_setequal(c(d$shared, d$added), unique(b$hashes))
  expect_setequal(c(d$shared, d$removed), unique(a$hashes))
  expect_identical(d$bytes_shared + d$bytes_added, b$size)
  expect_identical(d$ratio, d$bytes_shared / b$size)
  expect_true(length(d$added) <= 4 && length(d$removed) <= 3)
  expect_gt(d$ratio, 0.99)
})

test_that("identical and disjoint versions are the two extremes", {
  x <- dedup_manifest(splitmix_bytes(50000, "2"))
  y <- dedup_manifest(splitmix_bytes(50000, "3"))
  same <- dedup_diff(x, x)
  expect_identical(same$ratio, 1)
  expect_identical(same$added, character())
  expect_identical(same$bytes_removed, 0)
  apart <- dedup_diff(x, y)
  expect_identical(apart$ratio, 0)
  expect_identical(apart$shared, character())
  expect_identical(apart$bytes_removed, x$size)
  empty <- dedup_manifest(raw())
  expect_identical(dedup_diff(x, empty)$ratio, 1)
  expect_identical(dedup_diff(empty, x)$bytes_added, x$size)
})

test_that("a repeated chunk counts once as a digest and each time as bytes", {
  a <- dedup_manifest(raw(65536))
  b <- dedup_manifest(raw(3 * 65536))
  d <- dedup_diff(a, b)
  expect_identical(d$shared, a$hashes)
  expect_identical(d$bytes_shared, 3 * 65536)
  expect_identical(d$ratio, 1)
})

test_that("a moved chunk is still shared", {
  x <- splitmix_bytes(100000, "4")
  y <- c(x[50001:100000], x[1:50000])
  d <- dedup_diff(dedup_manifest(x), dedup_manifest(y))
  expect_gt(d$ratio, 0.7)
})

test_that("manifests made differently cannot be diffed", {
  x <- splitmix_bytes(10000, "5")
  expect_error(dedup_diff(dedup_manifest(x), dedup_manifest(x, min = 64, avg = 256, max = 1024)),
               class = "zudedup_algorithm_error")
  expect_zudedup_error(dedup_diff(dedup_manifest(x), list()), "zudedup_invalid_argument",
                       arg = "b")
  skip_if_not_installed("zucrypt")
  expect_error(dedup_diff(dedup_manifest(x), dedup_manifest(x, hash = "sha256")),
               class = "zudedup_algorithm_error")
})

test_that("1% of a 10 MB object changed at 100 points leaves most of it shared", {
  # design section 15. Each scattered edit costs about one chunk, and the chunk
  # a random point falls in is size-biased (about 11 KB at the defaults), so
  # 100 edits lose about 11% whatever their size: measured 0.889-0.896 over
  # three draws at Stage 4. The 95% the RFC asked for is not reachable with
  # 8 KiB chunks; 85% leaves room for the draw.
  skip_heavy()
  withr::local_seed(42)
  x <- splitmix_bytes(10 * 1024^2, "6")
  y <- x
  for (p in sample(length(x) - 1100, 100)) y[p + 0:1047] <- as.raw(sample(0:255, 1048, TRUE))
  d <- dedup_diff(dedup_manifest(x), dedup_manifest(y))
  expect_gt(d$ratio, 0.85)
})
