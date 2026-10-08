# Which chunks a store has

Which chunks a store has

## Usage

``` r
dedup_has(store, hashes)

dedup_missing(store, manifest)
```

## Arguments

- store:

  A
  [`dedup_store()`](https://pedrobtz.github.io/zudedup/reference/dedup_store.md)
  or
  [`dedup_backend()`](https://pedrobtz.github.io/zudedup/reference/dedup_backend.md).

- hashes:

  Chunk digests, as lower-case hex.

- manifest:

  A manifest from
  [`dedup_put()`](https://pedrobtz.github.io/zudedup/reference/dedup_put.md)
  or
  [`dedup_manifest()`](https://pedrobtz.github.io/zudedup/reference/dedup_manifest.md),
  made with the store's hash and parameters.

## Value

For `dedup_has()`, a logical vector, `TRUE` where the store has the
chunk. For `dedup_missing()`, the distinct digests of `manifest` the
store lacks: what a
[`dedup_put()`](https://pedrobtz.github.io/zudedup/reference/dedup_put.md)
of the object would write.

## Examples

``` r
store <- dedup_store(tempfile(), create = TRUE)
x <- as.raw(sample(0:255, 50000, replace = TRUE))
m <- dedup_manifest(x)
length(dedup_missing(store, m))
#> [1] 8
dedup_put(store, x)
dedup_has(store, m$hashes)
#> [1] TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE
dedup_missing(store, m)
#> character(0)
```
