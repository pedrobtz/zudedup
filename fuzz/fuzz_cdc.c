/* The chunker's block-independence invariant under libFuzzer (design
 * sections 6.3 and 15). The first input byte picks the parameters, the
 * second seeds the split points; the rest is chunked twice, whole and in
 * blocks of pseudo-random length, and the two must give the same cuts and
 * leave the same chunk in progress. Every chunk must also respect min and
 * max. Any difference traps.
 *
 * Built with -DZDD_FUZZ_CANARY, the split run forgets the hash at every
 * block boundary, a real block-independence bug: tools/run-fuzz requires
 * that build to crash before it trusts this one (a gate is trusted once it
 * has been seen to fail). */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "zdd_check.h"

static const uint64_t params[][3] = {
    {64, 256, 1024},
    {2048, 8192, 65536},
    {64, 1024, 1024},
    {1024, 1024, 1024},
    {100, 512, 4096},
    {700, 1024, 1500},
};
#define NPARAMS (sizeof params / sizeof params[0])

static void check(int ok)
{
    if (!ok)
        __builtin_trap();
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 2)
        return 0;
    const uint64_t *p = params[data[0] % NPARAMS];
    uint32_t rng = 0x9e3779b9u ^ data[1];
    data += 2;
    size -= 2;

    zdd_cdc whole, split;
    check(zdd_cdc_init(&whole, p[0], p[1], p[2]) == ZDD_OK);
    check(zdd_cdc_init(&split, p[0], p[1], p[2]) == ZDD_OK);

    size_t cap = zdd_cdc_max_cuts(&whole, size);
    size_t *a = malloc(cap * sizeof *a);
    size_t *b = malloc((size + 1) * sizeof *b);
    size_t *tmp = malloc((size + 1) * sizeof *tmp);
    check(a && b && tmp);

    size_t na = zdd_cdc_feed(&whole, data, size, a);

    size_t nb = 0, done = 0;
    while (done < size) {
        rng ^= rng << 13;
        rng ^= rng >> 17;
        rng ^= rng << 5;
        size_t len = 1 + rng % 1500;
        if (len > size - done)
            len = size - done;
        size_t k = zdd_cdc_feed(&split, data + done, len, tmp);
        check(k <= zdd_cdc_max_cuts(&split, len));
        for (size_t i = 0; i < k; i++)
            b[nb++] = done + tmp[i];
        done += len;
#ifdef ZDD_FUZZ_CANARY
        split.h = 0;
#endif
    }

    check(na == nb);
    check(memcmp(a, b, na * sizeof *a) == 0);
    check(whole.n == split.n && whole.h == split.h);

    /* Every chunk is at most max, and every chunk but the last is longer
       than min, unless min == max. */
    size_t prev = 0;
    for (size_t i = 0; i < na; i++) {
        size_t len = a[i] - prev;
        check(len >= 1 && len <= p[2]);
        check(len > p[0] || len == p[2]);
        prev = a[i];
    }
    check(size - prev == whole.n && whole.n <= p[2]);

    free(a);
    free(b);
    free(tmp);
    return 0;
}
