# Bytes for tests. Everything random comes from SplitMix64 (Steele, Lea and
# Flood, 2014), written here in base R so that the gear table and every
# fixture input can be regenerated from a seed without compiling anything:
# tools/make-gear.R sources this file. R has no 64-bit integer, so a 64-bit
# value is four 16-bit limbs, least significant first, in a row of a numeric
# matrix; every intermediate stays below 2^53 and is exact.

u64_from_hex <- function(hex) {
  hex <- sub("^0x", "", tolower(hex))
  stopifnot(grepl("^[0-9a-f]{1,16}$", hex))
  hex <- formatC(hex, width = 16, flag = "0")
  hex <- gsub(" ", "0", hex)
  limbs <- strtoi(substring(hex, c(13, 9, 5, 1), c(16, 12, 8, 4)), 16L)
  matrix(as.numeric(limbs), nrow = 1)
}

u64_to_hex <- function(x) {
  sprintf("%04x%04x%04x%04x", x[, 4], x[, 3], x[, 2], x[, 1])
}

u64_from_index <- function(i) {
  i <- as.numeric(i)
  cbind(i %% 65536, (i %/% 65536) %% 65536, (i %/% 65536^2) %% 65536, 0)
}

u64_carry <- function(r) {
  for (k in 1:3) {
    r[, k + 1] <- r[, k + 1] + r[, k] %/% 65536
    r[, k] <- r[, k] %% 65536
  }
  r[, 4] <- r[, 4] %% 65536
  r
}

u64_add <- function(a, b) u64_carry(sweep_rows(a, b, `+`))

u64_mul <- function(a, b) {
  b <- b[rep_len(1L, nrow(a)), , drop = FALSE]
  if (nrow(b) != nrow(a)) stop("u64_mul: shapes")
  r <- matrix(0, nrow(a), 4)
  for (k in 0:3) {
    for (i in 0:k) {
      r[, k + 1] <- r[, k + 1] + a[, i + 1] * b[, k - i + 1]
    }
    # Carry as we go, so a sum of four 2^32 products never meets the next.
    if (k < 3) {
      r[, k + 2] <- r[, k + 2] + r[, k + 1] %/% 65536
      r[, k + 1] <- r[, k + 1] %% 65536
    }
  }
  r[, 4] <- r[, 4] %% 65536
  r
}

u64_shr <- function(x, s) {
  q <- s %/% 16
  r <- s %% 16
  out <- matrix(0, nrow(x), 4)
  for (k in 1:4) {
    lo <- if (k + q <= 4) x[, k + q] else 0
    hi <- if (k + q + 1 <= 4) x[, k + q + 1] else 0
    out[, k] <- lo %/% 2^r + (hi %% 2^r) * 2^(16 - r)
  }
  out
}

u64_xor <- function(a, b) {
  matrix(as.numeric(bitwXor(as.integer(a), as.integer(b))), nrow(a))
}

sweep_rows <- function(a, b, f) {
  if (nrow(b) == 1L && nrow(a) > 1L) b <- b[rep_len(1L, nrow(a)), , drop = FALSE]
  f(a, b)
}

# The first n outputs of SplitMix64 from `seed` (hex), as limb rows. Output i
# mixes seed + i * gamma, so the whole stream is computed at once.
splitmix64 <- function(n, seed) {
  gamma <- u64_from_hex("9e3779b97f4a7c15")
  z <- u64_add(u64_mul(u64_from_index(seq_len(n)), gamma), u64_from_hex(seed))
  z <- u64_mul(u64_xor(z, u64_shr(z, 30)), u64_from_hex("bf58476d1ce4e5b9"))
  z <- u64_mul(u64_xor(z, u64_shr(z, 27)), u64_from_hex("94d049bb133111eb"))
  u64_xor(z, u64_shr(z, 31))
}

# n bytes: the SplitMix64 stream from `seed`, each output little-endian.
splitmix_bytes <- function(n, seed) {
  if (n == 0) return(raw())
  z <- splitmix64(ceiling(n / 8), seed)
  b <- rbind(z[, 1] %% 256, z[, 1] %/% 256, z[, 2] %% 256, z[, 2] %/% 256,
             z[, 3] %% 256, z[, 3] %/% 256, z[, 4] %% 256, z[, 4] %/% 256)
  as.raw(b)[seq_len(n)]
}

# Bytes from a hex string, spaces allowed.
bytes <- function(hex) {
  hex <- gsub("[[:space:]]", "", hex)
  if (!nzchar(hex)) return(raw())
  as.raw(strtoi(substring(hex, seq(1, nchar(hex), 2), seq(2, nchar(hex), 2)), 16L))
}

# The gear table of design section 6.1: SplitMix64 from GEAR_SEED, each
# output shifted right by one so that (h >> 1) + G[b] never overflows 64 bits.
GEAR_SEED <- "5a5a5a5a5a5a5a5a"
gear_table <- function() u64_to_hex(u64_shr(splitmix64(256, GEAR_SEED), 1))

# The seed of the boundary fixture's input (design section 15).
FIXTURE_SEED <- "7a75646564757030"
# Cached: generating it in R takes a fraction of a second natively and much
# longer under valgrind, and a dozen tests use it. The cache holds the same
# bytes every call would make, so no test can see another's use of it.
fixture_cache <- new.env(parent = emptyenv())
fixture_bytes <- function() {
  if (is.null(fixture_cache$bytes)) {
    fixture_cache$bytes <- splitmix_bytes(4 * 1024^2, FIXTURE_SEED)
  }
  fixture_cache$bytes
}
