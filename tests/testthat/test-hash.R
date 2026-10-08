test_that("whole-object XXH3-128 matches the pinned xxhsum digests", {
  skip_under_torture()
  ref <- read_hash_reference()
  obj <- ref[ref$kind == "object", ]
  for (i in seq_len(nrow(obj))) {
    name <- obj$name[i]
    x <- if (name == "abc") charToRaw("abc") else if (name == "fixture") {
      fixture_bytes()
    } else {
      splitmix_bytes(as.numeric(sub("splitmix:", "", name)), "abc")
    }
    expect_identical(dedup_manifest(x)$hash, obj$xxh3[i], info = name)
    expect_identical(zdd_xxh3_hex(x), obj$xxh3[i], info = name)
  }
})

test_that("every chunk digest of the fixture matches the pinned digests", {
  skip_under_torture()
  ref <- read_hash_reference()
  chunks <- ref[ref$kind == "chunk", ]
  expect_identical(dedup_chunk(fixture_bytes())$hash, chunks$xxh3)
})

test_that("chunk digests do not depend on the block size", {
  skip_under_torture()
  x <- fixture_bytes()
  p <- fixture_params$small
  params <- zdd_check_params(p$min, p$avg, p$max)
  whole <- zdd_scan(x, params, "xxh3")
  for (block in c(1000, 65536, 1048576)) {
    s <- zdd_scan(x, params, "xxh3", block = block)
    expect_identical(s$table, whole$table, info = block)
    expect_identical(s$object, whole$object, info = block)
  }
})

test_that("the object digest is zufast's and the digest is high then low", {
  x <- splitmix_bytes(300000, "77")
  expect_identical(dedup_manifest(x)$hash, zufast::fast_hash(x, bits = 128))
  # design D12: the canonical big-endian rendering, as xxhsum prints it.
  expect_identical(dedup_manifest(charToRaw("abc"))$hash,
                   "06b05ab6733a618578af5f94892f3950")
})

test_that("SHA-256 matches the pinned hashlib digests", {
  skip_under_torture()
  skip_if_not_installed("zucrypt")
  ref <- read_hash_reference()
  x <- fixture_bytes()
  m <- dedup_manifest(x, hash = "sha256")
  expect_identical(m$hashes, ref$sha256[ref$kind == "chunk"])
  expect_identical(m$hash, ref$sha256[ref$name == "fixture"])
  expect_identical(dedup_manifest(raw(), hash = "sha256")$hash,
                   ref$sha256[ref$name == "splitmix:0"])
})

test_that("SHA-256 chunk digests do not depend on the block size", {
  skip_under_torture()
  skip_if_not_installed("zucrypt")
  x <- splitmix_bytes(200000, "88")
  params <- zdd_check_params(64, 256, 1024)
  whole <- zdd_scan(x, params, "sha256")
  for (block in c(1, 999, 65536)) {
    if (block == 1) {
      s <- zdd_scan(x[1:5000], params, "sha256", block = 1)
      expect_identical(s$table, zdd_scan(x[1:5000], params, "sha256")$table)
    } else {
      expect_identical(zdd_scan(x, params, "sha256", block = block)$table,
                       whole$table, info = block)
    }
  }
})
