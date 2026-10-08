# The backend interface (design section 9): the one piece of API other
# packages program against. A backend maps a digest to bytes and records what
# its chunks were made with; every store function takes one.

#' A store over your own functions
#'
#' Builds a store from functions that keep chunks wherever you like: an
#' environment, a database, object storage. zudedup asks for nothing but the
#' functions below; the filesystem store of [dedup_store()] is one such
#' backend.
#'
#' A backend also records the hash algorithm and chunking parameters its
#' chunks are made with. Every store function refuses a manifest made with
#' different ones, with `zudedup_algorithm_error`. The default hash,
#' XXH3-128, is fast and not cryptographic: for a store that parties you do
#' not trust can write to, use `hash = "sha256"`.
#'
#' @param has `function(hashes)`: a logical vector, one element per digest,
#'   `TRUE` where the chunk is stored.
#' @param get `function(hash)`: the chunk's bytes as a raw vector, or `NULL`
#'   if it is not stored.
#' @param put `function(hash, bytes)`: stores a chunk. It must be atomic:
#'   once it returns, `has(hash)` is `TRUE` only if `get(hash)` returns all
#'   of `bytes`, and a crash must not leave a partial chunk that `has()`
#'   reports. A second put of the same digest and bytes must be harmless.
#' @param delete `function(hashes)`, optional: removes chunks; needed by
#'   [dedup_delete()] and [dedup_gc()].
#' @param list `function()`, optional: the digests of every stored chunk;
#'   needed by [dedup_verify()] and [dedup_gc()].
#' @param hash,min,avg,max What the backend's chunks are made with, as for
#'   [dedup_chunk()].
#' @return A `dedup_backend`, which every store function accepts.
#' @export
#' @examples
#' env <- new.env()
#' store <- dedup_backend(
#'   has = function(hashes) vapply(hashes, exists, TRUE, envir = env,
#'                                 inherits = FALSE, USE.NAMES = FALSE),
#'   get = function(hash) get0(hash, envir = env, inherits = FALSE),
#'   put = function(hash, bytes) assign(hash, bytes, envir = env),
#'   delete = function(hashes) rm(list = hashes, envir = env),
#'   list = function() ls(env)
#' )
#' m <- dedup_put(store, serialize(mtcars, NULL))
#' identical(unserialize(dedup_get(store, m)), mtcars)
dedup_backend <- function(has, get, put, delete = NULL, list = NULL,
                          hash = c("xxh3", "sha256"), min = 2048, avg = 8192,
                          max = 65536) {
  zdd_check_fun(has, "has", 1L)
  zdd_check_fun(get, "get", 1L)
  zdd_check_fun(put, "put", 2L)
  if (!is.null(delete)) zdd_check_fun(delete, "delete", 1L)
  if (!is.null(list)) zdd_check_fun(list, "list", 0L)
  zdd_new_backend(has, get, put, delete, list, zdd_check_hash(hash),
                  zdd_check_params(min, avg, max), kind = "custom")
}

zdd_new_backend <- function(has, get, put, delete, list, hash, params, kind,
                            path = NULL) {
  structure(
    base::list(has = has, get = get, put = put, delete = delete, list = list,
               hash = hash, params = params, kind = kind, path = path),
    class = "dedup_backend"
  )
}

# A function that can be called with `arity` positional arguments: enough
# formals, or `...`. Formals without a default are not counted as required,
# since R functions often take optional arguments that way (missing()).
zdd_check_fun <- function(f, arg, arity) {
  if (!is.function(f)) {
    zdd_invalid_argument(arg, sprintf("`%s` must be a function", arg))
  }
  fm <- names(formals(args(f)))
  if (!"..." %in% fm && length(fm) < arity) {
    zdd_invalid_argument(arg, sprintf("`%s` must take %d argument%s", arg, arity,
                                      if (arity == 1L) "" else "s"))
  }
  invisible(f)
}

zdd_check_backend <- function(store, need = character(), call = NULL) {
  if (!inherits(store, "dedup_backend")) {
    zdd_invalid_argument("store", "`store` must be a dedup_store() or dedup_backend()",
                         call = call)
  }
  for (f in need) {
    if (is.null(store[[f]])) {
      zdd_invalid_argument("store", sprintf(
        "this backend has no `%s` function, which this operation needs", f),
        call = call)
    }
  }
  invisible(store)
}

#' @export
print.dedup_backend <- function(x, ...) {
  p <- x$params
  cat(sprintf("<dedup_backend> %s%s\n", x$kind,
              if (is.null(x$path)) "" else paste0(": ", x$path)))
  cat(sprintf("  hash:   %s%s\n", x$hash,
              if (x$hash == "xxh3") " (not cryptographic)" else ""))
  cat(sprintf("  params: min %s, avg %s, max %s\n", format(p$min, scientific = FALSE),
              format(p$avg, scientific = FALSE), format(p$max, scientific = FALSE)))
  invisible(x)
}
