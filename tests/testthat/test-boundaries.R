# THE FORMAT GATE (design section 15). The committed tables were produced by
# the Stage 1 chunker and agreed with Python fastcdc 1.7.0 with zudedup's
# gear table substituted. If this fails, the chunker is wrong, not the
# fixture: never regenerate it.

test_that("the fixture input reproduces the committed boundaries", {
  x <- fixture_bytes()
  p <- fixture_params$default
  expect_chunks(x, read_boundaries(p$file), min = p$min, avg = p$avg, max = p$max)
})

test_that("the smallest parameters reproduce their committed boundaries", {
  x <- fixture_bytes()
  p <- fixture_params$small
  expect_chunks(x, read_boundaries(p$file), min = p$min, avg = p$avg, max = p$max)
})
