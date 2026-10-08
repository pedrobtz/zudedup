# Content-defined chunking (design section 6): R reads blocks, the chunker in
# src/zdd_cdc.c finds the boundaries, and its state crosses each .Call as a
# raw vector, so the boundaries do not depend on the block size. Hashing
# (design section 7) happens in the same pass: XXH3-128 in C, SHA-256 here
# through zucrypt.

# A connection is read in blocks of this many bytes (design section 5).
zdd_block_size <- 1048576L

#' Split bytes into content-defined chunks
#'
#' Finds chunk boundaries with FastCDC: a gear rolling hash over the bytes,
#' with normalised chunking so that sizes cluster around `avg`. A boundary
#' depends only on the bytes near it, so an insertion or deletion changes
#' the chunks around it and leaves the rest alone. The same bytes give the
#' same chunks on every platform and in every version of zudedup, however
#' they are read.
#'
#' The default hash, XXH3-128, is fast and not cryptographic: an adversary
#' who chooses content can make two chunks with the same digest. Use
#' `hash = "sha256"` where that matters.
#'
#' @param x A raw vector, a connection, or the path of a file. A connection
#'   that is not open is opened, read and closed; an open one must be in
#'   binary mode and is read from its current position to its end, in blocks
#'   of 1 MiB.
#' @param min,avg,max Chunk sizes in bytes. No chunk is shorter than `min`
#'   except the last, none is longer than `max`, and the mean is close to
#'   `avg`, which must be a power of two. `min` is in \[64, 2^26\], `avg`
#'   in \[256, 2^28\] and `max` in \[1024, 2^30\], with
#'   `min <= avg <= max`.
#' @param hash The digest of each chunk: `"xxh3"` (XXH3-128, 32 hex
#'   characters, the default) or `"sha256"` (64 hex characters, needs the
#'   zucrypt package).
#' @return A data frame with one row per chunk, in order: `offset`, the
#'   0-based position of its first byte (a double, since inputs may exceed
#'   2^31 bytes), `length`, its size in bytes (an integer), and `hash`, its
#'   digest in lower-case hex. An empty input has no chunks.
#' @seealso [dedup_manifest()] for the chunk digests with the object's own;
#'   [zudedup-conditions] for the errors raised.
#' @export
#' @examples
#' x <- as.raw(sample(0:255, 200000, replace = TRUE))
#' chunks <- dedup_chunk(x)
#' head(chunks)
#' sum(chunks$length) == length(x)
#'
#' # An insertion near the start leaves the later chunks in place.
#' y <- c(as.raw(1:100), x)
#' mean(dedup_chunk(y)$hash %in% chunks$hash)
dedup_chunk <- function(x, min = 2048, avg = 8192, max = 65536,
                        hash = c("xxh3", "sha256")) {
  params <- zdd_check_params(min, avg, max)
  hash <- zdd_check_hash(hash)
  zdd_scan(x, params, hash)$table
}

zdd_check_hash <- function(hash, call = NULL) {
  if (!is.character(hash) || length(hash) < 1L || is.na(hash[1L])) {
    zdd_invalid_argument("hash", "`hash` must be \"xxh3\" or \"sha256\"", call = call)
  }
  if (identical(hash, c("xxh3", "sha256"))) hash <- "xxh3"
  if (length(hash) != 1L || !hash %in% c("xxh3", "sha256")) {
    zdd_invalid_argument("hash", "`hash` must be \"xxh3\" or \"sha256\"", call = call)
  }
  if (hash == "sha256" && !requireNamespace("zucrypt", quietly = TRUE)) {
    zdd_invalid_argument("hash", "`hash = \"sha256\"` needs the zucrypt package",
                         call = call)
  }
  hash
}

# One pass over x: the chunk table, the object digest and the size. `hash`
# is "xxh3", "sha256" or "none" (boundaries only). `block` is the block size
# for a connection, and also splits a raw vector, which only the tests ask
# for: nothing may depend on it. `on_block`, if given, is called after each
# block with the table rows completed in it and their bytes' source, so a
# store can write them while memory stays bounded (design section 8).
zdd_scan <- function(x, params, hash, block = NULL, on_block = NULL) {
  in_c <- hash == "xxh3"
  st <- zdd_call(.Call(zudedup_cdc_init, params$min, params$avg, params$max, in_c))
  ends <- list()
  hashes <- list()
  done <- 0
  carry <- raw()          # sha256: the bytes of the chunk in progress
  is_path <- is.character(x) && length(x) == 1L &&
    !grepl("^(https?|ftps?|file)://", x, ignore.case = TRUE)

  feed <- function(b) {
    r <- zdd_call(.Call(zudedup_cdc_feed, st$state, b))
    st <<- r
    cuts <- r$cuts
    h <- r$hashes
    chunk_bytes <- NULL
    if (hash == "sha256" || !is.null(on_block)) {
      chunk_bytes <- zdd_split_block(carry, b, cuts)
      carry <<- chunk_bytes$carry
      if (hash == "sha256") h <- vapply(chunk_bytes$chunks, zdd_sha256_hex, "")
    }
    if (length(cuts)) {
      ends[[length(ends) + 1L]] <<- done + cuts
      if (hash != "none") hashes[[length(hashes) + 1L]] <<- h
    }
    if (!is.null(on_block) && length(cuts)) {
      on_block(h, chunk_bytes$chunks)
    }
    done <<- done + length(b)
  }

  if (is.raw(x)) {
    if (is.null(block) || length(x) <= block) {
      if (length(x)) feed(x)
    } else {
      for (s in seq(1, length(x), by = block)) {
        feed(x[s:min(s + block - 1, length(x))])
      }
    }
  } else {
    input <- zdd_open_input(x)
    if (input$close) on.exit(close(input$con), add = TRUE)
    block <- if (is.null(block)) zdd_block_size else block
    repeat {
      b <- tryCatch(readBin(input$con, "raw", n = block),
                    error = function(e) zdd_io_error(conditionMessage(e)))
      if (length(b) == 0L) break
      feed(b)
    }
  }

  ends <- as.numeric(unlist(ends, use.names = FALSE))
  hashes <- as.character(unlist(hashes, use.names = FALSE))
  object <- NA_character_
  pending <- if (is.null(st$pending)) 0 else st$pending
  if (pending > 0) {
    # The chunk in progress at the end of the input is the last chunk.
    ends <- c(ends, done)
    last <- switch(hash,
      xxh3 = zdd_call(.Call(zudedup_cdc_finish, st$state))$last,
      sha256 = zdd_sha256_hex(carry),
      none = NULL
    )
    hashes <- c(hashes, last)
    if (!is.null(on_block)) on_block(last, list(carry))
  }
  if (hash == "xxh3") {
    object <- zdd_call(.Call(zudedup_cdc_finish, st$state))$object
  } else if (hash == "sha256") {
    # zucrypt has no incremental interface, so the object digest needs the
    # bytes again: from the raw vector, or by reading a path a second time.
    # Another connection cannot be read twice, and the digest is NA (D15).
    if (is.raw(x)) {
      object <- zdd_sha256_hex(x)
    } else if (is_path) {
      object <- zdd_sha256_hex(file(x))
    }
  }

  starts <- c(0, ends)[seq_along(ends)]
  table <- data.frame(offset = starts, length = as.integer(ends - starts))
  if (hash != "none") table$hash <- hashes
  list(table = table, object = object, size = done)
}

# The chunks a block completes, as raw vectors, and the bytes left over to
# carry into the next block. `carry` is the start of the first chunk, from
# earlier blocks.
zdd_split_block <- function(carry, b, cuts) {
  chunks <- vector("list", length(cuts))
  from <- 1
  for (i in seq_along(cuts)) {
    piece <- if (cuts[i] >= from) b[from:cuts[i]] else raw()
    chunks[[i]] <- if (i == 1L && length(carry)) c(carry, piece) else piece
    from <- cuts[i] + 1
  }
  rest <- if (from <= length(b)) b[from:length(b)] else raw()
  carry <- if (length(cuts)) rest else c(carry, rest)
  list(chunks = chunks, carry = carry)
}

zdd_sha256_hex <- function(x) {
  d <- zucrypt::crypt_hash(x, "sha256")
  paste(sprintf("%02x", as.integer(d)), collapse = "")
}

zdd_xxh3_hex <- function(x) .Call(zudedup_xxh3, x)

# The 0-based end offset of every chunk of x: boundaries only.
zdd_chunk_ends <- function(x, params, block = NULL) {
  t <- zdd_scan(x, params, "none", block = block)$table
  t$offset + t$length
}

# zu_open_input() with zudedup's conditions.
zdd_open_input <- function(x) {
  if (!inherits(x, "connection") && !is.character(x)) {
    zdd_invalid_argument("x", "`x` must be a raw vector, a connection or a file path")
  }
  zu_open_input(x, what = "x", prefix = "zudedup",
                abort = function(arg, message) zdd_invalid_argument(arg, message))
}

# Runs a .Call that returns list(status, ...) and raises on a status.
zdd_call <- function(res) {
  if (!is.null(res$status)) zdd_raise_status(res$status)
  res
}
