## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new release.

## Test environments

The checks below run on every change through the `pedrobtz/r-actions`
reusable workflows, with `--as-cran`:

* macOS (latest), R release
* Windows (latest), R release
* Ubuntu (latest), R release and oldrel-1
* Ubuntu with gcc 16 and with clang, and the clang 23 container
* UBSan (gcc and clang), ASan (gcc and clang containers), valgrind, LTO,
  gctorture and rchk (`native-checks.yaml`)

## Notes for the reviewer

* zudedup links to zufast (`LinkingTo`), which was submitted first.
* The C code is checked by libFuzzer under ASan and UBSan, a lint gate, a
  symbol check and a mutation check on every guard (`hardening.yaml`), and
  its chunk boundaries agree with the Python `fastcdc` package's
  (`conformance.yaml`).
