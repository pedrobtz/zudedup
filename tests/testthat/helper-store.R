# Stores for tests. Every store test runs against two backends: the
# filesystem store, and a dedup_backend() of five closures over an
# environment, which proves the interface by a second instance (roadmap
# Stage 3). Both are removed when the calling test ends.

store_kinds <- c("filesystem", "environment")

local_store <- function(kind = "filesystem", ..., env = parent.frame()) {
  if (kind == "filesystem") {
    dir <- withr::local_tempdir(.local_envir = env)
    return(dedup_store(file.path(dir, "store"), create = TRUE, ...))
  }
  e <- new.env(parent = emptyenv())
  dedup_backend(
    has = function(hashes) vapply(hashes, exists, TRUE, envir = e,
                                  inherits = FALSE, USE.NAMES = FALSE),
    get = function(hash) get0(hash, envir = e, inherits = FALSE),
    put = function(hash, bytes) assign(hash, bytes, envir = e),
    delete = function(hashes) rm(list = hashes, envir = e),
    list = function() ls(e, all.names = TRUE),
    ...
  )
}

# Replaces a stored chunk's bytes behind the store's back.
corrupt_chunk <- function(store, hash, bytes) {
  if (store$kind == "filesystem") {
    writeBin(bytes, file.path(store$path, "objects", substr(hash, 1, 2), hash))
  } else {
    environment(store$put)$e[[hash]] <- bytes
  }
}

# The number of chunks a store holds.
stored_count <- function(store) length(store$list())

# A background R process that puts the file `data` into the store at `path`
# and returns the manifest. Under devtools::test() the package is not
# installed, so the process loads the same source with pkgload; under R CMD
# check it loads the installed package from the same library path.
start_put <- function(path, data) {
  dev <- exists(".__DEVTOOLS__", envir = asNamespace("zudedup"), inherits = FALSE)
  root <- if (dev) normalizePath(test_path("..", "..")) else ""
  callr::r_bg(function(dev, root, path, data) {
    if (dev) {
      getExportedValue("pkgload", "load_all")(root, quiet = TRUE, compile = FALSE)
    }
    s <- zudedup::dedup_store(path)
    zudedup::dedup_put(s, data)
  }, args = list(dev = dev, root = root, path = path, data = data),
  package = FALSE)
}
