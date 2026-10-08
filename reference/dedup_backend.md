# A store over your own functions

Builds a store from functions that keep chunks wherever you like: an
environment, a database, object storage. zudedup asks for nothing but
the functions below; the filesystem store of
[`dedup_store()`](https://pedrobtz.github.io/zudedup/reference/dedup_store.md)
is one such backend.

## Usage

``` r
dedup_backend(
  has,
  get,
  put,
  delete = NULL,
  list = NULL,
  hash = c("xxh3", "sha256"),
  min = 2048,
  avg = 8192,
  max = 65536
)
```

## Arguments

- has:

  `function(hashes)`: a logical vector, one element per digest, `TRUE`
  where the chunk is stored.

- get:

  `function(hash)`: the chunk's bytes as a raw vector, or `NULL` if it
  is not stored.

- put:

  `function(hash, bytes)`: stores a chunk. It must be atomic: once it
  returns, `has(hash)` is `TRUE` only if `get(hash)` returns all of
  `bytes`, and a crash must not leave a partial chunk that `has()`
  reports. A second put of the same digest and bytes must be harmless.

- delete:

  `function(hashes)`, optional: removes chunks; needed by
  [`dedup_delete()`](https://pedrobtz.github.io/zudedup/reference/dedup_delete.md)
  and `dedup_gc()`.

- list:

  `function()`, optional: the digests of every stored chunk; needed by
  `dedup_verify()` and `dedup_gc()`.

- hash, min, avg, max:

  What the backend's chunks are made with, as for
  [`dedup_chunk()`](https://pedrobtz.github.io/zudedup/reference/dedup_chunk.md).

## Value

A `dedup_backend`, which every store function accepts.

## Details

A backend also records the hash algorithm and chunking parameters its
chunks are made with. Every store function refuses a manifest made with
different ones, with `zudedup_algorithm_error`. The default hash,
XXH3-128, is fast and not cryptographic: for a store that parties you do
not trust can write to, use `hash = "sha256"`.

## Examples

``` r
env <- new.env()
store <- dedup_backend(
  has = function(hashes) vapply(hashes, exists, TRUE, envir = env,
                                inherits = FALSE, USE.NAMES = FALSE),
  get = function(hash) get0(hash, envir = env, inherits = FALSE),
  put = function(hash, bytes) assign(hash, bytes, envir = env),
  delete = function(hashes) rm(list = hashes, envir = env),
  list = function() ls(env)
)
m <- dedup_put(store, serialize(mtcars, NULL))
identical(unserialize(dedup_get(store, m)), mtcars)
#> [1] TRUE
```
