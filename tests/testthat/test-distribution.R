test_that("over 100 MB of random bytes, sizes stay in bounds and centre on avg", {
  skip_heavy()
  x <- splitmix_bytes(100 * 1024^2, "d15771b")
  t <- dedup_chunk(x)
  expect_valid_chunks(t, length(x), 2048, 65536)
  body <- t$length[-nrow(t)]
  expect_gte(min(body), 2049)
  expect_lt(abs(mean(body) - 8192) / 8192, 0.10)
})
