#ifndef ZDD_R_H
#define ZDD_R_H

#define R_NO_REMAP
#include <Rinternals.h>

SEXP zudedup_cdc_init(SEXP min, SEXP avg, SEXP max);
SEXP zudedup_cdc_feed(SEXP state, SEXP block);
SEXP zudedup_gear_table(void);

#endif
