# Crafted manifests for test-validate.R (design section 12).

good_manifest <- function(alg = "xxh3") {
  if (alg == "sha256") skip_if_not_installed("zucrypt")
  dedup_manifest(splitmix_bytes(5000, "11"), min = 64, avg = 256, max = 1024,
                 hash = alg)
}

with_field <- function(m, field, value) {
  m <- unclass(m)
  m[field] <- list(value)
  structure(m, class = "dedup_manifest")
}

expect_bad <- function(m, ...) {
  expect_zudedup_error(zdd_validate_manifest(m, ...), "zudedup_invalid_argument",
                       arg = "manifest")
}
