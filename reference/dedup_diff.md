# What two versions of an object share

Compares two manifests as sets of chunk digests. A chunk that moved is
still shared, so the comparison is order-insensitive. Both manifests
must come from the same hash algorithm and chunking parameters, or their
digests are not comparable (`zudedup_algorithm_error`).

## Usage

``` r
dedup_diff(a, b)
```

## Arguments

- a, b:

  Manifests, from
  [`dedup_manifest()`](https://pedrobtz.github.io/zudedup/reference/dedup_manifest.md)
  or
  [`dedup_put()`](https://pedrobtz.github.io/zudedup/reference/dedup_put.md):
  `a` the old version, `b` the new.

## Value

A list: `shared`, `added` and `removed`, the distinct digests in both,
only in `b` and only in `a`; `bytes_shared` and `bytes_added`, the bytes
of `b` in chunks `a` has and in chunks it lacks (a chunk repeated in `b`
counts each time, so the two sum to `b`'s size); `bytes_removed`, the
bytes of `a` in chunks `b` lacks; and `ratio`, `bytes_shared` over `b`'s
size (1 for an empty `b`): the fraction of the new version a store
holding the old one already has.

## See also

[`dedup_missing()`](https://pedrobtz.github.io/zudedup/reference/dedup_has.md)
for the chunks a particular store lacks.

## Examples

``` r
x <- as.raw(sample(0:255, 300000, replace = TRUE))
y <- x
y[150000:150100] <- as.raw(0)
d <- dedup_diff(dedup_manifest(x), dedup_manifest(y))
d$ratio
#> [1] 0.9633767
length(d$added)
#> [1] 1
```
