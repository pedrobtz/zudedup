# The condition hierarchy of design section 11. The class is the contract:
# callers branch on it and on the fields below, never on the message.

#' Conditions raised by zudedup
#'
#' Every error zudedup raises carries a condition class, so it can be caught
#' by kind rather than by matching the message, which may change. Every
#' class below inherits from `zudedup_error`.
#'
#' \describe{
#'   \item{`zudedup_invalid_argument`}{An argument was unusable: chunking
#'     parameters out of range, a malformed manifest, an unknown hash
#'     algorithm, or a backend without the function an operation needs. The
#'     condition carries `arg`, the argument at fault.}
#'   \item{`zudedup_store_error`}{A chunk is missing from a store, or its
#'     bytes do not hash to its name, or the store itself is unusable. The
#'     condition carries `problem`, `"missing"` or `"corrupt"` for a chunk
#'     (`NA` otherwise); `hash`, the chunk's digest; and `index`, its 1-based
#'     position in the manifest, where they apply.}
#'   \item{`zudedup_algorithm_error`}{A manifest's hash algorithm or
#'     chunking parameters differ from the store's or from another
#'     manifest's.}
#'   \item{`zudedup_io_error`}{A connection or file could not be read or
#'     written.}
#'   \item{`zudedup_limit_error`}{A limit was reached. The condition carries
#'     `limit`, the argument's name, such as `"max_chunks"`, and
#'     `limit_value`.}
#' }
#'
#' @name zudedup-conditions
#' @examples
#' tryCatch(
#'   dedup_chunk(raw(10), avg = 5000),
#'   zudedup_invalid_argument = function(e) e$arg
#' )
NULL

zdd_abort <- function(class, message, ..., call = NULL) {
  stop(structure(
    class = c(class, "zudedup_error", "error", "condition"),
    list(message = message, call = call, ...)
  ))
}

zdd_invalid_argument <- function(arg, message, call = NULL) {
  zdd_abort("zudedup_invalid_argument", message, arg = arg, call = call)
}

zdd_store_error <- function(message, hash = NA_character_, index = NA_integer_,
                            problem = NA_character_, call = NULL) {
  zdd_abort("zudedup_store_error", message, hash = hash, index = index,
            problem = problem, call = call)
}

zdd_algorithm_error <- function(message, call = NULL) {
  zdd_abort("zudedup_algorithm_error", message, call = call)
}

zdd_io_error <- function(message, call = NULL) {
  zdd_abort("zudedup_io_error", message, call = call)
}

zdd_limit_error <- function(limit, limit_value, message, call = NULL) {
  zdd_abort("zudedup_limit_error", message, limit = limit,
            limit_value = limit_value, call = call)
}

# A status name from C -> a condition, by the enumerator's name. Statuses that
# only misuse of the internal API can cause map to the bare zudedup_error:
# still catchable, never mistaken for a fault in the input.
zdd_raise_status <- function(status, call = NULL) {
  switch(status,
    ZDD_ERR_PARAMS = zdd_invalid_argument(
      "avg", "chunking parameters out of range", call = call),
    zdd_abort(character(), paste0("internal error: ", status), status = status,
              call = call)
  )
}
