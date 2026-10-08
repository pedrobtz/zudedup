# What this build of zudedup is

Reports the versions, the format constants and the hash algorithms
available, for bug reports and for checking that two installations chunk
alike.

## Usage

``` r
zudedup_info()
```

## Value

A list: `version`, zudedup's version; `zufast`, the version of the
zufast headers compiled in; `gear_seed`, the seed of the gear table;
`boundary_rule`, a description of the format (design section 6);
`defaults`, the default `min`, `avg` and `max`; and `hashes`, a named
logical saying which algorithms this installation can use.

## Details

XXH3-128, the default hash, is fast and not cryptographic.

## Examples

``` r
zudedup_info()
#> $version
#> [1] "0.0.0.9000"
#> 
#> $zufast
#> [1] "0.1.0"
#> 
#> $gear_seed
#> [1] "0x5a5a5a5a5a5a5a5a"
#> 
#> $boundary_rule
#> [1] "FastCDC: gear hash h = (h >> 1) + G[b], contiguous low-bit masks, normal point avg - 1.5 min; Python fastcdc 1.7.0's rule"
#> 
#> $defaults
#> $defaults$min
#> [1] 2048
#> 
#> $defaults$avg
#> [1] 8192
#> 
#> $defaults$max
#> [1] 65536
#> 
#> 
#> $hashes
#>   xxh3 sha256 
#>   TRUE   TRUE 
#> 
```
