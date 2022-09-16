#include "json_gen_num.h"
#include <stddef.h>

static inline size_t getndigits(uint64_t x)
{
#if 0
    if (x < 10) return 1;
    if (x < 100) return 2;
    if (x < 1000) return 3;
    if (x < 10000) return 4;
    if (x < 100000) return 5;
    if (x < 1000000) return 6;
    if (x < 10000000) return 7;
    if (x < 100000000) return 8;
    if (x < 1000000000) return 9;
    if (x < 10000000000) return 10;
    if (x < 100000000000) return 11;
    if (x < 1000000000000) return 12;
    if (x < 10000000000000) return 13;
    if (x < 100000000000000) return 14;
    if (x < 1000000000000000) return 15;
    if (x < 10000000000000000) return 16;
    if (x < 100000000000000000) return 17;
    if (x < 1000000000000000000) return 18;
    if (x < 10000000000000000000u) return 19;
    return 20;
#else
    size_t result = 0;
    for (;;) {
        if (x < 10) return result + 1;
        if (x < 100) return result + 2;
        if (x < 1000) return result + 3;
        if (x < 10000) return result + 4;
        x /= 10000;
        result += 4;
    }
#endif
}

static int gen0(char *out, uint8_t scale)
{
    if (scale) {
        out[0] = '0';
        out[1] = '.';
        size_t s = scale;
        for (size_t i = 0; i < s; ++i) {
            // Prevent gcc from emitting 'rep stos': rep stos/movs has significant startup overhead.
            asm volatile ("" ::: "memory");

            out[2 + i] = '0';
        }
        return s + 2;
    } else {
        *out = '0';
        return 1;
    }
}

int json_gen_unum(char *out, uint64_t x, uint8_t scale)
{
    if (x == 0) {
        return gen0(out, scale);
    }

    // Calculate the number of characters to be written without '.': max(getndigits(x), scale+1).
    size_t r = getndigits(x);
    if (r <= scale)
        r = scale + 1;

    char *end;
    if (scale) {
        // We're going to write '.', so increment 'r' by one.
        ++r;
        end = out + r;
        char *boundary = end - scale;
        do {
            --end;
            *end = '0' + (x % 10);
            x /= 10;
        } while (end != boundary);
        --end;
        *end = '.';
    } else {
        end = out + r;
    }

    char *boundary = out + 1;
    while (end != boundary) {
        --end;
        *end = '0' + (x % 10);
        x /= 10;
    }
    *out = '0' + x;

    return r;
}

int json_gen_inum(char *out, int64_t x, uint8_t scale)
{
    int offset = 0;
    uint64_t y = x;
    if (x < 0) {
        *out++ = '-';
        offset = 1;
        y = -y;
    }
    return offset + json_gen_unum(out, y, scale);
}
