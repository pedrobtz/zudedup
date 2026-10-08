# The filesystem store and the store operations (design section 8). A store
# is a backend (R/backend.R); every function here takes any backend. Guards
# that refuse bad bytes are marked "# GUARD: name", with a test of that name
# in test-store.R, and tools/run-mutation-check proves each load-bearing.

zdd_store_format <- 1L

#' A content-addressed store in a directory
#'
#' Opens, or creates, a store that keeps each chunk once, in a file named by
#' its digest. The layout is:
#'
#' ```
#' <path>/
#'   zudedup.json      the hash algorithm, chunking parameters and format
#'   objects/ab/ab...  one file per chunk, under the first two hex digits
#'   tmp/              chunks are written here, then renamed into place
#' ```
#'
#' Writes go to `tmp/` and are renamed into `objects/`, so a chunk is either
#' complete or absent, and two processes may put into one store at once.
#' [dedup_gc()] is not safe against a concurrent put; take whatever lock
#' your system provides around it.
#'
#' The default hash, XXH3-128, is fast and not cryptographic: an adversary
#' who can write to the store and choose content can make two chunks with
#' the same digest. For a store that parties you do not trust write to, use
#' `hash = "sha256"`.
#'
#' @param path The store's directory.
#' @param create If `TRUE`, create the store when `path` does not hold one.
#'   An existing store is opened either way.
#' @param hash,min,avg,max The hash algorithm and chunking parameters of a new
#'   store, as for [dedup_chunk()]. An existing store keeps its own; giving
#'   different ones is an error, `zudedup_algorithm_error`.
#' @return A `dedup_backend` over the directory, which every store function
#'   accepts.
#' @seealso [dedup_backend()] for a store kept anywhere else.
#' @export
#' @examples
#' store <- dedup_store(file.path(tempdir(), "example-store"), create = TRUE)
#' store
#' m <- dedup_put(store, serialize(mtcars, NULL))
#' identical(unserialize(dedup_get(store, m)), mtcars)
dedup_store <- function(path, create = FALSE, hash = c("xxh3", "sha256"),
                        min = 2048, avg = 8192, max = 65536) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    zdd_invalid_argument("path", "`path` must be a single directory path")
  }
  if (!isTRUE(create) && !isFALSE(create)) {
    zdd_invalid_argument("create", "`create` must be TRUE or FALSE")
  }
  given <- !c(hash = missing(hash), min = missing(min), avg = missing(avg),
              max = missing(max))
  meta_path <- file.path(path, "zudedup.json")

  if (file.exists(meta_path)) {
    meta <- zdd_read_meta(meta_path)
    # Only what the call gave is compared: the store's own settings stand in
    # for the rest, so they are not checked against the defaults.
    asked <- list(hash = if (given[["hash"]]) zdd_check_hash(hash) else NA,
                  min = min, avg = avg, max = max)
    have <- list(hash = meta$algorithm, min = meta$min, avg = meta$avg, max = meta$max)
    same <- function(a, b) length(a) == 1L && isTRUE(a == b)
    differ <- given & !mapply(same, asked, have)
    if (any(differ)) {
      zdd_algorithm_error(sprintf(
        "the store at %s was made with %s; this call asked for %s", path,
        zdd_describe(have[differ]), zdd_describe(asked[differ])))
    }
    hash <- meta$algorithm
    params <- list(min = meta$min, avg = meta$avg, max = meta$max)
  } else {
    hash <- zdd_check_hash(hash)
    params <- zdd_check_params(min, avg, max)
    if (!create) {
      zdd_store_error(sprintf("no store at %s (create = TRUE makes one)", path))
    }
    if (dir.exists(path) && length(list.files(path, all.files = TRUE, no.. = TRUE))) {
      zdd_store_error(sprintf("%s exists and is not an empty directory or a store", path))
    }
    zdd_create_store(path, hash, params)
  }
  path <- normalizePath(path, mustWork = TRUE)
  zdd_fs_backend(path, hash, params)
}

zdd_describe <- function(x) {
  paste(names(x), vapply(x, function(v) format(v, scientific = FALSE), ""),
        sep = " = ", collapse = ", ")
}

zdd_create_store <- function(path, hash, params) {
  # The 256 prefix directories are made once, here, so a put need not ask.
  prefixes <- file.path("objects", sprintf("%02x", 0:255))
  for (d in file.path(path, c("", "objects", "tmp", prefixes))) {
    if (!dir.exists(d) && !dir.create(d, recursive = TRUE, showWarnings = FALSE)) {
      zdd_io_error(sprintf("could not create %s", d))
    }
  }
  meta <- list(format = zdd_store_format, algorithm = hash, min = params$min,
               avg = params$avg, max = params$max)
  tmp <- tempfile("meta-", tmpdir = file.path(path, "tmp"))
  jsonlite::write_json(meta, tmp, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  if (!file.rename(tmp, file.path(path, "zudedup.json"))) {
    unlink(tmp)
    zdd_io_error(sprintf("could not write %s", file.path(path, "zudedup.json")))
  }
}

zdd_read_meta <- function(meta_path) {
  meta <- tryCatch(jsonlite::read_json(meta_path, simplifyVector = TRUE),
                   error = function(e) NULL)
  ok <- is.list(meta) && identical(meta$format, zdd_store_format) &&
    is.character(meta$algorithm) && length(meta$algorithm) == 1L &&
    meta$algorithm %in% names(zdd_hex_len) &&
    !inherits(tryCatch(zdd_check_params(meta$min, meta$avg, meta$max),
                       error = identity), "error")
  if (!ok) {
    zdd_store_error(sprintf("%s is not a zudedup store's metadata (format %d)",
                            meta_path, zdd_store_format))
  }
  meta$min <- as.numeric(meta$min)
  meta$avg <- as.numeric(meta$avg)
  meta$max <- as.numeric(meta$max)
  meta
}

# The filesystem backend: five closures over the directory.
zdd_fs_backend <- function(path, hash, params) {
  objects <- file.path(path, "objects")
  tmpdir <- file.path(path, "tmp")
  pattern <- sprintf("^[0-9a-f]{%d}$", zdd_hex_len[[hash]])
  chunk_path <- function(h) file.path(objects, substr(h, 1L, 2L), h)

  has <- function(hashes) unname(file.exists(chunk_path(hashes)))
  get <- function(hash) {
    p <- chunk_path(hash)
    size <- file.size(p)
    if (is.na(size)) return(NULL)
    # A chunk file longer than the store's max is corrupt (design section 12):
    # refuse it before reading it into memory. Defence in depth, not a
    # GUARD: the length check in dedup_get() refuses the bytes anyway, so its
    # removal changes no outcome, only how much a corrupt file can allocate.
    if (size > params$max) {
      zdd_store_error(sprintf("chunk %s is %s bytes, more than max = %s", hash,
                              format(size, scientific = FALSE),
                              format(params$max, scientific = FALSE)),
                      hash = hash, problem = "corrupt")
    }
    tryCatch(readBin(p, "raw", n = size), error = function(e) NULL)
  }
  put <- function(hash, bytes) {
    dest <- chunk_path(hash)
    tmp <- tempfile("chunk-", tmpdir = tmpdir)
    ok <- tryCatch({ writeBin(bytes, tmp); TRUE }, error = function(e) FALSE)
    if (!ok) {
      unlink(tmp)
      zdd_io_error(sprintf("could not write chunk %s", hash))
    }
    # A rename onto a chunk that already exists, which two concurrent puts of
    # the same bytes cause, is success: the files are identical. The prefix
    # directory exists unless someone removed it; then it is made again.
    if (!suppressWarnings(file.rename(tmp, dest))) {
      dir.create(dirname(dest), showWarnings = FALSE)
      if (!suppressWarnings(file.rename(tmp, dest))) {
        unlink(tmp)
        if (!file.exists(dest)) zdd_io_error(sprintf("could not store chunk %s", hash))
      }
    }
    invisible()
  }
  delete <- function(hashes) {
    unlink(chunk_path(hashes))
    invisible()
  }
  list <- function() {
    f <- basename(list.files(objects, recursive = TRUE))
    f[grepl(pattern, f)]
  }
  zdd_new_backend(has, get, put, delete, list, hash, params, kind = "filesystem",
                  path = path)
}

#' Put an object into a store
#'
#' Chunks `x` with the store's parameters, asks the store which chunks it
#' already has, and writes only the others. Memory stays bounded for a
#' connection or a file: the store is asked once per 1 MiB block, about the
#' chunks completed in it.
#'
#' The default hash, XXH3-128, is not cryptographic; see [dedup_store()].
#'
#' @param store A [dedup_store()] or [dedup_backend()].
#' @inheritParams dedup_chunk
#' @return The object's [dedup_manifest()], invisibly. Keep it: it is the only
#'   way to get the object back.
#' @export
#' @examples
#' store <- dedup_store(tempfile(), create = TRUE)
#' v1 <- serialize(mtcars, NULL)
#' m1 <- dedup_put(store, v1)
#' # A second version that differs in one row writes only the changed chunks.
#' cars2 <- mtcars
#' cars2[5, 1] <- 99
#' m2 <- dedup_put(store, serialize(cars2, NULL))
#' mean(m2$hashes %in% m1$hashes)
dedup_put <- function(store, x) {
  zdd_check_backend(store)
  scan <- zdd_scan(x, store$params, store$hash, on_block = function(hashes, chunks) {
    keep <- !duplicated(hashes)
    hashes <- hashes[keep]
    chunks <- chunks[keep]
    present <- zdd_backend_has(store, hashes)
    for (i in which(!present)) store$put(hashes[i], chunks[[i]])
  })
  invisible(zdd_new_manifest(scan$table$hash, scan$table$length, scan$size,
                             scan$object, store$hash, store$params))
}

#' Get an object back from a store
#'
#' Reads the chunks of a manifest in order and reassembles the object,
#' checking that each chunk's bytes hash to its digest. A store cannot
#' substitute content: a missing or corrupt chunk is an error,
#' `zudedup_store_error`, naming the digest and the chunk's position. The
#' manifest is checked whole before any chunk is read.
#'
#' @inheritParams dedup_put
#' @param manifest A manifest from [dedup_put()] or [dedup_manifest()], made
#'   with the store's hash and parameters.
#' @param file If given, the path the object is written to, a chunk at a
#'   time, instead of being returned; the file is removed if a chunk fails.
#' @param verify If `FALSE`, skip the digest check, for a caller who has just
#'   written the chunks. Lengths are always checked.
#' @param max_chunks,max_size Limits on the manifest, checked before any
#'   chunk is read: the number of chunks, and the object's size in bytes
#'   (only when the object is returned in memory). Exceeding one is
#'   `zudedup_limit_error`.
#' @return A raw vector, or `file`, invisibly.
#' @export
#' @examples
#' store <- dedup_store(tempfile(), create = TRUE)
#' m <- dedup_put(store, charToRaw("hello"))
#' rawToChar(dedup_get(store, m))
dedup_get <- function(store, manifest, file = NULL, verify = TRUE,
                      max_chunks = 1e7, max_size = Inf) {
  zdd_check_backend(store)
  if (!isTRUE(verify) && !isFALSE(verify)) {
    zdd_invalid_argument("verify", "`verify` must be TRUE or FALSE")
  }
  if (!is.null(file) && (!is.character(file) || length(file) != 1L || is.na(file))) {
    zdd_invalid_argument("file", "`file` must be NULL or a single path")
  }
  max_chunks <- zdd_check_limit(max_chunks, "max_chunks")
  max_size <- zdd_check_limit(max_size, "max_size")
  m <- zdd_validate_manifest(manifest, max_chunks = max_chunks,
                             max_size = if (is.null(file)) max_size else Inf)
  zdd_check_same_algorithm(store, m)
  m <- unclass(m)
  n <- length(m$hashes)

  if (is.null(file)) {
    out <- raw(m$size)
    at <- 0
    for (i in seq_len(n)) {
      b <- zdd_get_chunk(store, m$hashes[i], m$lengths[i], i, verify)
      if (length(b)) out[at + seq_along(b)] <- b
      at <- at + length(b)
    }
    return(out)
  }

  con <- tryCatch(base::file(file, "wb"),
                  error = function(e) zdd_io_error(sprintf("could not open %s", file)),
                  warning = function(w) zdd_io_error(sprintf("could not open %s", file)))
  ok <- FALSE
  on.exit({
    close(con)
    if (!ok) unlink(file)
  })
  for (i in seq_len(n)) {
    writeBin(zdd_get_chunk(store, m$hashes[i], m$lengths[i], i, verify), con)
  }
  ok <- TRUE
  invisible(file)
}

# One chunk from a backend, refused unless it is all there and, when
# verifying, hashes to its name.
zdd_get_chunk <- function(store, hash, len, index, verify) {
  b <- store$get(hash)
  if (is.null(b)) { # GUARD: chunk-missing
    zdd_store_error(sprintf("chunk %d (%s) is missing from the store", index, hash),
                    hash = hash, index = index, problem = "missing")
  }
  if (!is.raw(b) || length(b) != len) { # GUARD: chunk-length
    zdd_store_error(sprintf("chunk %d (%s) is corrupt: expected %d bytes", index,
                            hash, len), hash = hash, index = index, problem = "corrupt")
  }
  if (verify && zdd_digest(b, store$hash) != hash) { # GUARD: chunk-digest
    zdd_store_error(sprintf("chunk %d (%s) is corrupt: its bytes hash to another digest",
                            index, hash), hash = hash, index = index, problem = "corrupt")
  }
  b
}

zdd_digest <- function(x, algorithm) {
  if (algorithm == "xxh3") zdd_xxh3_hex(x) else zdd_sha256_hex(x)
}

# A manifest made with another hash or other parameters than the store's
# would be stored, or read, under the wrong names (design section 7).
zdd_check_same_algorithm <- function(store, m, call = NULL) {
  m <- unclass(m)
  same <- identical(m$algorithm, store$hash) &&
    identical(as.numeric(unlist(m$params[c("min", "avg", "max")])),
              as.numeric(unlist(store$params[c("min", "avg", "max")])))
  if (!same) { # GUARD: store-algorithm
    zdd_algorithm_error(sprintf(
      "the manifest was made with %s (min %s, avg %s, max %s); the store uses %s (min %s, avg %s, max %s)",
      m$algorithm, m$params$min, m$params$avg, m$params$max,
      store$hash, store$params$min, store$params$avg, store$params$max), call = call)
  }
  invisible(m)
}

# has(), checked: a backend that answers with the wrong shape would make
# dedup_put() skip chunks it never wrote.
zdd_backend_has <- function(store, hashes) {
  if (!length(hashes)) return(logical())
  r <- store$has(hashes)
  if (!is.logical(r) || length(r) != length(hashes) || anyNA(r)) { # GUARD: has-shape
    zdd_store_error("the backend's has() must return TRUE or FALSE for each digest")
  }
  r
}

zdd_check_hashes <- function(store, hashes, arg = "hashes") {
  pattern <- sprintf("^[0-9a-f]{%d}$", zdd_hex_len[[store$hash]])
  if (!is.character(hashes) || anyNA(hashes) || !all(grepl(pattern, hashes))) {
    zdd_invalid_argument(arg, sprintf(
      "`%s` must be lower-case hex digests of the store's algorithm (%s)", arg,
      store$hash))
  }
  hashes
}

#' Which chunks a store has
#'
#' @inheritParams dedup_put
#' @param hashes Chunk digests, as lower-case hex.
#' @return For `dedup_has()`, a logical vector, `TRUE` where the store has
#'   the chunk. For `dedup_missing()`, the distinct digests of `manifest`
#'   the store lacks: what a [dedup_put()] of the object would write.
#' @export
#' @examples
#' store <- dedup_store(tempfile(), create = TRUE)
#' x <- as.raw(sample(0:255, 50000, replace = TRUE))
#' m <- dedup_manifest(x)
#' length(dedup_missing(store, m))
#' dedup_put(store, x)
#' dedup_has(store, m$hashes)
#' dedup_missing(store, m)
dedup_has <- function(store, hashes) {
  zdd_check_backend(store)
  zdd_backend_has(store, zdd_check_hashes(store, hashes))
}

#' @rdname dedup_has
#' @inheritParams dedup_get
#' @export
dedup_missing <- function(store, manifest) {
  zdd_check_backend(store)
  m <- unclass(zdd_validate_manifest(manifest))
  zdd_check_same_algorithm(store, m)
  u <- unique(m$hashes)
  u[!zdd_backend_has(store, u)]
}

#' Delete chunks from a store
#'
#' Removes the named chunks. An object whose manifest names a deleted chunk
#' can no longer be read; [dedup_gc()] is the safe way to reclaim space.
#'
#' @inheritParams dedup_has
#' @return `store`, invisibly.
#' @export
#' @examples
#' store <- dedup_store(tempfile(), create = TRUE)
#' m <- dedup_put(store, charToRaw("hello"))
#' dedup_delete(store, m$hashes)
#' dedup_has(store, m$hashes)
dedup_delete <- function(store, hashes) {
  zdd_check_backend(store, "delete")
  hashes <- zdd_check_hashes(store, hashes)
  if (length(hashes)) store$delete(unique(hashes))
  invisible(store)
}
