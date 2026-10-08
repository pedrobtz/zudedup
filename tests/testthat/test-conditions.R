test_that("every condition inherits zudedup_error and carries its fields", {
  e <- tryCatch(zdd_store_error("gone", hash = "ab", index = 3L),
                error = identity)
  expect_s3_class(e, c("zudedup_store_error", "zudedup_error", "error"))
  expect_identical(e$hash, "ab")
  expect_identical(e$index, 3L)

  e <- tryCatch(zdd_limit_error("max_chunks", 10, "too many"),
                error = identity)
  expect_s3_class(e, "zudedup_limit_error")
  expect_identical(e$limit, "max_chunks")
  expect_identical(e$limit_value, 10)

  e <- tryCatch(zdd_invalid_argument("avg", "bad"), error = identity)
  expect_s3_class(e, "zudedup_invalid_argument")
  expect_identical(e$arg, "avg")

  expect_error(zdd_algorithm_error("x"), class = "zudedup_algorithm_error")
  expect_error(zdd_io_error("x"), class = "zudedup_io_error")
})
