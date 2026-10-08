/* .Call glue. Everything that touches R's API lives in this file and in
   init.c; the chunker (zdd_cdc.c) is R-free (design section 4). C never
   raises: a failure comes back as a status name and R/conditions.R raises
   (design section 11). */
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <stdio.h>
#include <string.h>

#include "zdd_check.h"
#include "zdd_gear.h"
#include "zdd_r.h"

/* The chunker state crosses .Call as a raw vector (design section 13, D13):
   a magic number, then the zdd_cdc struct, copied in and out, so nothing
   points into R's memory between calls and there is nothing to finalize. */
#define ZDD_STATE_MAGIC UINT64_C(0x7a64647374617431)   /* "zddstat1" */
#define ZDD_STATE_SIZE  (sizeof(uint64_t) + sizeof(zdd_cdc))

static SEXP state_new(const zdd_cdc *c)
{
    SEXP s = Rf_allocVector(RAWSXP, (R_xlen_t) ZDD_STATE_SIZE);
    uint64_t magic = ZDD_STATE_MAGIC;
    memcpy(RAW(s), &magic, sizeof magic);
    memcpy(RAW(s) + sizeof magic, c, sizeof *c);
    return s;
}

static zdd_status state_get(SEXP s, zdd_cdc *c)
{
    uint64_t magic;
    if (TYPEOF(s) != RAWSXP || (size_t) XLENGTH(s) != ZDD_STATE_SIZE)
        return ZDD_ERR_STATE;
    memcpy(&magic, RAW(s), sizeof magic);
    if (magic != ZDD_STATE_MAGIC)
        return ZDD_ERR_STATE;
    memcpy(c, RAW(s) + sizeof magic, sizeof *c);
    return ZDD_OK;
}

/* list(status, ...): status is NULL on success, else the enumerator's name. */
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

SEXP zudedup_cdc_init(SEXP min, SEXP avg, SEXP max)
{
    zdd_cdc c;
    zdd_status st = zdd_cdc_init(&c, as_u64(min), as_u64(avg), as_u64(max));
    const char *names[] = {"state"};
    SEXP values[1];
    values[0] = st == ZDD_OK ? PROTECT(state_new(&c)) : PROTECT(R_NilValue);
    SEXP out = result(st, 1, names, values);
    UNPROTECT(1);
    return out;
}

/* Feeds one block. Returns the new state (a fresh vector: the old one may be
   shared, so it is never written), the in-block end offsets of the chunks
   that end here, and the length of the chunk still in progress. */
SEXP zudedup_cdc_feed(SEXP state, SEXP block)
{
    zdd_cdc c;
    const char *names[] = {"state", "cuts", "pending"};
    SEXP values[3] = {R_NilValue, R_NilValue, R_NilValue};
    zdd_status st = state_get(state, &c);
    if (st != ZDD_OK || TYPEOF(block) != RAWSXP)
        return result(st != ZDD_OK ? st : ZDD_ERR_STATE, 3, names, values);

    size_t n = (size_t) XLENGTH(block);
    size_t cap = zdd_cdc_max_cuts(&c, n);
    size_t *cuts = (size_t *) R_alloc(cap, sizeof(size_t));
    size_t k = zdd_cdc_feed(&c, RAW(block), n, cuts);

    values[0] = PROTECT(state_new(&c));
    values[1] = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t) k));
    double *out = REAL(values[1]);
    for (size_t i = 0; i < k; i++)
        out[i] = (double) cuts[i];
    values[2] = PROTECT(Rf_ScalarReal((double) c.n));
    SEXP res = result(ZDD_OK, 3, names, values);
    UNPROTECT(3);
    return res;
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
