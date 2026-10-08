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
