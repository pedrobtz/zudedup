# A content-addressed store in a directory

Opens, or creates, a store that keeps each chunk once, in a file named
by its digest. The layout is:

## Usage

``` r
dedup_store(
  path,
  create = FALSE,
  hash = c("xxh3", "sha256"),
  min = 2048,
  avg = 8192,
  max = 65536
)
```

## Arguments

- path:

  The store's directory.

- create:

  If `TRUE`, create the store when `path` does not hold one. An existing
  store is opened either way.

- hash, min, avg, max:

  The hash algorithm and chunking parameters of a new store, as for
  [`dedup_chunk()`](https://pedrobtz.github.io/zudedup/reference/dedup_chunk.md).
  An existing store keeps its own; giving different ones is an error,
  `zudedup_algorithm_error`.

## Value

A `dedup_backend` over the directory, which every store function
accepts.

## Details

    <path>/
      zudedup.json      the hash algorithm, chunking parameters and format
      objects/ab/ab...  one file per chunk, under the first two hex digits
      tmp/              chunks are written here, then renamed into place

Writes go to `tmp/` and are renamed into `objects/`, so a chunk is
either complete or absent, and two processes may put into one store at
once. `dedup_gc()` is not safe against a concurrent put; take whatever
lock your system provides around it.

The default hash, XXH3-128, is fast and not cryptographic: an adversary
who can write to the store and choose content can make two chunks with
the same digest. For a store that parties you do not trust write to, use
`hash = "sha256"`.

## See also

[`dedup_backend()`](https://pedrobtz.github.io/zudedup/reference/dedup_backend.md)
for a store kept anywhere else.

## Examples

``` r
store <- dedup_store(file.path(tempdir(), "example-store"), create = TRUE)
store
#> <dedup_backend> filesystem: /tmp/RtmpCTZOND/example-store
#>   hash:   xxh3 (not cryptographic)
#>   params: min 2048, avg 8192, max 65536
m <- dedup_put(store, serialize(mtcars, NULL))
identical(unserialize(dedup_get(store, m)), mtcars)
#> [1] TRUE
```
