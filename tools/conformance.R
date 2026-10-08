# The engine of tools/run-conformance; see there. Needs zudedup installed,
# and PYTHON naming an interpreter with fastcdc 1.7.0.
suppressMessages(library(zudedup))
source("tests/testthat/helper-bytes.R")

python <- Sys.getenv("PYTHON", "python3")
xxhsum <- Sys.which("xxhsum")
work <- tempfile("conformance-")
dir.create(file.path(work, "inputs"), recursive = TRUE)
dir.create(file.path(work, "chunks"))

# Inputs: the fixture, every file under tests/testthat/fixtures/, a few
# SplitMix64 streams of awkward sizes, and low-entropy inputs where a gear
# hash bug would show (zeros never cut; a repeating pattern).
writeBin(fixture_bytes(), file.path(work, "inputs", "fixture.bin"))
for (f in list.files("tests/testthat/fixtures", full.names = TRUE)) {
  file.copy(f, file.path(work, "inputs", basename(f)))
}
for (n in c(1, 63, 64, 65, 1023, 1024, 1025, 70000, 300001)) {
  writeBin(splitmix_bytes(n, "c0ffee"), file.path(work, "inputs", sprintf("splitmix-%d.bin", n)))
}
writeBin(raw(200000), file.path(work, "inputs", "zeros.bin"))
writeBin(rep(as.raw(0:250), 2000), file.path(work, "inputs", "pattern.bin"))
writeBin(charToRaw(paste(rep("id,name,value\n1,alpha,3.5\n", 20000), collapse = "")),
         file.path(work, "inputs", "csv.bin"))

params <- rbind(c(2048, 8192, 65536), c(64, 256, 1024), c(64, 1024, 1024),
                c(1024, 1024, 1024), c(100, 512, 4096), c(700, 1024, 1500),
                c(16384, 65536, 1048576))
write.table(params, file.path(work, "params.tsv"), sep = "\t", row.names = FALSE,
            col.names = FALSE)
writeLines(gear_table(), file.path(work, "gear.txt"))

status <- system2(python, c("tools/conformance.py", work))
if (status != 0) stop("tools/conformance.py failed")
py <- utils::read.delim(file.path(work, "python-chunks.tsv"), colClasses = "character")

failed <- 0L
for (name in list.files(file.path(work, "inputs"))) {
  path <- file.path(work, "inputs", name)
  for (i in seq_len(nrow(params))) {
    p <- params[i, ]
    ours <- dedup_chunk(path, min = p[1], avg = p[2], max = p[3])
    theirs <- py[py$input == name & py$min == p[1] & py$avg == p[2] & py$max == p[3], ]
    same <- identical(ours$offset, as.numeric(theirs$offset)) &&
      identical(ours$length, as.integer(theirs$length))
    if (!same) {
      failed <- failed + 1L
      cat(sprintf("FAIL: %s at (%s): %d chunks here, %d in Python fastcdc\n", name,
                  paste(p, collapse = ", "), nrow(ours), nrow(theirs)))
    }
  }
}
cat(sprintf("==> boundaries: %d inputs x %d parameter sets compared with Python fastcdc 1.7.0\n",
            length(list.files(file.path(work, "inputs"))), nrow(params)))

# Digests against xxhsum itself, where it is installed (CI installs it):
# every input whole, and every chunk of the fixture at the defaults.
if (nzchar(xxhsum)) {
  check_xxhsum <- function(paths, want) {
    out <- system2(xxhsum, c("-H2", shQuote(paths)), stdout = TRUE)
    got <- regmatches(out, regexpr("[0-9a-f]{32}", out))
    bad <- which(got != want)
    for (b in bad) cat(sprintf("FAIL: xxhsum gives %s for %s, zudedup %s\n", got[b], paths[b], want[b]))
    length(bad)
  }
  inputs <- list.files(file.path(work, "inputs"), full.names = TRUE)
  ours <- vapply(inputs, function(f) dedup_manifest(f)$hash, "")
  failed <- failed + check_xxhsum(inputs, unname(ours))
  x <- fixture_bytes()
  t <- dedup_chunk(x)
  chunk_files <- file.path(work, "chunks", sprintf("%04d", seq_len(nrow(t))))
  for (i in seq_len(nrow(t))) writeBin(x[t$offset[i] + seq_len(t$length[i])], chunk_files[i])
  failed <- failed + check_xxhsum(chunk_files, t$hash)
  ref <- utils::read.delim("tests/testthat/fixtures/hash-reference.tsv", colClasses = "character")
  if (!identical(ref$xxh3[ref$kind == "chunk"], t$hash)) {
    failed <- failed + 1L
    cat("FAIL: hash-reference.tsv disagrees with the chunk digests xxhsum confirmed\n")
  }
  cat(sprintf("==> digests: %d inputs and %d chunks compared with %s\n", length(inputs),
              nrow(t), system2(xxhsum, "--version", stdout = TRUE, stderr = TRUE)[1]))
} else {
  cat("==> xxhsum not found: digests not compared (CI installs it)\n")
}

unlink(work, recursive = TRUE)
if (failed > 0L) quit(status = 1)
cat("==> conformance: everything agrees\n")
