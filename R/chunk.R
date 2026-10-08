# Content-defined chunking (design section 6): R reads blocks, the chunker in
# src/zdd_cdc.c finds the boundaries, and its state crosses each .Call as a
# raw vector, so the boundaries do not depend on the block size.

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
#' @param x A raw vector, a connection, or the path of a file. A connection
#'   that is not open is opened, read and closed; an open one must be in
#'   binary mode and is read from its current position to its end, in blocks
#'   of 1 MiB.
#' @param min,avg,max Chunk sizes in bytes. No chunk is shorter than `min`
#'   except the last, none is longer than `max`, and the mean is close to
#'   `avg`, which must be a power of two. `min` is in \[64, 2^26\], `avg`
#'   in \[256, 2^28\] and `max` in \[1024, 2^30\], with
#'   `min <= avg <= max`.
#' @return A data frame with one row per chunk, in order: `offset`, the
#'   0-based position of its first byte (a double, since inputs may exceed
#'   2^31 bytes), and `length`, its size in bytes (an integer). An empty
#'   input has no chunks.
#' @seealso [zudedup-conditions] for the errors raised.
#' @export
#' @examples
#' x <- as.raw(sample(0:255, 200000, replace = TRUE))
#' chunks <- dedup_chunk(x)
#' head(chunks)
#' sum(chunks$length) == length(x)
#'
#' # An insertion near the start leaves the later boundaries in place.
#' y <- c(as.raw(1:100), x)
#' tail(dedup_chunk(y)$offset - 100) %in% dedup_chunk(x)$offset
dedup_chunk <- function(x, min = 2048, avg = 8192, max = 65536) {
  params <- zdd_check_params(min, avg, max)
  ends <- zdd_chunk_ends(x, params)
  starts <- c(0, ends)[seq_along(ends)]
  data.frame(offset = starts, length = as.integer(ends - starts))
}

# The 0-based end offset of every chunk of x, in order. `block` is the block
# size for a connection, and also splits a raw vector, which only the tests
# ask for: the boundaries must not depend on it.
zdd_chunk_ends <- function(x, params, block = NULL) {
  st <- zdd_call(.Call(zudedup_cdc_init, params$min, params$avg, params$max))
  ends <- list()
  done <- 0
  feed <- function(b) {
    r <- zdd_call(.Call(zudedup_cdc_feed, st$state, b))
    st <<- r
    if (length(r$cuts)) ends[[length(ends) + 1L]] <<- done + r$cuts
    done <<- done + length(b)
  }
  if (is.raw(x)) {
    if (is.null(block) || length(x) <= block) {
      feed(x)
    } else {
      starts <- seq(1, length(x), by = block)
      for (s in starts) feed(x[s:min(s + block - 1, length(x))])
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
  ends <- unlist(ends, use.names = FALSE)
  if (is.null(ends)) ends <- numeric()
  # The chunk in progress at the end of the input is the last chunk.
  if (!is.null(st$pending) && st$pending > 0) ends <- c(ends, done)
  ends
}

# zu_open_input() with zudedup's conditions.
zdd_open_input <- function(x) {
  if (!is.raw(x) && !inherits(x, "connection") && !is.character(x)) {
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
