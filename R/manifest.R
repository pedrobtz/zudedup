# Manifests (design section 5): the ordered chunk digests of one object, its
# size and its own digest, with what made them.

#' The manifest of an object
#'
#' Chunks an object and records, in order, the digest and length of every
#' chunk, the object's size and the digest of the whole object. Two objects
#' whose manifests have the same `hashes` have the same bytes, up to the
#' strength of the hash; two versions of an object share the digests of the
#' chunks they share.
#'
#' The default hash, XXH3-128, is fast and not cryptographic: an adversary
#' who chooses content can make two chunks with the same digest. Use
#' `hash = "sha256"` for anything shared across a trust boundary.
#'
#' @inheritParams dedup_chunk
#' @param ... `min`, `avg` and `max`, as for [dedup_chunk()].
#' @return A `dedup_manifest`: a list of `hashes` (the chunk digests, in
#'   order, as lower-case hex), `lengths` (integer), `size` (the object's
#'   length in bytes, a double), `hash` (the digest of the whole object),
#'   `algorithm` (`"xxh3"` or `"sha256"`) and `params` (`min`, `avg`,
#'   `max`). For XXH3 the object digest is what [zufast::fast_hash()] and
#'   `xxhsum -H2` give for the same bytes. With `hash = "sha256"` and a
#'   connection, which cannot be read twice, it is `NA`.
#'
#'   It prints as a summary; [as.data.frame()] gives the chunk table and
#'   [length()] the number of chunks.
#' @seealso [dedup_chunk()] for the chunk table alone.
#' @export
#' @examples
#' x <- serialize(mtcars, NULL)
#' m <- dedup_manifest(x, min = 64, avg = 256, max = 1024)
#' m
#' head(as.data.frame(m))
dedup_manifest <- function(x, ..., hash = c("xxh3", "sha256")) {
  dots <- list(...)
  bad <- setdiff(names(dots), c("min", "avg", "max"))
  if (length(dots) && (is.null(names(dots)) || any(!nzchar(names(dots))) ||
                       length(bad))) {
    zdd_invalid_argument("...", "`...` takes only `min`, `avg` and `max`")
  }
  defaults <- list(min = 2048, avg = 8192, max = 65536)
  defaults[names(dots)] <- dots
  params <- zdd_check_params(defaults$min, defaults$avg, defaults$max)
  hash <- zdd_check_hash(hash)
  scan <- zdd_scan(x, params, hash)
  zdd_new_manifest(scan$table$hash, scan$table$length, scan$size,
                   scan$object, hash, params)
}

zdd_new_manifest <- function(hashes, lengths, size, hash, algorithm, params) {
  structure(
    list(hashes = hashes, lengths = lengths, size = as.numeric(size),
         hash = hash, algorithm = algorithm,
         params = list(min = params$min, avg = params$avg, max = params$max)),
    class = "dedup_manifest"
  )
}

#' @export
length.dedup_manifest <- function(x) length(.subset2(x, "hashes"))

#' @export
format.dedup_manifest <- function(x, ...) {
  x <- unclass(x)
  n <- length(x$hashes)
  p <- x$params
  c(
    sprintf("<dedup_manifest> %s bytes in %d chunk%s", format(x$size, big.mark = ",",
            scientific = FALSE), n, if (n == 1L) "" else "s"),
    sprintf("  hash:   %s %s", x$algorithm, if (is.na(x$hash)) "NA" else x$hash),
    sprintf("  params: min %s, avg %s, max %s", format(p$min, scientific = FALSE),
            format(p$avg, scientific = FALSE), format(p$max, scientific = FALSE))
  )
}

#' @export
print.dedup_manifest <- function(x, ...) {
  writeLines(format(x, ...))
  invisible(x)
}

#' @export
as.data.frame.dedup_manifest <- function(x, ...) {
  x <- unclass(x)
  ends <- cumsum(as.numeric(x$lengths))
  data.frame(offset = ends - x$lengths, length = x$lengths, hash = x$hashes)
}
