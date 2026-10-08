# Argument checks shared by the exported functions. Each raises
# zudedup_invalid_argument naming the argument (design section 11).

zdd_check_count <- function(x, arg, lo, hi, call = NULL) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || x != trunc(x) ||
      x < lo || x > hi) {
    zdd_invalid_argument(arg, sprintf(
      "`%s` must be a whole number of bytes in [%s, %s]",
      arg, format(lo, scientific = FALSE), format(hi, scientific = FALSE)
    ), call = call)
  }
  as.numeric(x)
}

# The chunking parameters of design section 5: the Python fastcdc package's
# ranges, min <= avg <= max, and avg a power of two. zdd_cdc.c checks the
# same again; this is where the error names the argument.
zdd_check_params <- function(min, avg, max, call = NULL) {
  min <- zdd_check_count(min, "min", 64, 2^26, call)
  avg <- zdd_check_count(avg, "avg", 256, 2^28, call)
  max <- zdd_check_count(max, "max", 1024, 2^30, call)
  if (2^round(log2(avg)) != avg) {
    zdd_invalid_argument("avg", "`avg` must be a power of two", call = call)
  }
  if (min > avg) {
    zdd_invalid_argument("min", "`min` must not exceed `avg`", call = call)
  }
  if (avg > max) {
    zdd_invalid_argument("max", "`max` must not be less than `avg`",
                         call = call)
  }
  list(min = min, avg = avg, max = max)
}
