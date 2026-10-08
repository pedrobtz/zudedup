# Get an object back from a store

Reads the chunks of a manifest in order and reassembles the object,
checking that each chunk's bytes hash to its digest. A store cannot
substitute content: a missing or corrupt chunk is an error,
`zudedup_store_error`, naming the digest and the chunk's position. The
manifest is checked whole before any chunk is read.

## Usage

``` r
dedup_get(
  store,
  manifest,
  file = NULL,
  verify = TRUE,
  max_chunks = 1e+07,
  max_size = Inf
)
```

## Arguments

- store:

  A
  [`dedup_store()`](https://pedrobtz.github.io/zudedup/reference/dedup_store.md)
  or
  [`dedup_backend()`](https://pedrobtz.github.io/zudedup/reference/dedup_backend.md).

- manifest:

  A manifest from
  [`dedup_put()`](https://pedrobtz.github.io/zudedup/reference/dedup_put.md)
  or
  [`dedup_manifest()`](https://pedrobtz.github.io/zudedup/reference/dedup_manifest.md),
  made with the store's hash and parameters.

- file:

  If given, the path the object is written to, a chunk at a time,
  instead of being returned; the file is removed if a chunk fails.

- verify:

  If `FALSE`, skip the digest check, for a caller who has just written
  the chunks. Lengths are always checked.

- max_chunks, max_size:

  Limits on the manifest, checked before any chunk is read: the number
  of chunks, and the object's size in bytes (only when the object is
  returned in memory). Exceeding one is `zudedup_limit_error`.

## Value

A raw vector, or `file`, invisibly.

## Examples

``` r
store <- dedup_store(tempfile(), create = TRUE)
m <- dedup_put(store, charToRaw("hello"))
rawToChar(dedup_get(store, m))
#> [1] "hello"
```
