# Design section 6.3: the boundaries do not depend on how the bytes arrive.

test_that("raw input split into blocks gives the same boundaries", {
  x <- fixture_bytes()
  for (p in fixture_params) {
    whole <- ends_in_blocks(x, NULL, p)
    for (block in c(7, 4096, 65536, 1048576)) {
      expect_identical(ends_in_blocks(x, block, p), whole,
                       info = paste(p$file, "block", block))
    }
  }
})

test_that("one byte at a time gives the same boundaries", {
  # The whole fixture a byte at a time is four million calls; a prefix long
  # enough for many cuts at the small parameters and a few at the defaults
  # covers the same code. The fuzzer covers arbitrary splits.
  x <- fixture_bytes()[seq_len(150000)]
  for (p in fixture_params) {
    expect_identical(ends_in_blocks(x, 1, p), ends_in_blocks(x, NULL, p),
                     info = p$file)
  }
})

test_that("a connection read in any block size gives the same table", {
  x <- fixture_bytes()
  p <- fixture_params$small
  want <- read_boundaries(p$file)
  for (block in c(4096, 65536, 1048576)) {
    con <- rawConnection(x)
    ends <- zdd_chunk_ends(con, zdd_check_params(p$min, p$avg, p$max),
                           block = block)
    close(con)
    expect_identical(ends, want$offset + want$length, info = block)
  }
})

test_that("a file path gives the same table as its bytes", {
  x <- fixture_bytes()
  path <- withr::local_tempfile()
  writeBin(x, path)
  expect_identical(no_hash(dedup_chunk(path)), read_boundaries("boundaries.tsv"))
})
