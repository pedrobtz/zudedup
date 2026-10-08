/* .Call glue. Everything that touches R's API lives in this file and in
   init.c; the chunker (zdd_cdc.c) is R-free (design section 4). */
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <stdio.h>

#include "zdd_gear.h"
#include "zdd_r.h"

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
