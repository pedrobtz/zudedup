# Split bytes into content-defined chunks

Finds chunk boundaries with FastCDC: a gear rolling hash over the bytes,
with normalised chunking so that sizes cluster around `avg`. A boundary
depends only on the bytes near it, so an insertion or deletion changes
the chunks around it and leaves the rest alone. The same bytes give the
same chunks on every platform and in every version of zudedup, however
they are read.

## Usage

``` r
dedup_chunk(x, min = 2048, avg = 8192, max = 65536)
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

## Value

A data frame with one row per chunk, in order: `offset`, the 0-based
position of its first byte (a double, since inputs may exceed 2^31
bytes), and `length`, its size in bytes (an integer). An empty input has
no chunks.

## See also

[zudedup-conditions](https://pedrobtz.github.io/zudedup/reference/zudedup-conditions.md)
for the errors raised.

## Examples

``` r
x <- as.raw(sample(0:255, 200000, replace = TRUE))
chunks <- dedup_chunk(x)
head(chunks)
#>   offset length
#> 1      0   6417
#> 2   6417   7155
#> 3  13572  17779
#> 4  31351  10520
#> 5  41871   9488
#> 6  51359  13335
sum(chunks$length) == length(x)
#> [1] TRUE

# An insertion near the start leaves the later boundaries in place.
y <- c(as.raw(1:100), x)
tail(dedup_chunk(y)$offset - 100) %in% dedup_chunk(x)$offset
#> [1] TRUE TRUE TRUE TRUE TRUE TRUE
```
