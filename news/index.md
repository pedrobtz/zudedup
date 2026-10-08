# Changelog

## zudedup 0.0.0.9000

The development version of the first release, 0.1.0 (this heading
becomes `# zudedup 0.1.0` when it is submitted).

- [`dedup_chunk()`](https://pedrobtz.github.io/zudedup/reference/dedup_chunk.md)
  splits a raw vector, a connection or a file into content-defined
  chunks with FastCDC. The boundaries are a format: the same bytes give
  the same chunks on every platform, whatever block size they arrive in,
  and they agree with the Python `fastcdc` package (1.7.0) given
  zudedup’s gear table.
