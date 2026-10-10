# zudedup — Design

**Status:** Draft, 2026-10-08. Adopted from [RFC 0006](https://github.com/pedrobtz/packages/blob/main/rfcs/0006-zudedup-content-defined-chunking.md) (2026-10-07) as the package's own specification. Stages 0–5 are implemented (every function of §5, the conformance job, the benchmarks of §16 and the documentation); the roadmap's **Status:** lines say what else is. Every statement here is a decision; things not yet decided live in §18 and nowhere else. Amend this file in the same commit as the code that changes it. [roadmap.md](roadmap.md) sequences the work; its section references (§) point here.
**Package:** `zudedup`
**One line:** FastCDC content-defined chunking of byte streams, chunk hashing through `zufast`'s XXH3-128 (or `zucrypt`'s SHA-256), manifests, and a dumb content-addressed store with a backend interface, for `dastash` and for anyone versioning large binary objects in R.

What changed between the RFC and this document: the RFC said nothing in it had been checked against a running implementation. On 2026-10-08 the sibling checkouts (`../zufast`, `../zucrypt`, `../zukomp`, `../dastash`, `../zubin`) were read, and the places where the RFC's assumptions did not hold are corrected and marked *verified 2026-10-08* (§3, §6, §7). The RFC's roadmap table (its §19) became [roadmap.md](roadmap.md). On the same day, a review before Stage 0 fixed the boundary rule against the Python `fastcdc` source (§6), and settled how hashing crosses blocks, what SHA-256 can stream, and what a backend records (§7–§9, §13; D14–D19).

---

## 1. What zudedup is

`zudedup` splits byte streams into variable-size chunks at boundaries chosen by the content, hashes each chunk, and stores chunks by hash. Two versions of a serialised data frame that differ in a few rows share almost every chunk; a 2 GB artifact re-uploaded after a small change sends only the chunks that changed; a manifest of chunk hashes is a strong identity for the whole.

It is the blob layer that `dastash` describes and does not yet have (*verified 2026-10-08*: `../dastash/.agents/cache-model.md` §11.3 names it `B : Hashes ⇀ Bytes`, "a filesystem, not transactional", and §11.2 says why content addressing deduplicates bytes and never values), and a standalone tool for anyone keeping versions of large binary objects in R. It is an *engine* package in the family's terms, like `zurand`: a small C core with an R API, no C API of its own.

The one-line statement that governs every decision below:

> **Chunk boundaries are a format: the same bytes give the same chunks on every platform, in every version, whatever the block size they arrive in.**

Three properties shape the design:

- **Boundaries depend only on content.** The gear table and the masks are constants committed to the package and never changed; a fixture pins the boundaries of a fixed input forever. A store written by 0.1.0 is read by every later version, and two machines chunk a file identically.
- **The hash is the identity, and it says what it is.** XXH3-128 is the default: fast, 128-bit, and not cryptographic, which the documentation says wherever it is mentioned. A caller who needs collision resistance against an adversary chooses `hash = "sha256"` and gets it from `zucrypt`.
- **The store is dumb.** It maps a hash to bytes and nothing else. Keys, metadata, expiry and concurrency are `dastash`'s; `zudedup` has no opinion on what a chunk means.

---

## 2. Scope

| | v0.1.0 | Later, when asked | Never |
|---|---|---|---|
| FastCDC chunking with normalised chunking, over a raw vector or a connection, in bounded memory | yes | | |
| Chunk hashing with XXH3-128 (default) or SHA-256 (through `zucrypt` when installed) | yes | | |
| Manifests: the ordered chunk hashes of one object, its length and its whole-object hash | yes | | |
| A filesystem store: put, get, has, missing, delete, verify, garbage collection against a set of manifests | yes | | |
| Manifest diff: shared, added and removed chunks between two manifests, with byte counts | yes | | |
| A backend interface, so the store can be a directory, an `mdbx` database (through `dastash`) or object storage (through `qak` or `azr`) without `zudedup` knowing | yes | | |
| Manifest files on disk (`dedup_manifest_write()`, `_read()`) | | §18 Q2 | |
| Delta encoding between near-identical chunks (zstd `--patch-from`, bsdiff) | | zubin ideas.md §1.7 | |
| A Merkle tree over manifests for partial verification | | yes | |
| Compression of chunks at rest, through `zukomp` | | §18 Q1 | |
| Whole-object identity by call rather than content | | | yes: `storr` and `memoise` do that; dastash's `cache-model.md` §11 says why content addressing is the one that deduplicates |
| Encryption at rest | | | yes: a store backend's or `zucrypt`'s |
| A key-value API: names, expiry, eviction | | | yes |

---

## 3. Position in the `zu*` family

These are zudedup's cells for the family table that alignment rule R1 of [`zu-family-alignment.md`](https://github.com/pedrobtz/packages/blob/main/zu-family-alignment.md) places in `pedrobtz/packages` as `zu-family.md`. That file did not exist on 2026-10-08; until it does, the rows live here.

| | zudedup |
|---|---|
| Role | engine |
| R prefix | `dedup_` |
| Info function | `zudedup_info()` (the package name, as R1 recommends) |
| Root condition class | `zudedup_error` |
| Public C prefix | none; internal `zdd_` / `ZDD_` |
| From C | no C API; `LinkingTo` consumer only |
| Hides symbols (`$(C_VISIBILITY)`) | yes, from Stage 0 (R3) |
| Vendored code | none |
| `LinkingTo` | `zufast (>= 0.1.0)` |
| `Imports` | `zujson` (D9) for the store's metadata file; `jsonlite` until 2026-10-10 |
| `Suggests` | `zucrypt`, `callr`, `testthat`, `withr`, `knitr`, `rmarkdown` (not `dastash`: it will depend on zudedup, and is not on CRAN) |
| `Remotes` (development only) | `pedrobtz/zufast@main`, `pedrobtz/zucrypt@main` |
| `Depends: R` | 4.1 (R2) |
| Language | en-GB (R2) |

`zdd_` is free: no sibling's `src/` or `inst/include/` uses it (*verified 2026-10-08*, Stage 0).

### 3.1 Relationships, as decided rather than as hoped

- **`zufast`** owns the hash (*verified 2026-10-08* against `../zufast/inst/include/zufast/hash.h`): `zuf_hash128(data, n)` returns a `zuf_digest128` of two `uint64_t`, `low` and `high`; the streaming form is `zuf_hasher_init(h, seed)`, `zuf_hasher_update(h, data, n)` and `zuf_hasher_digest128(h)` (there is no `zuf_hasher_final()`, which the RFC named). Seed 0 throughout, so digests equal upstream XXH3's. The gear hash itself is sixty lines of `zudedup`'s own, since it is a rolling hash with a fixed table, not a general primitive.
- **`zucrypt`** owns SHA-256 when a caller asks for it (*verified 2026-10-08*: it exports `crypt_hash()` and `crypt_info()`); `Suggests`. When it is absent, `hash = "sha256"` is `zudedup_invalid_argument` naming the package.
- **`dastash`** is the consumer: its blob directory becomes a `zudedup` store, and its "what changed between two artifacts" question is `dedup_diff()`. `dastash` adopts `zudedup` by an issue gated on the CRAN release (alignment R10.1); nothing here is shaped around an unmade decision.
- **`qak`** and **`azr`** are the remote backends' transport, if a backend for object storage is written; `zudedup` ships the interface and the filesystem implementation only.
- **`zukomp`** owns compression at rest, later (`komp_compress()`, *verified 2026-10-08*).
- **`zubin`** is where the idea came from (`../zubin/.agents/ideas.md` §1.2, ranked first after zubin itself in its §4); zudedup takes nothing from zubin's headers, since it reads bytes and never a record layout.

### 3.2 What exists elsewhere

No CRAN package implements content-defined chunking (*verified 2026-10-08* against `tools::CRAN_package_db()`: titles and descriptions mentioning content-defined chunking, FastCDC, Rabin or chunking-based deduplication match only record-linkage and bibliographic deduplication packages). `storr` and `memoise` address whole objects by key or by call; `qs2`, `fst` and `arrow` serialise but do not deduplicate across versions. Outside R, `restic`, `borg`, `casync`, `rsync` and the Python `fastcdc` package are the prior art, and `zudedup`'s boundary rule is the Python `fastcdc` package's (version 1.7.0, `fastcdc_py.cdc_offset()`) exactly, so that a file chunked by it with zudedup's gear table substituted gives the same boundaries, which is a conformance test (§15).

---

## 4. Architecture

```text
raw / connection
      │
      ▼
  CHUNKER  (src/zdd_cdc.c, R-free behind zdd_check.h)
      - gear rolling hash over bytes; no window, no state but one uint64 and a length
      - FastCDC normalised chunking: a stricter mask before the average size,
        a looser one after; min and max sizes enforced
      - block-independent: fed in any block size, the boundaries are the same
      │
      ▼   offsets and lengths
  HASHER   (zufast XXH3-128 in C; or zucrypt SHA-256 from R)
      │
      ▼   manifest: hashes, lengths, total, object hash
  STORE    (R, with a backend; the filesystem backend ships)
      - put: write the chunks the backend lacks
      - get: read and reassemble, verifying each chunk's hash
```

The chunker is R-free behind `zdd_check.h`, builds with `-DZDD_STANDALONE`, and is fuzzed for the invariants of §15. Its state is a small struct (`h`, the current chunk length, the three parameters) that crosses the `.Call` boundary as a raw vector (§13), so chunking a connection is a loop in R over blocks, each block one `.Call`.

---

## 5. Public R API (complete v0.1.0 surface)

```r
# chunking
dedup_chunk(x, min = 2048, avg = 8192, max = 65536, hash = c("xxh3", "sha256"))
                                  # raw, connection or path -> data frame of offset, length, hash
dedup_manifest(x, ..., hash = c("xxh3", "sha256"))
                                  # raw, connection or path -> dedup_manifest
dedup_diff(a, b)                  # two manifests -> shared, added, removed

# stores
dedup_store(path, create = FALSE, hash = c("xxh3", "sha256"),
            min = 2048, avg = 8192, max = 65536)
                                  # a filesystem store; the settings apply on creation
dedup_put(store, x)               # -> manifest; writes missing chunks only
dedup_get(store, manifest, file = NULL, verify = TRUE,
          max_chunks = 1e7, max_size = Inf)
                                  # -> raw, or writes to file
dedup_has(store, hashes)          # logical
dedup_missing(store, manifest)    # the hashes a put would write
dedup_delete(store, hashes)
dedup_verify(store)               # -> the digests whose bytes do not hash to their name
dedup_gc(store, keep)             # delete chunks not in any kept manifest (a manifest or a list)

# backends
dedup_backend(has, get, put, delete = NULL, list = NULL,
              hash = "xxh3", min = 2048, avg = 8192, max = 65536)
                                  # a store over user functions

zudedup_info()
```

Eleven functions, one constructor for backends, one value class (`dedup_manifest`) and the info function.

### Chunking arguments

`min`, `avg` and `max` are bytes, with `min <= avg <= max`; `avg` must be a power of two, which is what the mask derivation needs. The ranges are the Python `fastcdc` package's, so the conformance test covers every legal setting: `min` in [64, 2^26], `avg` in [256, 2^28], `max` in [1024, 2^30]. The defaults are FastCDC's: 2 KiB, 8 KiB, 64 KiB. A path is opened as a connection (through `R/zu_source.R`, copied verbatim from zuxml at Stage 1). A connection is read in 1 MiB blocks and the chunker's state carries across blocks, so memory is bounded by `max` plus the block. `dedup_chunk()` of a connection reads it whole in blocks and returns the table; it does not keep the bytes.

### Manifests

A `dedup_manifest` is a list: `hashes` (a character vector of hex digests, in order), `lengths` (integer), `size` (double, the total), `hash` (the whole-object digest), `algorithm` (`"xxh3"` or `"sha256"`), and `params` (`min`, `avg`, `max`). It serialises as a plain list, prints as a summary, and `as.data.frame()` gives the chunk table. Two manifests with different `algorithm` or `params` cannot be diffed, and the error (`zudedup_algorithm_error`) says so.

---

## 6. The chunker

### 6.1 The gear hash

`h = (h >> 1) + G[b]` over each byte `b`, where `G` is a table of 256 constants below 2^63. No window: the shift discards a byte's influence after 64 steps on its own, and because it shifts *right*, every bit of `h`, the low bits the masks test included, depends on the last 64 bytes. (A left shift, the paper's form, leaves bit *k* depending only on the last *k* + 1 bytes, so low-bit masks would see a window of a dozen bytes.) This is the FastCDC gear hash as the Python `fastcdc` package computes it, chosen over Rabin fingerprints because it is one shift and one add per byte.

**The table is a format constant.** `src/zdd_gear.h` holds the 256 values, generated once by `tools/make-gear.R` from SplitMix64 seeded with `0x5A5A5A5A5A5A5A5A`, each output shifted right by one bit, with the script, the seed and the boundary rule recorded in the header so anyone can regenerate and compare. The shift keeps every entry below 2^63, so `(h >> 1) + G[b]` never exceeds 2^64 and never wraps: Python, whose integers are unbounded, computes the same `h` as C's `uint64_t`, which a full 64-bit table would not give. The table is never changed after 0.1.0: changing it changes every boundary, which would make every store unreadable. The Python `fastcdc` package's table is different, so a cross-implementation test substitutes zudedup's table on the Python side (its table is a module-level constant), never the other way round; the shipped package has no table option.

### 6.2 Normalised chunking

Two masks, derived from `avg`: with `bits = log2(avg)`, `mask_s = 2^(bits + 1) - 1` and `mask_l = 2^(bits - 1) - 1`, contiguous low bits (0x3fff and 0x0fff for 8 KiB). For each chunk, `h` starts at 0 and `n` counts its bytes:

- the first `min` bytes are not hashed;
- each later byte `b`: `n += 1`, `h = (h >> 1) + G[b]`; cut after it if `(h & mask) == 0`, with `mask_s` while `n <= normal` and `mask_l` after;
- at `n == max` the cut is forced; the last chunk of an input is whatever remains.

`normal = avg - (min + ceil(min / 2))`, floored at 0 and capped at `max`. Placing the switch there rather than at `avg` is the Python package's choice and is kept for two reasons: the mean chunk size lands near `avg` (measured on 2026-10-08 over 4 MiB: 8,508 bytes on random input and 8,160 on CSV text, against about 10,000 with the switch at `avg`), and the conformance test then runs the Python package's own chunker unchanged, with only its table replaced. A content-defined cut therefore gives a chunk of at least `min + 1` bytes.

**The whole rule is a format constant** (D2, D14), recorded in `src/zdd_gear.h` beside the table: the shift direction, the mask placement, the normal point and where the cut falls all change boundaries. The mask placement was §18 Q4; it was decided at Stage 0 for contiguous low bits, which the right shift makes sound.

### 6.3 Block independence

The chunker is a struct of `h`, the current chunk length and the three parameters; `zdd_cdc_feed()` takes a block and reports boundaries within it, carrying the state across calls. The R-facing state that crosses `.Call` adds what hashing needs to carry across blocks (§7, §13): a `zuf_hasher` for the chunk in progress and one for the whole object. So a 10 GB file read in 1 MiB blocks and the same file in memory produce the same boundaries; a property test feeds every fixture in block sizes 1, 7, 4096, 65536 and 1 MiB.

---

## 7. Hashing

| `hash` | Digest | Through |
|---|---|---|
| `"xxh3"` (default) | 128-bit, 32 hex characters | `zufast`, in C, per chunk and streamed over the object |
| `"sha256"` | 256-bit, 64 hex characters | `zucrypt::crypt_hash()`, from R, per chunk; over the object only where the bytes can be read again (below) |

`"xxh3"` is for local stores, caches and change detection; `"sha256"` for stores shared across a trust boundary.

**Rendering** (*verified 2026-10-08* against `hash.h`'s `zuf_digest128 {low, high}`): the 32 hex characters are the canonical big-endian rendering of the 128-bit value, `high` then `low`, each as 16 lower-case hex digits, which is the text `xxhsum`'s 128-bit mode prints; Stage 2 pins it against `xxhsum` on the fixtures. The whole-object hash uses the same algorithm, streamed over the bytes as they are chunked (`zuf_hasher_update()` per block, `zuf_hasher_digest128()` at the end), so a manifest's `hash` is also what `zufast::fast_hash()` gives for the whole object and what `xxhsum` prints for the file.

**XXH3 is not a cryptographic hash.** An adversary who can write to a store and choose content can produce two chunks with the same XXH3 digest. The documentation of every function that names the default says so, and `print.dedup_store` shows the algorithm. For a store that untrusted parties write to, `hash = "sha256"`.

**SHA-256 over a connection** (*verified 2026-10-08*: `zucrypt` 0.1.0 has `crypt_hash()` over a raw vector or a whole connection, and no incremental interface). The chunk digests need only the chunk's bytes, which zudedup holds anyway (at most `max`). The whole-object digest needs every byte, and zudedup has already consumed the connection to chunk it. So, with `hash = "sha256"`, the object digest is computed from the raw vector, or by `crypt_hash()` reading a path a second time; for any other connection the manifest's `hash` is `NA` and the manifest is otherwise complete. If zucrypt gains a streaming hasher, `NA` goes and nothing else changes (D15).

A store records its algorithm in its metadata file at creation; a manifest with another algorithm is refused by every store function (`zudedup_algorithm_error`).

---

## 8. The filesystem store

```text
<path>/
  zudedup.json         algorithm, params, format version 1
  objects/ab/abcdef…   one file per chunk, named by its full hex digest
  tmp/                 writes land here and are renamed into place
```

- `dedup_put()` chunks, hashes, asks `has()` once per block for the digests of the chunks completed in it (one call for a raw vector, one per 1 MiB from a connection, so memory stays bounded, §13), writes the missing ones to `tmp/` and renames each into place, so a chunk is either complete or absent; a crash mid-put leaves `tmp/` files that `dedup_gc()` removes. A rename onto a chunk that already exists, which two concurrent puts of the same bytes cause, is success: the files are identical.
- `dedup_get()` reads the chunks in manifest order into one raw vector, or streams them to `file`, verifying each chunk's digest as it goes (`verify = FALSE` skips that, for a caller who has just written them). A missing or corrupt chunk is `zudedup_store_error` naming the digest and the chunk index.
- `dedup_gc(store, keep)` deletes every chunk not referenced by a manifest in `keep`; it is the caller's job (dastash's) to pass every live manifest, and the function's documentation says a manifest not passed is a manifest whose object is lost.
- Concurrency: two processes may put at once, since renames are atomic and identical chunks are identical files; `dedup_gc()` is not safe against a concurrent put and the documentation says to take the lock the caller's system provides (dastash's mdbx transaction).
- The two-character directory prefix keeps directories under a few thousand entries for stores up to a few million chunks; beyond that is an mdbx backend's job.

---

## 9. Backends

`dedup_backend(has, get, put, delete, list)` wraps R functions:

```r
has(hashes)          # -> logical, same length
get(hash)            # -> raw, or NULL if absent
put(hash, bytes)     # -> invisible; must be atomic
delete(hashes)       # optional; needed by dedup_delete() and dedup_gc()
list()               # optional; needed by dedup_verify() and dedup_gc()
```

`put` must be atomic: after it, `has(hash)` is `TRUE` only if `get(hash)` would return all of `bytes`. Idempotence is not enough: a torn write that `has()` reports present is skipped by every later put, and nothing notices until a get (D16). A second put of the same hash with the same bytes must be harmless.

A backend also records what its chunks were made with: `hash`, `min`, `avg` and `max` are arguments of `dedup_backend()`, not functions the backend implements, and every store function refuses a manifest that disagrees (`zudedup_algorithm_error`), exactly as the filesystem store does with its metadata file (D17).

`dedup_store()` returns a backend of this shape over a directory; a `dastash` store over mdbx, or a blob container over `qak`, is the same shape. Every store function takes either. The backend interface is the one piece of API that other packages program against, so it is the part most carefully kept (§17, D8). A backend missing `delete` makes `dedup_delete()` and `dedup_gc()` `zudedup_invalid_argument`; one missing `list` does the same for `dedup_verify()` and `dedup_gc()`.

---

## 10. Manifest diff

`dedup_diff(a, b)` returns a list: `shared`, `added`, `removed` (each a character vector of digests), `bytes_shared`, `bytes_added`, `bytes_removed`, and `ratio`, the fraction of `b`'s bytes already in `a`. It is a set comparison on digests, order-insensitive, since a chunk that moved is still shared. A chunk that appears more than once in one manifest counts once in the digest vectors and once per occurrence in the byte counts, so `bytes_shared + bytes_added` is `b`'s size and `ratio` is `bytes_shared / size(b)`. For a delta upload, `dedup_missing(remote, manifest)` is the question to ask the remote backend; `dedup_diff()` is the question to ask about two versions.

---

## 11. Errors

Every condition inherits `zudedup_error`; tests assert on class, never on message text. A store error's `problem` is `"missing"` or `"corrupt"` for a chunk, so a caller can tell a lost chunk from a damaged one (added at Stage 3, when the mutation check showed the two were otherwise indistinguishable). C returns statuses by enumerator name and R raises (`zucbor`'s convention).

```text
zudedup_error
├── zudedup_invalid_argument    parameters, a bad manifest, an unknown hash, a missing backend function
├── zudedup_store_error         a missing or corrupt chunk; an unusable store   (problem, hash, index)
├── zudedup_algorithm_error     a manifest's algorithm or params do not match the store's
├── zudedup_io_error            a connection or file could not be read or written
└── zudedup_limit_error         a limit of §12 was reached                       (limit, limit_value)
```

---

## 12. Limits and hostile input

The chunker reads bytes and computes a hash; it cannot be made to allocate by its input. What can be hostile is a manifest or a store handed to `dedup_get()`:

| Limit | Default | Where |
|---|---|---|
| `max_chunks` | 1e7 | a manifest's length, before any read |
| `max_size` | `Inf` | a manifest's `size`, before allocation in memory |
| chunk length | `max` | a chunk file longer than the store's `max` is corrupt, refused before it is read (defence in depth: the length check refuses its bytes anyway) |

`max_size` does not apply when `file =` is given. A manifest is validated whole before any chunk is read: digests are hex of the algorithm's length, lengths are within `[1, max]` (the last may be shorter), and their sum is `size`. A chunk whose bytes do not hash to its name is refused, so a store cannot substitute content. Each guard carries a `# GUARD: name` marker on its `if` line in `R/` and a test named `GUARD name`; `tools/run-mutation-check` replaces each condition with `FALSE` in the loaded namespace and requires that test to fail. A check that a later guard subsumes carries no marker: it is there for a clearer message.

---

## 13. Memory model

- Chunking a connection holds one block (1 MiB) plus the current chunk (at most `max`); chunking a raw vector holds nothing extra.
- `dedup_put()` holds one chunk at a time; `dedup_get(file =)` streams.
- All scratch is `R_alloc()`ed; the chunker's state is a struct carried as a raw vector between `.Call`s, with the two `zuf_hasher`s of §6.3 in it. A `zuf_hasher` needs 64-byte alignment and a raw vector's data does not have it, so each `.Call` copies the state into an aligned local, works on that, and copies it back; nothing points into the raw vector across calls. The state does hold one pointer, to XXH3's default secret inside zudedup's own shared object (*verified 2026-10-08*: seed 0 resets through `XXH3_64bits_reset()`, which stores it), so it is valid only in the process that made it: the state lives inside one call of `dedup_chunk()`, `dedup_manifest()` or `dedup_put()`, is never returned to the caller, and carries a magic number and its length so that a raw vector of the wrong shape is refused, so an interrupt between blocks leaks nothing and there is no external pointer to finalize. No C function has an error cleanup path.

---

## 14. Build, portability and CRAN

- C99, the family's lint flags; `LinkingTo: zufast (>= 0.1.0)`; `Imports: zujson` for the store metadata file (D9); `Suggests: zucrypt, dastash, callr, testthat (>= 3.0.0), withr`. During development `Remotes: pedrobtz/zufast@main`, removed before submission (alignment R10.2).
- `src/Makevars`: `PKG_CFLAGS = $(C_VISIBILITY)`, hand-listed `OBJECTS`, portable make only; the shared object exports `R_init_zudedup` only (`tools/check-symbols`).
- Licence MIT; `Language: en-GB`; `.Rbuildignore` covers `.agents/`, `.claude/`, `tools/`, `fuzz/`.
- CRAN order: after `zufast` (tagged 0.1.0, not on CRAN on 2026-10-08). Nothing else waits on zudedup; `dastash` adopts it after.
- Workflows: the family's standard set, with `hardening.yaml` running the chunker fuzz target and a `conformance` job running the Python `fastcdc` comparison.

---

## 15. Testing

- **The boundary fixture.** A 4 MiB input, the SplitMix64 stream from seed `0x7a75646564757030` written little-endian (`fixture_bytes()` in `helper-bytes.R`), is chunked at Stage 1 and its boundaries committed as `tests/testthat/fixtures/boundaries.tsv`; every later version must reproduce it exactly. This is the format-stability gate.
- **Cross-implementation.** In the `conformance` job, Python's `fastcdc` package (pinned at 1.7.0, `fastcdc_py.fastcdc_py()`) with `zudedup`'s gear table substituted must produce the same boundaries on the fixture and on every file under `tests/testthat/fixtures/`.
- **Block independence as a property**: every fixture chunked in block sizes 1, 7, 4096, 65536 and 1 MiB, and as one raw vector, gives the same chunk table.
- **Size distribution**: over 100 MB of random bytes, no chunk under `min`, none over `max`, the mean within 10 % of `avg`.
- **Dedup as a property**: a 10 MB object with 1 % of its bytes changed at 100 random points shares at least 85 % of its bytes with the original, measured by `dedup_diff()`. (The RFC asked for 95 %, which 8 KiB chunks cannot give: each scattered edit costs about one chunk, and the chunk a random point falls in is size-biased, about 11 KB, so 100 edits lose about 11 % whatever their size. Measured at Stage 4: 0.889–0.896 over three draws.)
- **The store**: put, get, verify, gc, missing and delete over temporary directories; a corrupted chunk file is refused on get; a crash simulated by a leftover `tmp/` file is cleaned by gc; two processes putting the same object (via `callr`) leave one copy.
- **Hashes against references**: XXH3-128 digests compared with `xxhsum` on the fixtures (pinned once, so the suite needs no `xxhsum`); SHA-256 with `openssl` when `zucrypt` is installed.
- **The chunker is fuzzed** under ASan and UBSan with the block-independence invariant (the fuzzer splits its input at random points and compares); `fuzz_canary` must crash first.
- Tests are self-sufficient, pass under `shuffle = TRUE`, stay serial, and the CRAN suite runs in under 15 s; the 100 MB cases call `skip_heavy()`.

---

## 16. Performance targets

Measured by `tools/run-benchmarks`, not in CI. The targets were chunking at not less than 1 GB/s on one core for the default parameters, hashing at `zufast`'s XXH3 speed, and `dedup_put()` of a large object into an empty store within 2× the time of `writeBin()` of the same bytes.

Measured at Stage 5 (2026-10-08; zudedup 0.0.0.9000, R 4.6.1, aarch64-apple-darwin23, 256 MB of random bytes, best of three):

| | |
|---|---|
| chunking, boundaries only | 1.46 GB/s |
| chunking with XXH3-128 per chunk | 1.23 GB/s |
| XXH3-128 of the whole object | 33.6 GB/s |
| `writeBin()` to a file | 0.18 s |
| `dedup_put()` into an empty store (32,582 chunks) | 7.9 s, 44× `writeBin()`; 213 µs per chunk written |
| `dedup_put()` again (every chunk present) | 0.94 s |
| `dedup_get()` with verification | 3.6 s |

The chunking target is met. The put target is not, and cannot be met by the filesystem store: it writes one file per chunk (about 125,000 per GB at the defaults), and the time is in creating, closing and renaming those files, not in chunking or hashing (an `Rprof()` of the put puts 75 % in `file()`, `close()` and `file.rename()`). `writeBin()` makes one file. A store that packs chunks into larger files, as restic and borg do, is a backend's job (§9) and is not in 0.1.0; for the filesystem store the figure to watch is the cost per chunk written. Creating the 256 prefix directories once, at store creation, rather than on each put, is the one change Stage 5 made for speed.

---

## 17. Decisions

| # | Question | Decision |
|---|---|---|
| D1 | Chunking algorithm | FastCDC with normalised chunking |
| D2 | Gear table | fixed constants, committed; a format |
| D3 | Default parameters | 2 KiB, 8 KiB, 64 KiB, FastCDC's |
| D4 | Default hash | XXH3-128 via zufast; documented as non-cryptographic |
| D5 | Strong hash | SHA-256 via zucrypt, `Suggests` |
| D6 | Store semantics | hash to bytes only; no keys, no expiry |
| D7 | Filesystem layout | two-character prefix directories, atomic rename |
| D8 | Backend interface | five R functions; the one API other packages hold |
| D9 | Metadata file | JSON through `zujson` (*was `jsonlite` until zujson reached CRAN; switched 2026-10-10*) |
| D10 | Compression at rest | none in 0.1.0; `zukomp` later |
| D11 | Info function | `zudedup_info()`, the package name (R1) |
| D12 | Digest rendering | canonical big-endian hex, `high` then `low` (*verified 2026-10-08*) |
| D13 | Chunker state across blocks | a raw vector, no external pointer (§13) |
| D14 | Boundary rule | right-shift gear hash, contiguous low-bit masks, normal point `avg - 1.5 min`: the Python `fastcdc` 1.7.0 rule exactly (§6.2; was §18 Q4) |
| D15 | SHA-256 object digest from a connection | `NA` unless the bytes are a raw vector or a path; chunk digests always (§7) |
| D16 | Backend `put` | atomic, not merely idempotent (§9) |
| D17 | Backend metadata | `hash`, `min`, `avg`, `max` are `dedup_backend()` arguments (§9) |
| D18 | `has()` batching in `dedup_put()` | one call per block (§8) |
| D19 | Gear table entries | SplitMix64 output shifted right one bit, below 2^63 (§6.1) |
| D20 | Compression at rest (was §18 Q1) | not in 0.1.0; later, a store-level `compress =` recorded in the metadata file |
| D21 | Manifest files (was §18 Q2) | not in 0.1.0; a manifest is an R list the caller keeps (dastash in mdbx); `dedup_manifest_write()` and `_read()` in JSON when asked |
| D22 | Chunk-level encryption (was §18 Q3) | no; a backend that encrypts does so inside its `put` and `get` |

Reasons where they are not in the section cited:

- **D1.** Rabin fingerprinting is slower per byte and no better at boundaries; fixed-size chunking cannot survive an insertion. FastCDC is what the production tools of §3.2 converged on.
- **D4.** dastash's blob layer is local and private, where speed matters and an adversary does not; the family review gives digests to `zucrypt`, which stays true for the strong option.
- **D9.** `jsonlite` was the one dependency outside the family, held until `zujson` shipped. zujson 0.1.0 reached CRAN and replaced it on 2026-10-10. The file is unchanged: zujson writes the same bytes jsonlite did, and reads the same numbers back as integers, so a store made with either opens with the other.
- **D12.** The rendering must match what other tools print, or a user cannot check a store against `xxhsum`.
- **D14.** The rule had to be one an independent implementation computes, or the conformance test proves nothing; the Python package is that implementation. Its right shift is also what makes contiguous low-bit masks sound (§6.1). Its normal point puts the mean chunk size near `avg`, which the paper's switch at `avg` does not when the first `min` bytes are skipped.
- **D15.** zudedup cannot read a connection twice, and buffering a whole object to hash it defeats bounded memory. An `NA` that says so is better than either.
- **D16.** A torn chunk that `has()` reports present is never rewritten, so idempotence alone lets one crash poison every later put of the same bytes.
- **D17.** Without it, the algorithm check of §7 holds for the filesystem store and silently not for any other backend.
- **D18.** One call for the whole object needs every digest before any write, which for a connection means holding the object.
- **D19.** A full 64-bit table makes C's `uint64_t` wrap where Python's integers do not, and the two then disagree after the wrap reaches the low bits.
- **D20–D22** are the RFC's recommendations, adopted at Stage 5 by default so that the release has no open question; each is the maintainer's to reopen. D20 and D21 add API, which is easier to add after 0.1.0 than to remove; D22 is already possible through the backend interface.

---

## 18. Open questions

None. Q1–Q3 became D20–D22 at Stage 5, by the RFC's recommendations; Q4 and Q5 were decided at Stage 0 (D14 and §3.2). A new question goes here until it is decided.

---

## 19. Acceptance criteria for v0.1.0

1. Builds everywhere with `zufast` from CRAN and nothing else at run time beyond `zujson`.
2. The boundary fixture reproduces exactly on every platform.
3. Boundaries are block-independent, by the property test and the fuzzer.
4. Python `fastcdc` 1.7.0 with zudedup's table substituted agrees on every fixture.
5. Every store operation is atomic or idempotent as §8 states, under the two-process test.
6. A corrupt or missing chunk is refused on get; a bad manifest is refused before any read.
7. `R CMD check --as-cran` clean everywhere; `R_init_zudedup` is the only export; no stdio or exit symbols.

---

## 20. What this design does not decide

- Whether `dastash` adopts `zudedup`. That is dastash's issue, gated on CRAN, and its `cache-model.md` already states the blob layer this package implements.
- Whether the mdbx and object-storage backends live in `zudedup`, in `dastash`, or in `qak`. The interface of §9 lets any of them host one.
