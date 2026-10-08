# Skips a test that runs over 100 MB of input or several processes. It checks
# a property, not memory safety, and under gctorture or valgrind it would take
# hours; native-checks.yaml sets ZUDEDUP_SKIP_HEAVY for those jobs.
skip_heavy <- function() {
  skip_on_cran()
  skip_if(nzchar(Sys.getenv("ZUDEDUP_SKIP_HEAVY")), "ZUDEDUP_SKIP_HEAVY is set")
}

# Skips the slow sweeps unless ZUDEDUP_SLOW_TESTS is set, which the full CI
# profile does.
skip_if_no_slow_tests <- function() {
  skip_if_not(nzchar(Sys.getenv("ZUDEDUP_SLOW_TESTS")), "ZUDEDUP_SLOW_TESTS is not set")
}
