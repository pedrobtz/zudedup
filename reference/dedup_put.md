# Put an object into a store

Chunks `x` with the store's parameters, asks the store which chunks it
already has, and writes only the others. Memory stays bounded for a
connection or a file: the store is asked once per 1 MiB block, about the
chunks completed in it.

## Usage

``` r
dedup_put(store, x)
```

## Arguments

- store:

  A
  [`dedup_store()`](https://pedrobtz.github.io/zudedup/reference/dedup_store.md)
  or
  [`dedup_backend()`](https://pedrobtz.github.io/zudedup/reference/dedup_backend.md).

- x:

  A raw vector, a connection, or the path of a file. A connection that
  is not open is opened, read and closed; an open one must be in binary
  mode and is read from its current position to its end, in blocks of 1
  MiB.

## Value

The object's
[`dedup_manifest()`](https://pedrobtz.github.io/zudedup/reference/dedup_manifest.md),
invisibly. Keep it: it is the only way to get the object back.

## Details

The default hash, XXH3-128, is not cryptographic; see
[`dedup_store()`](https://pedrobtz.github.io/zudedup/reference/dedup_store.md).

## Examples

``` r
store <- dedup_store(tempfile(), create = TRUE)
v1 <- serialize(mtcars, NULL)
m1 <- dedup_put(store, v1)
# A second version that differs in one row writes only the changed chunks.
cars2 <- mtcars
cars2[5, 1] <- 99
m2 <- dedup_put(store, serialize(cars2, NULL))
mean(m2$hashes %in% m1$hashes)
#> [1] 0
```
