# zudedup 0.0.0.9000

The development version of the first release, 0.1.0 (this heading becomes
`# zudedup 0.1.0` when it is submitted).

* `dedup_chunk()` splits a raw vector, a connection or a file into
  content-defined chunks with FastCDC. The boundaries are a format: the same
  bytes give the same chunks on every platform, whatever block size they
  arrive in, and they agree with the Python `fastcdc` package (1.7.0) given
  zudedup's gear table.

* `dedup_chunk()` gives each chunk's digest, and `dedup_manifest()` records
  an object's chunk digests, lengths, size and whole-object digest. XXH3-128
  (through zufast, the digest `xxhsum -H2` prints) is the default and is not
  cryptographic; `hash = "sha256"` uses zucrypt.

* `zudedup_info()` reports the build, the format constants and the hash
  algorithms available.
