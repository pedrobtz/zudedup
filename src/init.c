#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

#include "zdd_r.h"

/* The .Call table. Entry points arrive with the stages that need them
   (roadmap); R_useDynamicSymbols(FALSE) keeps anything not listed here
   unreachable by name. */
static const R_CallMethodDef CallEntries[] = {
    {"zudedup_cdc_init",   (DL_FUNC) &zudedup_cdc_init,   4},
    {"zudedup_cdc_feed",   (DL_FUNC) &zudedup_cdc_feed,   2},
    {"zudedup_cdc_finish", (DL_FUNC) &zudedup_cdc_finish, 1},
    {"zudedup_xxh3",       (DL_FUNC) &zudedup_xxh3,       1},
    {"zudedup_build_info", (DL_FUNC) &zudedup_build_info, 0},
    {"zudedup_gear_table", (DL_FUNC) &zudedup_gear_table, 0},
    {NULL, NULL, 0}
};

/* attribute_visible: Makevars builds with $(C_VISIBILITY), which hides
   every other symbol; R must still find this one. */
void attribute_visible R_init_zudedup(DllInfo *dll)
{
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
