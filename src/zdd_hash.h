#ifndef ZDD_HASH_H
#define ZDD_HASH_H

/* XXH3-128 through zufast (design section 7), seed 0, so digests equal
 * upstream XXH3's and xxhsum -H2's. R-free. */

#include <stddef.h>
#include <stdint.h>

#include <zufast/hash.h>

/* 32 lower-case hex characters and a NUL: the canonical big-endian
 * rendering, high then low (D12). */
#define ZDD_HEX128 33
void zdd_hex128(zuf_digest128 d, char out[ZDD_HEX128]);

#endif
