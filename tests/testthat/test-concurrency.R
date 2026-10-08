# design section 8: two processes may put into one store at once, since each
# chunk is written to tmp/ and renamed into place, and identical chunks are
# identical files.

test_that("two processes putting the same object leave one copy of each chunk", {
  skip_heavy()
  skip_if_not_installed("callr")
  dir <- withr::local_tempdir()
  # About a thousand chunks: enough for the two writers to overlap, few
  # enough for Windows, where each file creation and rename is slow (the
  # first run, at eight thousand chunks, outlasted a two-minute wait).
  store <- dedup_store(file.path(dir, "store"), create = TRUE, min = 512, avg = 2048,
                       max = 8192)
  x <- splitmix_bytes(2 * 1024^2, "1")
  data <- file.path(dir, "data.bin")
  writeBin(x, data)

  procs <- lapply(1:2, function(i) start_put(store$path, data))
  ms <- lapply(procs, function(p) {
    p$wait(600000)
    if (p$is_alive()) {
      p$kill()
      fail("a put did not finish within ten minutes")
    }
    expect_identical(p$get_exit_status(), 0L, info = p$read_all_error())
    p$get_result()
  })

  expect_identical(ms[[1]], ms[[2]])
  expect_identical(ms[[1]], dedup_manifest(x, min = 512, avg = 2048, max = 8192))
  expect_identical(sort(store$list()), sort(unique(ms[[1]]$hashes)))
  expect_length(list.files(file.path(store$path, "tmp")), 0L)
  expect_identical(dedup_get(store, ms[[1]]), x)
  expect_identical(dedup_verify(store), character())
})
