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
