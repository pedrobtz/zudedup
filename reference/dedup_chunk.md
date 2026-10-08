# Split bytes into content-defined chunks

Finds chunk boundaries with FastCDC: a gear rolling hash over the bytes,
with normalised chunking so that sizes cluster around `avg`. A boundary
depends only on the bytes near it, so an insertion or deletion changes
the chunks around it and leaves the rest alone. The same bytes give the
same chunks on every platform and in every version of zudedup, however
they are read.

## Usage

``` r
dedup_chunk(x, min = 2048, avg = 8192, max = 65536, hash = c("xxh3", "sha256"))
```

## Arguments

- x:

  A raw vector, a connection, or the path of a file. A connection that
  is not open is opened, read and closed; an open one must be in binary
  mode and is read from its current position to its end, in blocks of 1
  MiB.

- min, avg, max:

  Chunk sizes in bytes. No chunk is shorter than `min` except the last,
  none is longer than `max`, and the mean is close to `avg`, which must
  be a power of two. `min` is in \[64, 2^26\], `avg` in \[256, 2^28\]
  and `max` in \[1024, 2^30\], with `min <= avg <= max`.

- hash:

  The digest of each chunk: `"xxh3"` (XXH3-128, 32 hex characters, the
  default) or `"sha256"` (64 hex characters, needs the zucrypt package).

## Value

A data frame with one row per chunk, in order: `offset`, the 0-based
position of its first byte (a double, since inputs may exceed 2^31
bytes), `length`, its size in bytes (an integer), and `hash`, its digest
in lower-case hex. An empty input has no chunks.

## Details

The default hash, XXH3-128, is fast and not cryptographic: an adversary
who chooses content can make two chunks with the same digest. Use
`hash = "sha256"` where that matters.

## See also

[`dedup_manifest()`](https://pedrobtz.github.io/zudedup/reference/dedup_manifest.md)
for the chunk digests with the object's own;
[zudedup-conditions](https://pedrobtz.github.io/zudedup/reference/zudedup-conditions.md)
for the errors raised.

## Examples

``` r
x <- as.raw(sample(0:255, 200000, replace = TRUE))
chunks <- dedup_chunk(x)
head(chunks)
#>   offset length                             hash
#> 1      0   6417 01190bf2b84bcdc37e9e2fb8c86e0220
#> 2   6417   7155 369c53992d1a356cddb8fe4f1e7a184b
#> 3  13572  17779 d64dd19372080ca51506ee01b86469a2
#> 4  31351  10520 642cc92900574b015ac37afb71fc2b1b
#> 5  41871   9488 4115c04a9234e8c084e944069ae097a6
#> 6  51359  13335 ae514930c17e8348bbc2055798ed5039
sum(chunks$length) == length(x)
#> [1] TRUE

# An insertion near the start leaves the later chunks in place.
y <- c(as.raw(1:100), x)
mean(dedup_chunk(y)$hash %in% chunks$hash)
#> [1] 0.9583333
```
