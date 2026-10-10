# Versioning large objects with zudedup

``` r

library(zudedup)
```

Keeping every version of a large object costs the size of every version,
unless the versions share their storage. zudedup makes them share it: it
splits each version into chunks whose boundaries depend only on the
bytes around them, names each chunk by its hash, and stores each chunk
once.

## Two versions of a data frame

Take a data frame, and a second version with a few rows changed.

``` r

set.seed(1)
v1 <- data.frame(
  id = 1:50000,
  group = sample(letters, 50000, replace = TRUE),
  value = round(rnorm(50000), 4)
)
v2 <- v1
v2$value[c(100, 25000, 49000)] <- 0
x1 <- serialize(v1, NULL, xdr = FALSE)
x2 <- serialize(v2, NULL, xdr = FALSE)
length(x1)
#> [1] 850314
```

[`dedup_chunk()`](https://pedrobtz.github.io/zudedup/reference/dedup_chunk.md)
shows the chunks. Their sizes cluster around `avg`, 8 KiB by default,
and no chunk is longer than `max`.

``` r

chunks <- dedup_chunk(x1)
nrow(chunks)
#> [1] 104
summary(chunks$length)
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#>    2173    5783    7734    8176    9980   19060
```

A manifest records the chunk digests in order, with the size and the
digest of the whole object. Comparing two manifests says how much the
versions share:

``` r

m1 <- dedup_manifest(x1)
m2 <- dedup_manifest(x2)
m1
#> <dedup_manifest> 850,314 bytes in 104 chunks
#>   hash:   xxh3 fb8a718f9d2d5cb4b204ad78b82c2606
#>   params: min 2048, avg 8192, max 65536
d <- dedup_diff(m1, m2)
d$ratio
#> [1] 0.9709354
length(d$added)
#> [1] 5
```

Changing three values touched three chunks; the rest of the second
version is already there.

## A store

A store keeps each chunk once. Putting the first version writes all its
chunks; putting the second writes only the ones it does not share.

``` r

store <- dedup_store(file.path(tempdir(), "vignette-store"), create = TRUE)
store
#> <dedup_backend> filesystem: /tmp/RtmpGrun2o/vignette-store
#>   hash:   xxh3 (not cryptographic)
#>   params: min 2048, avg 8192, max 65536
dedup_missing(store, m1) |> length()
#> [1] 104
dedup_put(store, x1)
dedup_missing(store, m2) |> length()
#> [1] 5
dedup_put(store, x2)
length(dedup_missing(store, m2))
#> [1] 0
```

[`dedup_get()`](https://pedrobtz.github.io/zudedup/reference/dedup_get.md)
reassembles a version from its manifest, checking every chunk against
its digest, so a store cannot hand back the wrong bytes.

``` r

identical(unserialize(dedup_get(store, m2)), v2)
#> [1] TRUE
```

The manifest is the only way back to an object: keep it, for instance in
a database or next to a name. When a version is no longer needed, pass
the manifests you keep to
[`dedup_gc()`](https://pedrobtz.github.io/zudedup/reference/dedup_gc.md),
which deletes every chunk none of them uses.

``` r

deleted <- dedup_gc(store, keep = m2)
length(deleted)
#> [1] 4
identical(unserialize(dedup_get(store, m2)), v2)
#> [1] TRUE
```

## Choosing the hash

The default hash, XXH3-128, is fast and is not cryptographic: someone
who can choose what goes into a store could make two chunks with the
same digest. That does not matter for a cache or a private store, and it
does for a store shared with parties you do not trust. There, use
`hash = "sha256"`, which needs the zucrypt package:

``` r

dedup_manifest(x1, hash = "sha256")
#> <dedup_manifest> 850,314 bytes in 104 chunks
#>   hash:   sha256 a0efb6acd626d47731f9c2426ac0a1be17adf2d561218ef11867367857632e6c
#>   params: min 2048, avg 8192, max 65536
```

## Other backends

[`dedup_store()`](https://pedrobtz.github.io/zudedup/reference/dedup_store.md)
keeps chunks in a directory.
[`dedup_backend()`](https://pedrobtz.github.io/zudedup/reference/dedup_backend.md)
builds a store from five functions of your own, so chunks can live
anywhere: here, an environment.

``` r

env <- new.env()
mem <- dedup_backend(
  has = function(hashes) vapply(hashes, exists, TRUE, envir = env,
                                inherits = FALSE, USE.NAMES = FALSE),
  get = function(hash) get0(hash, envir = env, inherits = FALSE),
  put = function(hash, bytes) assign(hash, bytes, envir = env),
  delete = function(hashes) rm(list = hashes, envir = env),
  list = function() ls(env)
)
m <- dedup_put(mem, x1)
length(ls(env))
#> [1] 104
identical(dedup_get(mem, m), x1)
#> [1] TRUE
```

A backend’s `put` must be atomic: once it returns, the chunk is there
whole, or `has()` must not report it.
