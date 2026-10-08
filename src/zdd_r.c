/* .Call glue. Everything that touches R's API lives in this file and in
   init.c; the chunker (zdd_cdc.c) and the hasher (zdd_hash.c) are R-free
   (design section 4). C never raises: a failure comes back as a status name
   and R/conditions.R raises (design section 11). */
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <stdio.h>
#include <string.h>

#include <zufast/version.h>

#include "zdd_check.h"
#include "zdd_gear.h"
#include "zdd_hash.h"
#include "zdd_r.h"

/* The state crosses .Call as a raw vector (design sections 6.3 and 13,
   D13): a header, then, when C hashes, a zuf_hasher for the chunk in
   progress and one for the whole object. A zuf_hasher needs 64-byte
   alignment and a raw vector's data does not have it, so the state is
   copied into an aligned local, used there, and copied out to a fresh
   vector: nothing points into R's memory between calls and there is nothing
   to finalize. XXH3's state holds a pointer to its default secret in this
   shared object, so a state is good only in the process that made it; it
   never leaves the R function that created it. */
#define ZDD_STATE_MAGIC UINT64_C(0x7a64647374617432)   /* "zddstat2" */

typedef struct {
    uint64_t magic;
    uint64_t hashing;   /* 1: XXH3-128 per chunk and over the object */
    zdd_cdc cdc;
} zdd_head;

typedef struct {
    zdd_head head;
    zuf_hasher chunk, object;
} zdd_state;

static size_t state_size(int hashing)
{
    return sizeof(zdd_head) + (hashing ? 2 * sizeof(zuf_hasher) : 0);
}

static SEXP state_new(const zdd_state *s)
{
    int hashing = (int) s->head.hashing;
    SEXP v = Rf_allocVector(RAWSXP, (R_xlen_t) state_size(hashing));
    memcpy(RAW(v), &s->head, sizeof s->head);
    if (hashing) {
        memcpy(RAW(v) + sizeof s->head, &s->chunk, sizeof s->chunk);
        memcpy(RAW(v) + sizeof s->head + sizeof s->chunk, &s->object,
               sizeof s->object);
    }
    return v;
}

static zdd_status state_get(SEXP v, zdd_state *s)
{
    if (TYPEOF(v) != RAWSXP || (size_t) XLENGTH(v) < sizeof(zdd_head))
        return ZDD_ERR_STATE;
    memcpy(&s->head, RAW(v), sizeof s->head);
    if (s->head.magic != ZDD_STATE_MAGIC || s->head.hashing > 1 ||
        (size_t) XLENGTH(v) != state_size((int) s->head.hashing))
        return ZDD_ERR_STATE;
    if (s->head.hashing) {
        memcpy(&s->chunk, RAW(v) + sizeof s->head, sizeof s->chunk);
        memcpy(&s->object, RAW(v) + sizeof s->head + sizeof s->chunk,
               sizeof s->object);
    }
    return ZDD_OK;
}

/* list(status, ...): status is NULL on success, else the enumerator's name.
   values[] must be protected by the caller. */
static SEXP result(zdd_status st, int n, const char **names, SEXP *values)
{
    SEXP out = PROTECT(Rf_allocVector(VECSXP, n + 1));
    SEXP nm = PROTECT(Rf_allocVector(STRSXP, n + 1));
    SET_STRING_ELT(nm, 0, Rf_mkChar("status"));
    if (st != ZDD_OK)
        SET_VECTOR_ELT(out, 0, Rf_mkString(zdd_status_name(st)));
    for (int i = 0; i < n; i++) {
        SET_STRING_ELT(nm, i + 1, Rf_mkChar(names[i]));
        SET_VECTOR_ELT(out, i + 1, values[i]);
    }
    Rf_setAttrib(out, R_NamesSymbol, nm);
    UNPROTECT(2);
    return out;
}

static uint64_t as_u64(SEXP x)
{
    double d = Rf_asReal(x);
    return (d >= 0 && d < 18446744073709551616.0) ? (uint64_t) d : 0;
}

static SEXP mk_hex(zuf_digest128 d)
{
    char hex[ZDD_HEX128];
    zdd_hex128(d, hex);
    return Rf_mkChar(hex);
}

SEXP zudedup_cdc_init(SEXP min, SEXP avg, SEXP max, SEXP hashing)
{
    zdd_state s;
    const char *names[] = {"state"};
    SEXP values[1] = {R_NilValue};
    memset(&s.head, 0, sizeof s.head);
    s.head.magic = ZDD_STATE_MAGIC;
    s.head.hashing = Rf_asLogical(hashing) == 1;
    zdd_status st = zdd_cdc_init(&s.head.cdc, as_u64(min), as_u64(avg), as_u64(max));
    if (st != ZDD_OK)
        return result(st, 1, names, values);
    if (s.head.hashing) {
        zuf_hasher_init(&s.chunk, 0);
        zuf_hasher_init(&s.object, 0);
    }
    values[0] = PROTECT(state_new(&s));
    SEXP out = result(ZDD_OK, 1, names, values);
    UNPROTECT(1);
    return out;
}

/* Feeds one block. Returns the new state (a fresh vector: the old one may be
   shared, so it is never written), the in-block end offsets of the chunks
   that end here, their digests when C hashes, and the length of the chunk
   still in progress. */
SEXP zudedup_cdc_feed(SEXP state, SEXP block)
{
    zdd_state s;
    const char *names[] = {"state", "cuts", "hashes", "pending"};
    SEXP values[4] = {R_NilValue, R_NilValue, R_NilValue, R_NilValue};
    zdd_status st = state_get(state, &s);
    if (st != ZDD_OK || TYPEOF(block) != RAWSXP)
        return result(ZDD_ERR_STATE, 4, names, values);

    const uint8_t *p = RAW(block);
    size_t n = (size_t) XLENGTH(block);
    /* Bytes of the chunk in progress already in the chunk hasher. */
    int carried = s.head.cdc.n > 0;
    size_t cap = zdd_cdc_max_cuts(&s.head.cdc, n);
    size_t *cuts = (size_t *) R_alloc(cap, sizeof(size_t));
    size_t k = zdd_cdc_feed(&s.head.cdc, p, n, cuts);

    values[0] = R_NilValue;
    values[1] = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t) k));
    for (size_t i = 0; i < k; i++)
        REAL(values[1])[i] = (double) cuts[i];
    values[2] = PROTECT(Rf_allocVector(STRSXP, s.head.hashing ? (R_xlen_t) k : 0));
    if (s.head.hashing) {
        zuf_hasher_update(&s.object, p, n);
        size_t from = 0;
        for (size_t i = 0; i < k; i++) {
            zuf_digest128 d;
            if (carried) {
                zuf_hasher_update(&s.chunk, p, cuts[i]);
                d = zuf_hasher_digest128(&s.chunk);
                carried = 0;
            } else {
                d = zuf_hash128(p + from, cuts[i] - from);
            }
            SET_STRING_ELT(values[2], (R_xlen_t) i, mk_hex(d));
            from = cuts[i];
        }
        if (from < n) {
            if (!carried)
                zuf_hasher_init(&s.chunk, 0);
            zuf_hasher_update(&s.chunk, p + from, n - from);
        }
    }
    values[0] = PROTECT(state_new(&s));
    values[3] = PROTECT(Rf_ScalarReal((double) s.head.cdc.n));
    SEXP res = result(ZDD_OK, 4, names, values);
    UNPROTECT(4);
    return res;
}

/* The end of the input: the digest of the chunk in progress (NA when there
   is none) and of the whole object. Only for a hashing state. */
SEXP zudedup_cdc_finish(SEXP state)
{
    zdd_state s;
    const char *names[] = {"last", "object"};
    SEXP values[2] = {R_NilValue, R_NilValue};
    zdd_status st = state_get(state, &s);
    if (st != ZDD_OK || !s.head.hashing)
        return result(ZDD_ERR_STATE, 2, names, values);
    values[0] = PROTECT(Rf_allocVector(STRSXP, 1));
    SET_STRING_ELT(values[0], 0, s.head.cdc.n > 0
                   ? mk_hex(zuf_hasher_digest128(&s.chunk)) : NA_STRING);
    values[1] = PROTECT(Rf_allocVector(STRSXP, 1));
    SET_STRING_ELT(values[1], 0, mk_hex(zuf_hasher_digest128(&s.object)));
    SEXP res = result(ZDD_OK, 2, names, values);
    UNPROTECT(2);
    return res;
}

/* XXH3-128 of a raw vector, one shot: what a store checks a chunk with. */
SEXP zudedup_xxh3(SEXP x)
{
    if (TYPEOF(x) != RAWSXP)
        return R_NilValue;
    SEXP out = PROTECT(Rf_allocVector(STRSXP, 1));
    SET_STRING_ELT(out, 0, mk_hex(zuf_hash128(RAW(x), (size_t) XLENGTH(x))));
    UNPROTECT(1);
    return out;
}

SEXP zudedup_build_info(void)
{
    char seed[19];
    snprintf(seed, sizeof seed, "0x%08lx%08lx",
             (unsigned long) (ZDD_GEAR_SEED >> 32),
             (unsigned long) (ZDD_GEAR_SEED & 0xffffffffu));
    SEXP out = PROTECT(Rf_allocVector(STRSXP, 2));
    SET_STRING_ELT(out, 0, Rf_mkChar(ZUFAST_VERSION));
    SET_STRING_ELT(out, 1, Rf_mkChar(seed));
    UNPROTECT(1);
    return out;
}

/* The gear table as 256 lower-case hex strings, for test-gear.R to compare
   with a regeneration from the seed. */
SEXP zudedup_gear_table(void)
{
    SEXP out = PROTECT(Rf_allocVector(STRSXP, 256));
    char buf[17];
    for (int i = 0; i < 256; i++) {
        uint64_t g = zdd_gear[i];
        snprintf(buf, sizeof buf, "%08lx%08lx",
                 (unsigned long) (g >> 32), (unsigned long) (g & 0xffffffffu));
        SET_STRING_ELT(out, i, Rf_mkChar(buf));
    }
    UNPROTECT(1);
    return out;
}
