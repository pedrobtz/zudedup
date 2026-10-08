# Check every chunk in a store

Reads every chunk the store lists and checks that its bytes hash to its
name. Needs a backend with `get` and `list`.

## Usage

``` r
dedup_verify(store)
```

## Arguments

- store:

  A
  [`dedup_store()`](https://pedrobtz.github.io/zudedup/reference/dedup_store.md)
  or
  [`dedup_backend()`](https://pedrobtz.github.io/zudedup/reference/dedup_backend.md).

## Value

The digests of the chunks that are corrupt (their bytes hash to another
digest, or the store refuses to read them), as a character vector, empty
when every chunk is sound.

## Examples

``` r
store <- dedup_store(tempfile(), create = TRUE)
dedup_put(store, serialize(mtcars, NULL))
dedup_verify(store)
#> character(0)
```
