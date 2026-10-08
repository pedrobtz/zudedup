# Store maintenance (design section 8): verification and garbage collection.

#' Check every chunk in a store
#'
#' Reads every chunk the store lists and checks that its bytes hash to its
#' name. Needs a backend with `get` and `list`.
#'
#' @inheritParams dedup_put
#' @return The digests of the chunks that are corrupt (their bytes hash to
#'   another digest, or the store refuses to read them), as a character
#'   vector, empty when every chunk is sound.
#' @export
#' @examples
#' store <- dedup_store(tempfile(), create = TRUE)
#' dedup_put(store, serialize(mtcars, NULL))
#' dedup_verify(store)
dedup_verify <- function(store) {
  zdd_check_backend(store, "list")
  hashes <- zdd_backend_list(store)
  bad <- vapply(hashes, function(h) {
    b <- tryCatch(store$get(h), zudedup_store_error = function(e) NULL)
    is.null(b) || !is.raw(b) || zdd_digest(b, store$hash) != h
  }, TRUE, USE.NAMES = FALSE)
  hashes[bad]
}

#' Delete the chunks no manifest needs
#'
#' Deletes every chunk in the store that no manifest in `keep` references,
#' and, in a filesystem store, any partial writes left in `tmp/` by an
#' interrupted [dedup_put()].
#'
#' **Pass every manifest whose object you want to keep.** An object whose
#' manifest is not in `keep` loses the chunks it does not share with one
#' that is, and cannot be read again. zudedup keeps no list of manifests:
#' that is the caller's.
#'
#' `dedup_gc()` is not safe against a concurrent [dedup_put()], which may be
#' relying on a chunk it saw present: hold whatever lock your system provides
#' around it.
#'
#' @inheritParams dedup_put
#' @param keep A manifest, or a list of manifests, made with the store's hash
#'   and parameters.
#' @return The digests of the deleted chunks, invisibly.
#' @export
#' @examples
#' store <- dedup_store(tempfile(), create = TRUE)
#' m1 <- dedup_put(store, as.raw(sample(0:255, 100000, replace = TRUE)))
#' m2 <- dedup_put(store, as.raw(sample(0:255, 100000, replace = TRUE)))
#' length(dedup_gc(store, keep = m2))
#' length(dedup_missing(store, m2))
dedup_gc <- function(store, keep) {
  zdd_check_backend(store, c("delete", "list"))
  if (inherits(keep, "dedup_manifest")) keep <- list(keep)
  if (!is.list(keep)) {
    zdd_invalid_argument("keep", "`keep` must be a manifest or a list of manifests")
  }
  live <- character()
  for (i in seq_along(keep)) {
    m <- zdd_validate_manifest(keep[[i]], arg = "keep")
    zdd_check_same_algorithm(store, m)
    live <- c(live, unclass(m)$hashes)
  }
  dead <- setdiff(zdd_backend_list(store), live)
  if (length(dead)) store$delete(dead)
  if (identical(store$kind, "filesystem")) {
    unlink(list.files(file.path(store$path, "tmp"), full.names = TRUE, all.files = TRUE,
                      no.. = TRUE))
  }
  invisible(dead)
}

zdd_backend_list <- function(store) {
  l <- store$list()
  if (is.null(l)) l <- character()
  if (!is.character(l) || anyNA(l)) {
    zdd_store_error("the backend's list() must return the stored digests")
  }
  l
}
