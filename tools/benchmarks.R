# The engine of tools/run-benchmarks; see there.
suppressMessages(library(zudedup))
mb <- as.numeric(commandArgs(trailingOnly = TRUE)[1])
n <- mb * 1024^2
set.seed(1)
x <- as.raw(sample.int(256L, n, replace = TRUE) - 1L)

# The best of `reps` runs. The expression is re-evaluated each time: a
# promise would run once and then time nothing.
time <- function(expr, reps = 3) {
  e <- substitute(expr)
  env <- parent.frame()
  min(vapply(seq_len(reps), function(i) {
    gc()
    system.time(eval(e, env))[["elapsed"]]
  }, 0))
}
rate <- function(secs) sprintf("%7.2f GB/s", n / secs / 1e9)

params <- zudedup:::zdd_check_params(2048, 8192, 65536)
t_bounds <- time(zudedup:::zdd_chunk_ends(x, params))
t_xxh3 <- time(dedup_chunk(x))
t_hash <- time(zudedup:::zdd_xxh3_hex(x))

dir <- tempfile("bench-")
dir.create(dir)
t_write <- time({
  f <- file.path(dir, "plain.bin")
  writeBin(x, f)
  unlink(f)
})
s <- dedup_store(file.path(dir, "store"), create = TRUE)
t_put <- time(m <- dedup_put(s, x), reps = 1)
t_reput <- time(dedup_put(s, x), reps = 1)
t_get <- time(dedup_get(s, m), reps = 1)
src <- file.path(dir, "src.bin")
writeBin(x, src)
s2 <- dedup_store(file.path(dir, "store2"), create = TRUE)
t_put_file <- time(dedup_put(s2, src), reps = 1)
chunks <- length(m)
unlink(dir, recursive = TRUE)

cat(sprintf("zudedup %s, R %s, %s, %s MB of random bytes\n",
            packageVersion("zudedup"), getRversion(), R.version$platform, mb))
cat(sprintf("  chunk, boundaries only        %s\n", rate(t_bounds)))
cat(sprintf("  chunk + XXH3-128 per chunk    %s\n", rate(t_xxh3)))
cat(sprintf("  XXH3-128 of the whole object  %s\n", rate(t_hash)))
cat(sprintf("  writeBin() to a file          %7.2f s\n", t_write))
cat(sprintf("  dedup_put() of the raw vector %7.2f s  (%.1fx writeBin)\n", t_put, t_put / t_write))
cat(sprintf("  dedup_put() of a file         %7.2f s  (%.1fx writeBin)\n", t_put_file, t_put_file / t_write))
cat(sprintf("  dedup_put() again (no writes) %7.2f s\n", t_reput))
cat(sprintf("  dedup_get() with verification %7.2f s\n", t_get))
cat(sprintf("  %d chunks: %.0f us per chunk written\n", chunks, 1e6 * (t_put - t_reput) / chunks))
