/* The chunker (design section 6): FastCDC's gear hash with normalised
 * chunking, under the boundary rule recorded in zdd_gear.h. R-free; see
 * zdd_check.h. */
#include "zdd_check.h"
#include "zdd_gear.h"

static int is_pow2(uint64_t x)
{
    return x != 0 && (x & (x - 1)) == 0;
}

static unsigned log2_u64(uint64_t x)
{
    unsigned b = 0;
    while (x > 1) {
        x >>= 1;
        b++;
    }
    return b;
}

zdd_status zdd_cdc_init(zdd_cdc *c, uint64_t min, uint64_t avg, uint64_t max)
{
    if (min < ZDD_MIN_LO || min > ZDD_MIN_HI || avg < ZDD_AVG_LO ||
        avg > ZDD_AVG_HI || max < ZDD_MAX_LO || max > ZDD_MAX_HI ||
        !is_pow2(avg) || min > avg || avg > max)
        return ZDD_ERR_PARAMS;

    unsigned bits = log2_u64(avg);
    /* normal = avg - (min + ceil(min / 2)), floored at 0 and capped at max:
       fastcdc 1.7.0's center_size(). */
    uint64_t off = min + (min + 1) / 2;
    if (off > avg)
        off = avg;
    uint64_t normal = avg - off;
    if (normal > max)
        normal = max;

    c->h = 0;
    c->n = 0;
    c->min = min;
    c->max = max;
    c->normal = normal;
    c->mask_s = (UINT64_C(1) << (bits + 1)) - 1;
    c->mask_l = (UINT64_C(1) << (bits - 1)) - 1;
    return ZDD_OK;
}

size_t zdd_cdc_max_cuts(const zdd_cdc *c, size_t n)
{
    uint64_t shortest = c->min + 1 < c->max ? c->min + 1 : c->max;
    return (size_t) (n / shortest) + 1;
}

size_t zdd_cdc_feed(zdd_cdc *c, const uint8_t *p, size_t n, size_t *cuts)
{
    uint64_t h = c->h, len = c->n;
    const uint64_t min = c->min, max = c->max, normal = c->normal;
    const uint64_t mask_s = c->mask_s, mask_l = c->mask_l;
    size_t ncut = 0, i = 0;

    while (i < n) {
        if (len < min) {
            /* The first min bytes of a chunk are not hashed. */
            uint64_t skip = min - len;
            if (skip > n - i)
                skip = n - i;
            len += skip;
            i += (size_t) skip;
            if (len == max) {           /* min == max: every chunk is max */
                cuts[ncut++] = i;
                h = 0;
                len = 0;
            }
            continue;
        }
        h = (h >> 1) + zdd_gear[p[i]];
        len++;
        i++;
        if ((h & (len <= normal ? mask_s : mask_l)) == 0 || len == max) {
            cuts[ncut++] = i;
            h = 0;
            len = 0;
        }
    }
    c->h = h;
    c->n = len;
    return ncut;
}

const char *zdd_status_name(zdd_status s)
{
    switch (s) {
    case ZDD_OK:
        return "ZDD_OK";
    case ZDD_ERR_PARAMS:
        return "ZDD_ERR_PARAMS";
    case ZDD_ERR_STATE:
        return "ZDD_ERR_STATE";
    }
    return "ZDD_ERR_UNKNOWN";
}
