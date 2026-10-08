#include "zdd_hash.h"

void zdd_hex128(zuf_digest128 d, char out[ZDD_HEX128])
{
    static const char digits[] = "0123456789abcdef";
    for (int i = 0; i < 16; i++) {
        out[i] = digits[(d.high >> (60 - 4 * i)) & 0xf];
        out[16 + i] = digits[(d.low >> (60 - 4 * i)) & 0xf];
    }
    out[32] = '\0';
}
