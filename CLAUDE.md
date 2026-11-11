# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Shared conventions

The portfolio's shared rules are synced into `.claude/shared/` from
`pedrobtz/packages:claude/shared/`. Never edit them here. Where this file and
a shared file disagree, this file wins for this package.

@.claude/shared/workflow.md
@.claude/shared/r-package.md
@.claude/shared/ci.md
@.claude/shared/correctness.md
@.claude/shared/assurance.md

Nothing is vendored (no `src/vendor/`), so `native-code.md` is not imported.

## What this is

`zudedup` is an R package for content-defined chunking and content-addressed
storage. It splits byte streams into variable-size chunks at content-chosen
boundaries (FastCDC with a gear rolling hash, in C), hashes each chunk with
XXH3-128 from `zufast` (`LinkingTo`, header-only) or SHA-256 from `zucrypt`
(`Suggests`), builds manifests, diffs them, and stores chunks by hash in a
dumb filesystem store behind a five-function backend interface that other
packages (`dastash`, an mdbx or object-storage backend) implement. The one
runtime dependency is `zujson`, a family member, for the store's metadata
file. It deliberately has no keys, no expiry, no eviction, no encryption and
no C API: it maps a hash to bytes and nothing else.

Two documents outrank this file. [.agents/design.md](.agents/design.md) is
the specification, numbered §1–§20: every statement in it is a decision, and
open questions live only in its §18. [.agents/roadmap.md](.agents/roadmap.md)
sequences it into Stages 0–6, each with a **Status:** line under its heading.
Both were adopted on 2026-10-08 from
[RFC 0006](https://github.com/pedrobtz/packages/blob/main/rfcs/0006-zudedup-content-defined-chunking.md)
in `pedrobtz/packages`. `CLAUDE.md` orients, the design decides, the roadmap
sequences.

It is a member of the `zu*` family (sibling checkouts in `../`): an *engine*
package like `zurand`. `zufast` is the hash provider, `zucbor` the model for
conditions, guards and the mutation check, `dastash`
(`../dastash/.agents/cache-model.md` §11) the consumer whose blob layer this
is.

## Current state

**2026-10-08: Stages 0–5 done.** Every function of design §5 exists and is
documented, with a vignette. The boundary rule is design D14 (Python
`fastcdc` 1.7.0's exactly), and `conformance.yaml` checks it against Python
and the digests against `xxhsum`. Gates: `boundaries*.tsv`,
`hash-reference.tsv`, the fuzzer with its canary, lint, symbols, the mutation
check, the two-process test.

Since then the store's metadata file moved to `zujson` (#17), a URL or file
that cannot be opened is a `zudedup_io_error` (#18), and #22 records the
post-0.1.0 work (`dedup_serialize()`/`dedup_unserialize()`, the compression
caveat, `dedup_diff()` against zudiff).

Stage 6, the release (#8), is not started. It waited for zufast (and
zucrypt, a `Suggests`) on CRAN; both are there now (zufast 0.1.0 on
2026-10-21, zucrypt 0.1.0 on 2026-10-23, checked 2026-11-11), so it is
unblocked, but `Remotes:` still points at their `main` branches. zudedup is
not on CRAN.

Update this section at the end of every stage.

## Versions and dependents

The `v0.1.0` parent issue is #1, with stages #2–#8; the roadmap has seven
stages, 0 to 6. `.github/scripts/stage-cards.sh` in `pedrobtz/packages` puts
issue #1 on the board. A deviation from a stage's exit criteria is recorded in its
**Status:** line, and status never goes in a heading.

Until the first release the R API may change freely, **except the backend
interface** (design §9), which other packages will program against: change it
only with a recorded decision. zudedup depends on siblings before CRAN does:
`LinkingTo: zufast (>= 0.1.0)` and `Suggests: zucrypt`, both from `Remotes:`
during development. `Remotes:` goes at Stage 6, and the release is checked
against zufast's CRAN tarball. Sibling packages that depend on this one:
none yet; `dastash` will depend on zudedup after it is on CRAN, not before.

**The format constants are not versioned at all.** The gear table
(`src/zdd_gear.h`), the mask placement and the boundary fixture never change
after 0.1.0; a change would make every existing store unreadable. A new
chunking scheme would be a new parameter set recorded in the store's
metadata, never a change to the old one.

## Commands

The everyday `devtools` commands are in `.claude/shared/r-package.md`. The
check here runs in CRAN mode with the clock check off:

```sh
_R_CHECK_SYSTEM_CLOCK_=0 Rscript -e 'devtools::check(cran = TRUE)'
```

zufast and zucrypt are on CRAN; during development `Remotes:` installs them
from `main`, or from the sibling checkout (`R CMD INSTALL ../zufast`).
roxygen2 must be 8.1.0 or newer.

Gate scripts:

<!-- markdownlint-disable MD013 -->
```sh
Rscript tools/make-gear.R      # regenerate src/zdd_gear.h from the seed; must be byte-identical
tools/run-fuzz [secs]          # canary first, then fuzz_cdc (block independence) under ASan+UBSan;
                               # macOS: FUZZ_CC=/opt/homebrew/opt/llvm/bin/clang
                               # CANARY_ONLY=1 only proves the canary crashes
tools/run-lint                 # -Wall -Wextra -Wpedantic -Wshadow -Werror on project C
tools/check-symbols <so>       # only R_init_zudedup exported; no stdio/abort/exit/assert
tools/run-mutation-check       # every R `# GUARD:` seen to be load-bearing (needs pkgload, testthat)
tools/run-conformance          # Python fastcdc 1.7.0 and xxhsum agree (CI; locally with PYTHON=<venv python>)
tools/run-benchmarks [MB]      # chunk throughput, hashing, put vs writeBin; not a CI gate
```
<!-- markdownlint-enable MD013 -->

## Architecture

Layout, from design §4 and §13:

<!-- markdownlint-disable MD013 -->
```text
R/            chunk.R, manifest.R, validate.R, store.R, backend.R, diff.R, gc.R,
              conditions.R, args.R, info.R, zu_source.R (copied verbatim from zuxml),
              zudedup-package.R
src/          init.c                      registration only
              zdd_check.h                 the chunker's R-free interface
              zdd_gear.h                  THE FORMAT: 256 gear constants, the masks, the seed, the script
              zdd_cdc.c                   gear hash, normalised chunking, feed with carried state
              zdd_hash.c                  zufast XXH3-128 per chunk and streamed; hex rendering
              zdd_r.c                     .Call glue: state as a raw vector
              Makevars                    hand-listed OBJECTS, $(C_VISIBILITY)
fuzz/         fuzz_cdc.c (the canary is the same file built with -DZDD_FUZZ_CANARY), seeds/
              (not in the tarball)
tools/        make-gear.R, the gate scripts above, conformance.py, valgrind.supp
tests/testthat/fixtures/   boundaries.tsv, boundaries-small.tsv (the format gate), hash-reference.tsv
.agents/      design.md, roadmap.md
```
<!-- markdownlint-enable MD013 -->

The pipeline is: R reads blocks (1 MiB from a connection, or the whole raw
vector) → **chunker** (`zdd_cdc.c`, pure C, R-free; one `.Call` per block,
state in and out as a raw vector) → **hasher** (XXH3 in the same loop, or
`zucrypt::crypt_hash()` from R) → **manifest** (an R list with a class) →
**store** (R code over a backend; the filesystem backend writes to `tmp/` and
renames).

## Invariants that are easy to break

- **`src/zdd_gear.h` is a format.** Never edit it, regenerate it with a
  different seed, or change the mask placement after 0.1.0.
  `test-boundaries.R` against `fixtures/boundaries.tsv` is the permanent
  regression; if it fails, the code is wrong, not the fixture.
- **Block independence.** The chunker's only state is `h`, the current chunk
  length and the parameters; anything that looks at where a block starts or
  ends breaks the property. The fuzzer and `test-block-independence.R` check
  it; keep both.
- **The chunker contains no R.** `zdd_cdc.c` never includes `R.h`; the fuzz
  build (`-DZDD_STANDALONE`) compiles it standalone.
- **Chunker state crosses `.Call` as a raw vector**, never as an external
  pointer: there is nothing to finalize, so an interrupt between blocks leaks
  nothing. All scratch is `R_alloc()`ed.
- **The digest rendering is `high` then `low`**, lower-case hex (design §7,
  D12); `fixtures/hash-reference.tsv` pins it against libxxhash. The seed is
  0.
- **A manifest is validated whole before any chunk is read** (design §12):
  hex lengths, chunk lengths in `[1, max]`, sum equals `size`, `max_chunks`.
  Guards carry `# GUARD: name` markers on their `if` lines and a
  `test_that("GUARD name")` each; `tools/run-mutation-check` proves each.
- **A chunk whose bytes do not hash to its name is refused**, always, unless
  `verify = FALSE` was asked for; a store must not be able to substitute
  content.
- **`dedup_put()` writes to `tmp/` and renames**; a chunk is complete or
  absent. Never write into `objects/` directly.
- **The backend interface is the contract other packages hold** (design §9).
  Five functions, those signatures. Additions are fine; changes need a design
  decision.
- **XXH3 is documented as non-cryptographic** in every roxygen topic that
  names the default. Do not drop that sentence when editing documentation.
- **C never calls `Rf_error()`**; statuses come back by enumerator name and
  `R/conditions.R` raises.
- **Portable make only** in `src/Makevars`; hand-listed `OBJECTS`; no
  `Makevars.win`.

## Naming

<!-- markdownlint-disable MD013 -->
| Layer | Prefix | Examples |
| --- | --- | --- |
| R exports | `dedup_` plus `zudedup_info()` | `dedup_chunk()`, `dedup_store()`, `dedup_backend()` |
| R classes | `dedup_` | `dedup_manifest`, `dedup_backend` |
| R condition classes | `zudedup_` | `zudedup_error`, `zudedup_store_error` |
| R and C internals | `zdd_` / `ZDD_` | `zdd_cdc_feed()`, `ZDD_STANDALONE` |
| `.Call` entry points | `zudedup_` | `zudedup_cdc_feed` |
| Test-switching variables | `ZUDEDUP_` | `ZUDEDUP_SKIP_HEAVY`, `ZUDEDUP_SLOW_TESTS` |
<!-- markdownlint-enable MD013 -->

## Editing rules

These add to `.claude/shared/r-package.md`, or depart from it where stated.

- **No `README.Rmd`, unlike the shared rule**: edit `README.md` directly and
  run its example.
- Prose is en-GB (`Language: en-GB`, `inst/WORDLIST`).
- One hard runtime dependency, `zujson` (design D9); add none without a
  recorded decision. `zucrypt`, `dastash` and `callr` stay in `Suggests`.
- Every export has `@return` and runnable `@examples`.
- `R/zu_source.R` is copied verbatim from `../zuxml`; fix it there and
  re-copy.
- `NEWS.md` keeps a versioned heading.
- Branches for stages are `stage-N-<slug>`. Performance claims need evidence
  from `tools/run-benchmarks`. A defect found in `zufast` gets an issue there,
  not only a workaround here.

## Testing

- **Inputs** are bytes from `splitmix_bytes()` with a stated seed, or from
  hex. Every store lives under `withr::local_tempdir()`.
- **Assert on condition classes and fields (`hash`, `index`, `limit`)**,
  never message text.
- The suite runs serially: no `Config/testthat/parallel`.
- **The conformance oracle is the Python `fastcdc` package** with zudedup's
  gear table substituted, run only in the `conformance` CI job; nothing under
  `tests/` needs Python. It covers boundaries only. Digests are pinned once
  from libxxhash and hashlib into `hash-reference.tsv`, so the suite needs
  neither.
- **Helpers**: `helper-bytes.R` (`splitmix_bytes()`, `bytes()`),
  `helper-expect.R` (`expect_chunks()`, `expect_zudedup_error()`),
  `helper-manifest.R` (crafted manifests for `test-validate.R`:
  `good_manifest()`, `with_field()`, `expect_bad()`), `helper-store.R`
  (`local_store()`, `corrupt_chunk()`), `helper-skip.R` (`skip_heavy()` on
  `ZUDEDUP_SKIP_HEAVY`, `skip_if_no_slow_tests()` on `ZUDEDUP_SLOW_TESTS`).
- **Fixtures are data**: `boundaries*.tsv` and `hash-reference.tsv` are read
  with `colClasses = "character"` and never regenerated by a test.
- **CRAN time budget: under 15 s** (7.9 s locally at Stage 5). The 100 MB
  properties and the two-process test (`callr`) call `skip_heavy()` or
  `skip_if_not_installed()`.

## Definition of done

In addition to the shared definition: `gctorture(TRUE)` clean when C
changed. A change to a contract (the backend interface, the manifest shape,
the store layout) amends the design in the same commit. A stage is done when
its exit criteria pass in CI on all three platforms; a gate counts once it
has been seen to fail.

## Releasing to CRAN

The shared release steps apply. What is specific to zudedup:

- **Entering `Pre-flight`** (Stage 6) also needs `Remotes:` removed and the
  package checked against zufast's CRAN tarball, and each design §19
  acceptance criterion verified in a table naming what verifies it.
- **After acceptance,** also open dastash's adoption issue.

## Continuous integration

The workflows, all calling `pedrobtz/r-actions` pinned by commit:

- `R-CMD-check.yaml` (`r-cmd-check.yml`, v1.22.0). **A deviation from
  `ci.md`:** it runs quick on pull requests and full on every push to `main`
  and under `full-ci`, not `profile: auto`, and the full profile sets
  `ZUDEDUP_SLOW_TESTS=true` for the slow sweeps.
- `coverage.yaml` (`coverage.yml`, v1.22.0).
- `native-checks.yaml`: sanitizers, valgrind, LTO, gctorture and rchk
  (v1.22.0), weekly on Thursdays.
- `hardening.yaml`, the package's own: `gates` (`tools/run-lint`,
  `tools/check-symbols` with a planted defect, `tools/run-mutation-check`),
  `canary` (`CANARY_ONLY=1 tools/run-fuzz`), and `fuzz` through r-actions'
  `fuzz.yml` (v1.26.0) over `fuzz/fuzz_cdc.c`: 5 minutes per push, an hour
  nightly. Its jobs have timeouts (15 and 30 minutes) since a stuck
  `apt-get` held the canary for an hour.
- `conformance.yaml`, the package's own: Python `fastcdc` and `xxhsum`.
- `pkgdown.yaml`.

Dependabot updates the GitHub Actions weekly. **Stage pull requests carry
`full-ci`**, a deviation from the shared quick-by-default rule that the
roadmap sets. Nothing is vendored, so there is no `vendor.yaml`.
