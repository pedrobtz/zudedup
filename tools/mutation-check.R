# The engine of tools/run-mutation-check; see there.
suppressMessages(pkgload::load_all(".", quiet = TRUE, export_all = TRUE))
ns <- asNamespace("zudedup")
tests <- list.files("tests/testthat", "^test-.*\\.R$", full.names = TRUE)
test_text <- setNames(lapply(tests, readLines), tests)

# Evaluates a file's top-level assignments into the namespace.
load_into_ns <- function(lines, file) {
  exprs <- parse(text = lines, keep.source = FALSE)
  for (e in exprs) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) && is.name(e[[2]])) {
      name <- as.character(e[[2]])
      if (exists(name, envir = ns, inherits = FALSE) && bindingIsLocked(name, ns)) {
        unlockBinding(name, ns)
      }
      assign(name, eval(e[[3]], ns), envir = ns)
    }
  }
}

# The source range of the condition of the `if` on line `line`.
condition_range <- function(pd, line) {
  ifs <- pd[pd$token == "IF" & pd$line1 == line, ]
  if (nrow(ifs) != 1L) stop("expected one `if` on line ", line)
  stmt <- ifs$parent
  kids <- pd[pd$parent == stmt, ]
  kids <- kids[order(kids$line1, kids$col1), ]
  open <- which(kids$token == "'('")[1]
  kids[open + 1L, c("line1", "col1", "line2", "col2")]
}

mutate <- function(lines, r) {
  if (r$line1 != r$line2) {
    first <- substr(lines[r$line1], 1, r$col1 - 1)
    last <- substr(lines[r$line2], r$col2 + 1, nchar(lines[r$line2]))
    lines[r$line1] <- paste0(first, "FALSE", last)
    lines <- lines[-seq(r$line1 + 1, r$line2)]
  } else {
    l <- lines[r$line1]
    lines[r$line1] <- paste0(substr(l, 1, r$col1 - 1), "FALSE",
                             substr(l, r$col2 + 1, nchar(l)))
  }
  lines
}

run_guard_test <- function(name) {
  desc <- paste("GUARD", name)
  hit <- names(Filter(function(t) any(grepl(sprintf('test_that("%s"', desc), t, fixed = TRUE)),
                      test_text))
  if (length(hit) != 1L) stop(sprintf("expected one test named \"%s\", found %d", desc, length(hit)))
  res <- as.data.frame(testthat::test_file(hit, desc = desc, package = "zudedup",
                                           load_package = "none",
                                           reporter = testthat::SilentReporter$new()))
  if (nrow(res) == 0L) stop("no test ran for ", desc)
  !any(res$failed > 0 | res$error)
}

failed <- FALSE
for (f in list.files("R", "\\.R$", full.names = TRUE)) {
  lines <- readLines(f)
  marks <- grep("\\bif \\(.*# GUARD: [a-z]", lines)
  if (!length(marks)) next
  pd <- getParseData(parse(f, keep.source = TRUE))
  for (line in marks) {
    name <- sub(".*# GUARD: ([a-z0-9-]+).*", "\\1", lines[line])
    if (!run_guard_test(name)) {
      cat(sprintf("FAIL: %s: its test fails even with the guard in place\n", name))
      failed <- TRUE
      next
    }
    load_into_ns(mutate(lines, condition_range(pd, line)), f)
    passed <- tryCatch(run_guard_test(name), error = function(e) FALSE)
    load_into_ns(lines, f)
    if (passed) {
      cat(sprintf("FAIL: %s (%s:%d): removing the guard changes nothing\n", name, f, line))
      failed <- TRUE
    } else {
      cat(sprintf("==> %s: its test fails without the guard\n", name))
    }
  }
}
if (failed) quit(status = 1)
cat("==> every guard is load-bearing\n")
