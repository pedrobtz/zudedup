#ifndef ZDD_CHECK_H
#define ZDD_CHECK_H

/* The chunker's interface (design sections 4 and 6), with no R in sight, so
 * that it builds without R for fuzzing: fuzz/ compiles zdd_cdc.c with
 * -DZDD_STANDALONE. Nothing here allocates; the caller owns every buffer. */

#include <stddef.h>
#include <stdint.h>

/* The parameter ranges of design section 5: the Python fastcdc package's, so
 * the conformance test covers every legal setting. */
#define ZDD_MIN_LO  UINT64_C(64)
#define ZDD_MIN_HI  (UINT64_C(1) << 26)
#define ZDD_AVG_LO  UINT64_C(256)
#define ZDD_AVG_HI  (UINT64_C(1) << 28)
#define ZDD_MAX_LO  UINT64_C(1024)
#define ZDD_MAX_HI  (UINT64_C(1) << 30)

/* Statuses, reported to R by name (zdd_status_name()); R raises. */
typedef enum {
    ZDD_OK = 0,
    ZDD_ERR_PARAMS,     /* min, avg or max out of range or out of order */
    ZDD_ERR_STATE       /* a state vector of the wrong size or magic */
} zdd_status;

/* The chunker's whole state: block independence (design section 6.3) holds
 * because nothing else is carried from one block to the next. Plain
 * integers only, so it can be copied byte for byte. */
typedef struct {
    uint64_t h;         /* the gear hash of the chunk so far */
    uint64_t n;         /* bytes in the chunk so far */
    uint64_t min, max;
    uint64_t normal;    /* the last length tested with mask_s */
    uint64_t mask_s, mask_l;
} zdd_cdc;

/* Checks the parameters and starts a chunker at the beginning of an input. */
zdd_status zdd_cdc_init(zdd_cdc *c, uint64_t min, uint64_t avg, uint64_t max);

/* The most cuts a block of n bytes can contain: a cut needs a chunk of at
 * least min + 1 bytes (or max, if smaller), except the first, which may
 * complete a chunk begun in an earlier block. */
size_t zdd_cdc_max_cuts(const zdd_cdc *c, size_t n);

/* Feeds n bytes. Writes the 0-based offset, within this block, just past the
 * last byte of each chunk that ends in it, and returns how many. `cuts` must
 * hold zdd_cdc_max_cuts(c, n). The chunk in progress at the end (c->n bytes)
 * continues into the next block; at the end of the input it is the last
 * chunk. */
size_t zdd_cdc_feed(zdd_cdc *c, const uint8_t *p, size_t n, size_t *cuts);

const char *zdd_status_name(zdd_status s);

#endif
