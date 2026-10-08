test_that("SplitMix64 gives its published outputs", {
  # The reference stream for seed 0 (Vigna's splitmix64.c).
  expect_identical(
    u64_to_hex(splitmix64(3, "0")),
    c("e220a8397b1dcdaf", "6e789e6aa1b965f4", "06c45d188009454f")
  )
})

test_that("the compiled gear table regenerates from its seed", {
  # design section 6.1: the table is a format constant. If this fails, the
  # header was edited; regenerate it with tools/make-gear.R, never the test.
  table <- .Call(zudedup_gear_table)
  expect_identical(table, gear_table())
})

test_that("every gear entry is below 2^63", {
  # (h >> 1) + G[b] must never overflow, or Python's fastcdc, which has
  # unbounded integers, would compute a different h.
  first <- strtoi(substr(.Call(zudedup_gear_table), 1, 1), 16L)
  expect_true(all(first < 8L))
})

test_that("the fixture input is the documented SplitMix64 stream", {
  x <- fixture_bytes()
  expect_length(x, 4 * 1024^2)
  expect_identical(x[1:16], bytes("f80e7118cacca735 2a2ceb23bfd9996e"))
})
