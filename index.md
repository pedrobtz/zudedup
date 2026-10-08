# zudedup

zudedup splits byte streams into variable-size chunks at boundaries
chosen by their content (FastCDC), hashes each chunk with XXH3-128 or
SHA-256, and stores chunks by hash. Two versions of a large object that
differ in a few places share almost every chunk, so a store keeps the
second version for the price of the bytes that changed.

It is in development: the chunker, manifests and the store arrive stage
by stage (see the roadmap in `.agents/roadmap.md`).

## Installation

The development version, which also needs the development version of
[zufast](https://github.com/pedrobtz/zufast) until that is on CRAN:

``` r

# install.packages("pak")
pak::pak("pedrobtz/zudedup")
```
