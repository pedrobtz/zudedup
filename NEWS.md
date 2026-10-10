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

* `dedup_store()` opens or creates a content-addressed store in a directory,
  and `dedup_backend()` builds one from five functions of your own.
  `dedup_put()` writes only the chunks a store lacks; `dedup_get()` reassembles
  an object, refusing a missing or corrupt chunk; `dedup_has()`,
  `dedup_missing()` and `dedup_delete()` act on digests.

* `dedup_diff()` measures what two versions share; `dedup_verify()` names
  the corrupt chunks in a store; `dedup_gc()` deletes the chunks no kept
  manifest needs, and partial writes an interrupted put left behind.

* A vignette, *Versioning large objects with zudedup*, walks through two
  versions of a data frame, a store and garbage collection.

* `zudedup_info()` reports the build, the format constants and the hash
  algorithms available.

* The store's metadata file, `zudedup.json`, is read and written with
  zujson instead of jsonlite. The file is unchanged, so existing stores open
  as before; zudedup's one runtime dependency is now a family package.
