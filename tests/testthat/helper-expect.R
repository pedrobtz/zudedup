# Helpers shared by the test files. They live here, not at the top of a
# test file, because devtools::test(shuffle = TRUE) reorders a file's
# top-level expressions, definitions included.

# expr raises `class`, and each named field in `...` has the given value.
# Tests assert on classes and fields, never on message text.
expect_zudedup_error <- function(expr, class, ...) {
  e <- tryCatch(expr, error = identity)
  if (!inherits(e, "condition")) {
    fail(paste0("no error was raised; expected ", class))
    return(invisible(NULL))
  }
  expect_s3_class(e, c(class, "zudedup_error"))
  fields <- list(...)
  for (f in names(fields)) {
    expect_identical(e[[f]], fields[[f]], label = paste0("field `", f, "`"))
  }
  invisible(e)
}

# The parameters of the committed boundary fixtures.
fixture_params <- list(
  default = list(min = 2048, avg = 8192, max = 65536, file = "boundaries.tsv"),
  small = list(min = 64, avg = 256, max = 1024, file = "boundaries-small.tsv")
)

# The chunk table of a fixture, as committed.
read_boundaries <- function(file) {
  t <- utils::read.delim(test_path("fixtures", file), colClasses = "character")
  data.frame(offset = as.numeric(t$offset), length = as.integer(t$length))
}

# dedup_chunk()'s table for x is `table`, row for row.
expect_chunks <- function(x, table, ...) {
  expect_identical(dedup_chunk(x, ...), table)
}

# The invariants every chunk table has (design section 6.2): chunks tile the
# input, none is longer than max, and every chunk but the last is longer
# than min.
expect_valid_chunks <- function(table, size, min, max) {
  n <- nrow(table)
  expect_identical(sum(as.numeric(table$length)), as.numeric(size))
  expect_identical(table$offset, cumsum(c(0, as.numeric(table$length)))[seq_len(n)])
  expect_true(all(table$length <= max))
  if (n > 1) expect_true(all(table$length[-n] > min | table$length[-n] == max))
}
