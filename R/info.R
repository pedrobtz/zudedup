#' What this build of zudedup is
#'
#' Reports the versions, the format constants and the hash algorithms
#' available, for bug reports and for checking that two installations chunk
#' alike.
#'
#' XXH3-128, the default hash, is fast and not cryptographic.
#'
#' @return A list: `version`, zudedup's version; `zufast`, the version of
#'   the zufast headers compiled in; `gear_seed`, the seed of the gear table;
#'   `boundary_rule`, a description of the format (design section 6);
#'   `defaults`, the default `min`, `avg` and `max`; and `hashes`, a named
#'   logical saying which algorithms this installation can use.
#' @export
#' @examples
#' zudedup_info()
zudedup_info <- function() {
  b <- .Call(zudedup_build_info)
  list(
    version = as.character(utils::packageVersion("zudedup")),
    zufast = b[[1]],
    gear_seed = b[[2]],
    boundary_rule = paste(
      "FastCDC: gear hash h = (h >> 1) + G[b], contiguous low-bit masks,",
      "normal point avg - 1.5 min; Python fastcdc 1.7.0's rule"
    ),
    defaults = list(min = 2048, avg = 8192, max = 65536),
    hashes = c(xxh3 = TRUE, sha256 = requireNamespace("zucrypt", quietly = TRUE))
  )
}
