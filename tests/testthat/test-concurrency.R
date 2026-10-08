# design section 8: two processes may put into one store at once, since each
# chunk is written to tmp/ and renamed into place, and identical chunks are
# identical files.

test_that("two processes putting the same object leave one copy of each chunk", {
  skip_heavy()
  skip_if_not_installed("callr")
  dir <- withr::local_tempdir()
  store <- dedup_store(file.path(dir, "store"), create = TRUE, min = 64, avg = 256,
                       max = 1024)
  x <- splitmix_bytes(2 * 1024^2, "1")
  data <- file.path(dir, "data.bin")
  writeBin(x, data)

  procs <- lapply(1:2, function(i) start_put(store$path, data))
  ms <- lapply(procs, function(p) {
    p$wait(120000)
    expect_identical(p$get_exit_status(), 0L)
    p$get_result()
  })

  expect_identical(ms[[1]], ms[[2]])
  expect_identical(ms[[1]], dedup_manifest(x, min = 64, avg = 256, max = 1024))
  expect_identical(sort(store$list()), sort(unique(ms[[1]]$hashes)))
  expect_length(list.files(file.path(store$path, "tmp")), 0L)
  expect_identical(dedup_get(store, ms[[1]]), x)
  expect_identical(dedup_verify(store), character())
})
