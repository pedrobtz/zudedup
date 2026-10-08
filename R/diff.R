# Manifest diff (design section 10): which chunks two versions share.

#' What two versions of an object share
#'
#' Compares two manifests as sets of chunk digests. A chunk that moved is
#' still shared, so the comparison is order-insensitive. Both manifests must
#' come from the same hash algorithm and chunking parameters, or their
#' digests are not comparable (`zudedup_algorithm_error`).
#'
#' @param a,b Manifests, from [dedup_manifest()] or [dedup_put()]: `a` the
#'   old version, `b` the new.
#' @return A list: `shared`, `added` and `removed`, the distinct digests in
#'   both, only in `b` and only in `a`; `bytes_shared` and `bytes_added`,
#'   the bytes of `b` in chunks `a` has and in chunks it lacks (a chunk
#'   repeated in `b` counts each time, so the two sum to `b`'s size);
#'   `bytes_removed`, the bytes of `a` in chunks `b` lacks; and `ratio`,
#'   `bytes_shared` over `b`'s size (1 for an empty `b`): the fraction of
#'   the new version a store holding the old one already has.
#' @seealso [dedup_missing()] for the chunks a particular store lacks.
#' @export
#' @examples
#' x <- as.raw(sample(0:255, 300000, replace = TRUE))
#' y <- x
#' y[150000:150100] <- as.raw(0)
#' d <- dedup_diff(dedup_manifest(x), dedup_manifest(y))
#' d$ratio
#' length(d$added)
dedup_diff <- function(a, b) {
  a <- unclass(zdd_validate_manifest(a, arg = "a"))
  b <- unclass(zdd_validate_manifest(b, arg = "b"))
  same <- identical(a$algorithm, b$algorithm) &&
    identical(as.numeric(unlist(a$params)), as.numeric(unlist(b$params)))
  if (!same) {
    zdd_algorithm_error(sprintf(
      "the manifests were made with different hashes or parameters (%s, %s)",
      a$algorithm, b$algorithm))
  }
  in_a <- b$hashes %in% a$hashes
  bytes_shared <- sum(as.numeric(b$lengths[in_a]))
  list(
    shared = unique(b$hashes[in_a]),
    added = unique(b$hashes[!in_a]),
    removed = unique(a$hashes[!a$hashes %in% b$hashes]),
    bytes_shared = bytes_shared,
    bytes_added = sum(as.numeric(b$lengths[!in_a])),
    bytes_removed = sum(as.numeric(a$lengths[!a$hashes %in% b$hashes])),
    ratio = if (b$size > 0) bytes_shared / b$size else 1
  )
}
