# zudedup

zudedup splits byte streams into variable-size chunks at boundaries
chosen by their content (FastCDC), hashes each chunk with XXH3-128 or
SHA-256, and stores chunks by hash. Two versions of a large object that
differ in a few places share almost every chunk, so a store keeps the
second version for the price of the bytes that changed, and a manifest
of chunk digests says exactly what two versions share.

- **Boundaries are a format.** The same bytes give the same chunks on
  every platform, in every version, however they are read, and they
  agree with the Python `fastcdc` package given zudedup’s gear table.
- **The hash says what it is.** XXH3-128 is the fast default and is not
  cryptographic; `hash = "sha256"` is one argument away.
- **The store is dumb.** It maps a digest to bytes, in a directory or
  behind any backend of five functions, and refuses to return bytes that
  do not match their digest.

## Installation

The development version, which also needs the development version of
[zufast](https://github.com/pedrobtz/zufast) until that is on CRAN:

``` r

# install.packages("pak")
pak::pak("pedrobtz/zudedup")
```

## Example

``` r

library(zudedup)

v1 <- serialize(mtcars, NULL)
cars2 <- mtcars
cars2["Valiant", "mpg"] <- 99
v2 <- serialize(cars2, NULL)

store <- dedup_store(tempfile(), create = TRUE, min = 64, avg = 256, max = 1024)
m1 <- dedup_put(store, v1)
m2 <- dedup_put(store, v2)   # writes only the chunks v1 lacks

dedup_diff(m1, m2)$ratio     # the fraction of v2 already stored
#> [1] 0.9340688
identical(unserialize(dedup_get(store, m2)), cars2)
#> [1] TRUE
```
