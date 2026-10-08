# Delete chunks from a store

Removes the named chunks. An object whose manifest names a deleted chunk
can no longer be read; `dedup_gc()` is the safe way to reclaim space.

## Usage

``` r
dedup_delete(store, hashes)
```

## Arguments

- store:

  A
  [`dedup_store()`](https://pedrobtz.github.io/zudedup/reference/dedup_store.md)
  or
  [`dedup_backend()`](https://pedrobtz.github.io/zudedup/reference/dedup_backend.md).

- hashes:

  Chunk digests, as lower-case hex.

## Value

`store`, invisibly.

## Examples

``` r
store <- dedup_store(tempfile(), create = TRUE)
m <- dedup_put(store, charToRaw("hello"))
dedup_delete(store, m$hashes)
dedup_has(store, m$hashes)
#> [1] FALSE
```
