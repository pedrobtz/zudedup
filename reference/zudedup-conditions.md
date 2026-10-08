# Conditions raised by zudedup

Every error zudedup raises carries a condition class, so it can be
caught by kind rather than by matching the message, which may change.
Every class below inherits from `zudedup_error`.

## Details

- `zudedup_invalid_argument`:

  An argument was unusable: chunking parameters out of range, a
  malformed manifest, an unknown hash algorithm, or a backend without
  the function an operation needs. The condition carries `arg`, the
  argument at fault.

- `zudedup_store_error`:

  A chunk is missing from a store, or its bytes do not hash to its name,
  or the store itself is unusable. The condition carries `hash`, the
  chunk's digest, and `index`, its 1-based position in the manifest,
  where they apply.

- `zudedup_algorithm_error`:

  A manifest's hash algorithm or chunking parameters differ from the
  store's or from another manifest's.

- `zudedup_io_error`:

  A connection or file could not be read or written.

- `zudedup_limit_error`:

  A limit was reached. The condition carries `limit`, the argument's
  name, such as `"max_chunks"`, and `limit_value`.
