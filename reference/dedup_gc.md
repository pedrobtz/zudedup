# Delete the chunks no manifest needs

Deletes every chunk in the store that no manifest in `keep` references,
and, in a filesystem store, any partial writes left in `tmp/` by an
interrupted
[`dedup_put()`](https://pedrobtz.github.io/zudedup/reference/dedup_put.md).

## Usage

``` r
dedup_gc(store, keep)
```

## Arguments

- store:

  A
  [`dedup_store()`](https://pedrobtz.github.io/zudedup/reference/dedup_store.md)
  or
  [`dedup_backend()`](https://pedrobtz.github.io/zudedup/reference/dedup_backend.md).

- keep:

  A manifest, or a list of manifests, made with the store's hash and
  parameters.

## Value

The digests of the deleted chunks, invisibly.

## Details

**Pass every manifest whose object you want to keep.** An object whose
manifest is not in `keep` loses the chunks it does not share with one
that is, and cannot be read again. zudedup keeps no list of manifests:
that is the caller's.

`dedup_gc()` is not safe against a concurrent
[`dedup_put()`](https://pedrobtz.github.io/zudedup/reference/dedup_put.md),
which may be relying on a chunk it saw present: hold whatever lock your
system provides around it.

## Examples

``` r
store <- dedup_store(tempfile(), create = TRUE)
m1 <- dedup_put(store, as.raw(sample(0:255, 100000, replace = TRUE)))
m2 <- dedup_put(store, as.raw(sample(0:255, 100000, replace = TRUE)))
length(dedup_gc(store, keep = m2))
#> [1] 12
length(dedup_missing(store, m2))
#> [1] 0
```
