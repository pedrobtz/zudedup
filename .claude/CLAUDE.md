# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`zudedup` is an R package for content-defined chunking and content-addressed storage: it splits byte streams into variable-size chunks at content-chosen boundaries (FastCDC with a gear rolling hash, in C), hashes each chunk with XXH3-128 from `zufast` (`LinkingTo`, header-only) or SHA-256 from `zucrypt` (`Suggests`), builds manifests, diffs them, and stores chunks by hash in a dumb filesystem store behind a five-function backend interface that other packages (`dastash`, an mdbx or object-storage backend) implement. The one runtime dependency is `jsonlite`, for the store's metadata file, until `zujson` is on CRAN. It deliberately has no keys, no expiry, no eviction, no encryption and no C API: it maps a hash to bytes and nothing else.

Two documents outrank this file. [.agents/design.md](../.agents/design.md) is the specification, numbered §1–§20: every statement in it is a decision, and open questions live only in its §18. [.agents/roadmap.md](../.agents/roadmap.md) sequences it into Stages 0–6, each with a **Status:** line under its heading. Both were adopted on 2026-10-08 from [RFC 0006](https://github.com/pedrobtz/packages/blob/main/rfcs/0006-zudedup-content-defined-chunking.md) in `pedrobtz/packages`. `CLAUDE.md` orients, the design decides, the roadmap sequences.

It is a member of the `zu*` family (sibling checkouts in `../`): an *engine* package like `zurand`. `zufast` is the hash provider, `zucbor` the model for conditions, guards and the mutation check, `dastash` (`../dastash/.agents/cache-model.md` §11) the consumer whose blob layer this is.

## Current state

**2026-10-08: Stage 0 done.** The package checks 0/0/0 and the format constants are committed: `src/zdd_gear.h` (from `tools/make-gear.R`; the boundary rule is design D14, Python `fastcdc` 1.7.0's exactly, with a right shift and a table below 2^63) and the fixture input's seed (`helper-bytes.R`). There is no chunking code yet; Stage 1 adds the chunker and commits `boundaries.tsv`. Tracking: parent #1, stages #2–#8.

Update this paragraph at the end of every stage.

## Stage tracking

Progress toward the next version is tracked as GitHub sub-issues, so the parent issue shows a progress bar such as "6 of 7".

- **One parent issue per target version**, `v0.1.0`: #1. `.github/scripts/stage-cards.sh` in `pedrobtz/packages` puts it on the board.
- **One sub-issue per roadmap stage**, titled as the roadmap titles it, for example `Stage 1 — The chunker, block independence, fuzzing`, linking to that section's anchor. The roadmap has seven stages, 0 to 6.
- **Every tracking issue carries the `stage` label.**
- **Close a stage by merging its pull request.** Put `Closes #<n>` in the body. Never close a stage whose exit criteria are not met; record a deviation in its **Status:** line first.
- **The roadmap stays authoritative.** Adding, removing or renaming a stage means editing the roadmap and the sub-issues in the same change. Status never goes in a heading.
- Close the parent issue when CRAN accepts the version and it is tagged.

## Versioning

The package develops at `0.0.0.9000` and targets `0.1.0` for its first CRAN release. Set `Version: 0.1.0` and the matching `NEWS.md` heading when the package enters `Pre-flight` (Stage 6). Bump to `0.1.0.9000` only after CRAN accepts it.

Until the first release the R API may change freely, **except the backend interface** (design §9), which other packages will program against: change it only with a recorded decision. zudedup depends on a sibling before CRAN does: `LinkingTo: zufast (>= 0.1.0)` from `Remotes: pedrobtz/zufast@main` during development. **zufast must be on CRAN before zudedup is submitted**; `Remotes:` goes at Stage 6 and the release is checked against zufast's CRAN tarball. `dastash` will depend on zudedup after it is on CRAN, not before.

**The format constants are not versioned at all.** The gear table (`src/zdd_gear.h`), the mask placement and the boundary fixture never change after 0.1.0; a change would make every existing store unreadable. A new chunking scheme would be a new parameter set recorded in the store's metadata, never a change to the old one.

## Commands

Run from the package root.

```sh
Rscript -e 'devtools::load_all()'                # compile src/ and load
Rscript -e 'devtools::document()'                # roxygen -> NAMESPACE, man/
Rscript -e 'devtools::test()'                    # full testthat suite
Rscript -e 'devtools::test(filter = "<name>")'   # one test file
Rscript -e 'devtools::test(shuffle = TRUE)'      # order independence
_R_CHECK_SYSTEM_CLOCK_=0 Rscript -e 'devtools::check(cran = TRUE)'
air format .                                     # format R sources
```

zufast is not on CRAN: install it from the sibling checkout (`R CMD INSTALL ../zufast`) or `pak::pak("pedrobtz/zufast")`. roxygen2 must be 8.1.0 or newer.

Gate scripts, each arriving at the roadmap stage named:

```sh
Rscript tools/make-gear.R      # regenerate src/zdd_gear.h from the seed; must be byte-identical
tools/run-fuzz [secs]          # Stage 1: canary first, then fuzz_cdc (block independence) under ASan+UBSan
tools/run-lint                 # Stage 1: -Wall -Wextra -Wpedantic -Wshadow -Werror on project C
tools/check-symbols <so>       # Stage 1: only R_init_zudedup exported; no stdio/abort/exit/assert
tools/run-mutation-check       # Stage 3: every manifest and store guard seen to be load-bearing
tools/run-conformance          # Stage 5: Python fastcdc with our table agrees on every fixture (CI only)
tools/run-benchmarks           # Stage 5: chunk throughput, hashing, put vs writeBin; not a CI gate
```

## Architecture

Planned layout, from design §4 and §13. Nothing under `src/` beyond the template exists yet.

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
fuzz/         fuzz_cdc.c, fuzz_canary.c (not in the tarball)
tools/        make-gear.R and the gate scripts above
tests/testthat/fixtures/   boundaries.tsv (the format gate), xxh3-reference.tsv, small files
.agents/      design.md, roadmap.md
```

The pipeline is: R reads blocks (1 MiB from a connection, or the whole raw vector) → **chunker** (`zdd_cdc.c`, pure C, R-free; one `.Call` per block, state in and out as a raw vector) → **hasher** (XXH3 in the same loop, or `zucrypt::crypt_hash()` from R) → **manifest** (an R list with a class) → **store** (R code over a backend; the filesystem backend writes to `tmp/` and renames).

## Invariants that are easy to break

- **`src/zdd_gear.h` is a format.** Never edit it, regenerate it with a different seed, or change the mask placement after 0.1.0. `test-boundaries.R` against `fixtures/boundaries.tsv` is the permanent regression; if it fails, the code is wrong, not the fixture.
- **Block independence.** The chunker's only state is `h`, the current chunk length and the parameters; anything that looks at where a block starts or ends breaks the property. The fuzzer and `test-block-independence.R` check it; keep both.
- **The chunker contains no R.** `zdd_cdc.c` never includes `R.h`; the fuzz build (`-DZDD_STANDALONE`) compiles it standalone.
- **Chunker state crosses `.Call` as a raw vector**, never as an external pointer: there is nothing to finalize, so an interrupt between blocks leaks nothing. All scratch is `R_alloc()`ed.
- **The digest rendering is `high` then `low`**, lower-case hex (design §7, D12); `fixtures/xxh3-reference.tsv` pins it against `xxhsum`. The seed is 0.
- **A manifest is validated whole before any chunk is read** (design §12): hex lengths, chunk lengths in `[1, max]`, sum equals `size`, `max_chunks`. Guards carry `/* GUARD */` markers or named tests, and `tools/run-mutation-check` proves each.
- **A chunk whose bytes do not hash to its name is refused**, always, unless `verify = FALSE` was asked for; a store must not be able to substitute content.
- **`dedup_put()` writes to `tmp/` and renames**; a chunk is complete or absent. Never write into `objects/` directly.
- **The backend interface is the contract other packages hold** (design §9). Five functions, those signatures. Additions are fine; changes need a design decision.
- **XXH3 is documented as non-cryptographic** in every roxygen topic that names the default. Do not drop that sentence when editing documentation.
- **C never calls `Rf_error()`**; statuses come back by enumerator name and `R/conditions.R` raises.
- **Portable make only** in `src/Makevars`; hand-listed `OBJECTS`; no `Makevars.win`.

## Naming

| Layer | Prefix | Examples |
|---|---|---|
| R exports | `dedup_` plus `zudedup_info()` | `dedup_chunk()`, `dedup_store()`, `dedup_backend()` |
| R classes | `dedup_` | `dedup_manifest`, `dedup_backend` |
| R condition classes | `zudedup_` | `zudedup_error`, `zudedup_store_error` |
| R and C internals | `zdd_` / `ZDD_` | `zdd_cdc_feed()`, `ZDD_STANDALONE` |
| `.Call` entry points | `zudedup_` | `zudedup_cdc_feed` |
| Test-switching variables | `ZUDEDUP_` | `ZUDEDUP_SKIP_HEAVY`, `ZUDEDUP_SLOW_TESTS` |

## Testing conventions

- **Self-sufficient.** Inputs built inside each `test_that()`; bytes from `splitmix_bytes()` with a stated seed or from hex. No file-scope objects; shared code in `helper-*.R`.
- **Self-contained.** Every store under `withr::local_tempdir()`; global state through `withr::local_*()`.
- **Assert on condition classes and fields (`hash`, `index`, `limit`), never message text.**
- **Order independence.** `devtools::test(shuffle = TRUE)` is part of the definition of done; serial, no `Config/testthat/parallel`.
- **The conformance oracle is the Python `fastcdc` package** with zudedup's gear table substituted, run only in the `conformance` CI job; nothing under `tests/` needs Python. It covers boundaries only. Digests are pinned once from `xxhsum` into a fixture, so the suite needs no `xxhsum` either.
- **Helpers in `tests/testthat/helper-*.R`**: `helper-bytes.R` (`splitmix_bytes()`, `bytes()`), `helper-expect.R` (`expect_chunks()`, `expect_zudedup_error()`), `helper-store.R` (`local_store()`, `corrupt_chunk()`), `helper-skip.R` (`skip_heavy()` on `ZUDEDUP_SKIP_HEAVY`, `skip_if_no_slow_tests()` on `ZUDEDUP_SLOW_TESTS`).
- **Fixtures are data**: `boundaries.tsv` and `xxh3-reference.tsv` are read with `colClasses = "character"` and never regenerated by a test.
- **Keep the suite inside the CRAN time budget:** under 15 s; the 100 MB properties and the two-process test (`callr`) call `skip_heavy()` or `skip_if_not_installed()`.

## Definition of done

`devtools::document()` and `devtools::check()` clean, meaning 0 errors, 0 warnings and 0 notes. The one allowed note is "New submission" before the first release. `devtools::test(shuffle = TRUE)` green. `gctorture(TRUE)` clean when C changed. CI green on every leg. A user-facing change also needs a test, roxygen documentation and a `NEWS.md` entry. A change to a contract (the backend interface, the manifest shape, the store layout) amends the design in the same commit. A stage is done when its exit criteria pass in CI on all three platforms; a gate counts once it has been seen to fail.

## Releasing to CRAN

- **CI is the pre-submission check.** The `pedrobtz/r-actions` R CMD check runs `--as-cran` on the CRAN-like runners and containers, and replaces win-builder, the macOS builder and R-hub. `cran-comments.md` lists the CI legs as its test environments.
- **Entering `Pre-flight`.** Stages 0–5 done, `Version: 0.1.0` with the `NEWS.md` heading, `cran-comments.md` written, CI green, zufast on CRAN and `Remotes:` removed.
- **Before submitting,** run the `cran-extrachecks` and `review-cran-submission` skills and resolve every finding.
- **The pretest is automated and does not read `cran-comments.md`.** Fix every NOTE.
- **After acceptance,** tag `v0.1.0`, publish the GitHub release, bump to `0.1.0.9000`, close the parent issue, and open dastash's adoption issue.

## Editing rules

- roxygen comments are the source. Never edit `man/` or `NAMESPACE` by hand.
- There is no `README.Rmd`; edit `README.md` directly and run its example.
- Prose is simple, short and en-GB (`Language: en-GB`, `inst/WORDLIST`).
- Wrap roxygen at 80 characters; `air format .` on R sources.
- `lower_snake_case`; the naming table above.
- One hard runtime dependency, `jsonlite` (design D9); add none without a recorded decision. `zucrypt`, `dastash` and `callr` stay in `Suggests`.
- Every export has `@return` and runnable `@examples`; no roxygen topics for internals.
- `R/zu_source.R` is copied verbatim from `../zuxml`; fix it there and re-copy.
- `NEWS.md` keeps a versioned heading.

## Continuous integration

Workflows come from `pedrobtz/r-actions`. The scaffold's `R-CMD-check.yaml` (quick on pull requests, full on `main` and under `full-ci`), `coverage.yaml` and `pkgdown.yaml` exist at `@v1`; Stage 0 pins `coverage.yaml` by commit and adds Dependabot. The roadmap's CI table says which stage adds `hardening.yaml` (fuzz, lint, symbols, mutation check), `native-checks.yaml` (UBSan, ASan, valgrind, LTO, gctorture, blocking rchk) and `conformance.yaml` (Python `fastcdc`). Stage pull requests carry `full-ci`. Nothing is vendored, so there is no `vendor.yaml`.

This file lives in `.claude/`, not the package root, because pkgdown renders every root-level `*.md` as a site page (alignment rule R8 in `pedrobtz/packages`); keep it here.

## Commits and pull requests

Short, imperative, sentence-case commit subjects, optionally scoped. Keep each commit focused and do not sweep in unrelated files. A pull request explains the user-visible outcome and the rationale, links related issues, lists the checks that were run and the tests that were skipped, and flags platform-sensitive changes. Performance claims need evidence from `tools/run-benchmarks`.

Never commit or push to the default branch. Work on a branch (`stage-N-<slug>`), open a pull request, and leave it for review. Do not merge a pull request unless you are told to.

When you find a defect, in this package, in `zufast` or in an upstream tool, open an issue for it rather than only working around it.
