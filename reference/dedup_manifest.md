# The manifest of an object

Chunks an object and records, in order, the digest and length of every
chunk, the object's size and the digest of the whole object. Two objects
whose manifests have the same `hashes` have the same bytes, up to the
strength of the hash; two versions of an object share the digests of the
chunks they share.

## Usage

``` r
dedup_manifest(x, ..., hash = c("xxh3", "sha256"))
```

## Arguments

- x:

  A raw vector, a connection, or the path of a file. A connection that
  is not open is opened, read and closed; an open one must be in binary
  mode and is read from its current position to its end, in blocks of 1
  MiB.

- ...:

  `min`, `avg` and `max`, as for
  [`dedup_chunk()`](https://pedrobtz.github.io/zudedup/reference/dedup_chunk.md).

- hash:

  The digest of each chunk: `"xxh3"` (XXH3-128, 32 hex characters, the
  default) or `"sha256"` (64 hex characters, needs the zucrypt package).

## Value

A `dedup_manifest`: a list of `hashes` (the chunk digests, in order, as
lower-case hex), `lengths` (integer), `size` (the object's length in
bytes, a double), `hash` (the digest of the whole object), `algorithm`
(`"xxh3"` or `"sha256"`) and `params` (`min`, `avg`, `max`). For XXH3
the object digest is what
[`zufast::fast_hash()`](https://pedrobtz.github.io/zufast/reference/fast_hash.html)
and `xxhsum -H2` give for the same bytes. With `hash = "sha256"` and a
connection, which cannot be read twice, it is `NA`.

It prints as a summary;
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) gives the
chunk table and [`length()`](https://rdrr.io/r/base/length.html) the
number of chunks.

## Details

The default hash, XXH3-128, is fast and not cryptographic: an adversary
who chooses content can make two chunks with the same digest. Use
`hash = "sha256"` for anything shared across a trust boundary.

## See also

[`dedup_chunk()`](https://pedrobtz.github.io/zudedup/reference/dedup_chunk.md)
for the chunk table alone.

## Examples

``` r
x <- serialize(mtcars, NULL)
m <- dedup_manifest(x, min = 64, avg = 256, max = 1024)
m
#> <dedup_manifest> 3,807 bytes in 15 chunks
#>   hash:   xxh3 1f06f784813afcdab461cd3834bfdb1c
#>   params: min 64, avg 256, max 1024
head(as.data.frame(m))
#>   offset length                             hash
#> 1      0    251 0f893b93eb1ff3b923ff38e1ed8df53f
#> 2    251    202 d9dbb5b4dbba8ba7b0e3733c203434f9
#> 3    453    353 69c955ef4d40fa9caddebda5259598a9
#> 4    806    165 2d7cd06b5e384ac0d4df3c99e7c07b6d
#> 5    971    244 303bae0cda12c73a1ed2ef344dec52c5
#> 6   1215    265 fc52b03436e712ab4a1c65e1bf73b65c
```
