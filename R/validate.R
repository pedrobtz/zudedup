# A manifest is checked whole before any chunk is read (design section 12):
# a manifest can come from anywhere, and a bad one must be refused before it
# makes a store read or allocate anything. Each guard is marked
# "# GUARD: name"; test-validate.R has a crafted manifest for each, and
# tools/run-mutation-check proves each is load-bearing. The unmarked checks
# give a clearer message for a fault a later guard would also refuse.

zdd_hex_len <- c(xxh3 = 32L, sha256 = 64L)

zdd_validate_manifest <- function(m, max_chunks = 1e7, max_size = Inf,
                                  arg = "manifest", call = NULL) {
  bad <- function(why) {
    zdd_invalid_argument(arg, paste0("`", arg, "` is not a valid manifest: ", why),
                         call = call)
  }
  if (!inherits(m, "dedup_manifest")) bad("not a dedup_manifest") # GUARD: class
  m <- unclass(m)
  fields <- c("hashes", "lengths", "size", "hash", "algorithm", "params")
  if (!is.list(m) || !all(fields %in% names(m))) bad("fields are missing")

  alg <- m$algorithm
  if (!is.character(alg) || length(alg) != 1L || !alg %in% names(zdd_hex_len)) { # GUARD: manifest-algorithm
    bad("unknown algorithm")
  }
  p <- m$params
  if (!is.list(p) || !all(c("min", "avg", "max") %in% names(p))) bad("params are missing")
  p <- tryCatch(zdd_check_params(p$min, p$avg, p$max),
                zudedup_invalid_argument = function(e) bad("params are out of range"))

  h <- m$hashes
  n <- length(h)
  if (!is.character(h) || anyNA(h)) bad("`hashes` must be a character vector")
  if (n > max_chunks) { # GUARD: max-chunks
    zdd_limit_error("max_chunks", max_chunks, sprintf(
      "manifest has %d chunks, more than max_chunks = %s", n,
      format(max_chunks, scientific = FALSE)), call = call)
  }
  pattern <- sprintf("^[0-9a-f]{%d}$", zdd_hex_len[[alg]])
  if (!all(grepl(pattern, h))) bad("a digest is not lower-case hex of the algorithm's length") # GUARD: hashes-hex

  len <- m$lengths
  if (!is.integer(len) || length(len) != n || anyNA(len)) bad("`lengths` must be an integer per chunk") # GUARD: lengths-type
  if (n && (min(len) < 1L || max(len) > p$max)) bad("a chunk length is outside [1, max]") # GUARD: lengths-range

  size <- m$size
  if (!is.numeric(size) || length(size) != 1L || is.na(size) || size < 0) bad("`size` must be a byte count") # GUARD: size-type
  if (sum(as.numeric(len)) != size) bad("the chunk lengths do not sum to `size`") # GUARD: size-sum
  if (size > max_size) { # GUARD: max-size
    zdd_limit_error("max_size", max_size, sprintf(
      "manifest is %s bytes, more than max_size = %s", format(size, scientific = FALSE),
      format(max_size, scientific = FALSE)), call = call)
  }

  oh <- m$hash
  if (!is.character(oh) || length(oh) != 1L) bad("`hash` must be one digest") # GUARD: object-hash
  if (!is.na(oh) && !grepl(pattern, oh)) bad("`hash` is not hex of the algorithm's length") # GUARD: object-hex
  if (is.na(oh) && alg == "xxh3") bad("an XXH3 manifest always has its object digest") # GUARD: object-na
  invisible(structure(m, class = "dedup_manifest"))
}

zdd_check_limit <- function(x, arg, call = NULL) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || x < 0) {
    zdd_invalid_argument(arg, sprintf("`%s` must be a non-negative number", arg),
                         call = call)
  }
  x
}
