#include "json_parse_num.h"

static inline const char *span_rstrip_n(
        const char *span_begin,
        const char *span_dot,
        const char *span_end,
        size_t n)
{
    for (; span_end != span_begin && n; --span_end) {
        if (span_end - 1 != span_dot) {
            --n;
        }
    }
    return span_end;
}

int64_t json_parse_num(const char *buf, const char *buf_end, uint8_t scale)
{
    bool negate = false;
    bool negate_e = false;
    int16_t e = 0;

    if (unlikely(buf == buf_end)) {
        goto error;
    }
    if (*buf == '-') {
        negate = true;
        ++buf;

        if (unlikely(buf == buf_end)) {
            goto error;
        }
    }

    const char *span_begin = buf;
    const char *span_end = buf;
    const char *span_dot = NULL;

    for (;;) {
        char c = *span_end;

        uint16_t wraparoo = ((uint16_t) (unsigned char) c) - '0';
        if (wraparoo < 10) {
            // do nothing
        } else if (c == '.') {
            if (unlikely(span_dot != NULL)) {
                goto error;
            }
            span_dot = span_end;
        } else if (c == 'e' || c == 'E') {
            goto exp_part;
        } else {
            goto error;
        }
        ++span_end;
        if (span_end == buf_end) {
            goto done;
        }
    }

exp_part:
    (void) 0;
    const char *p = span_end + 1;
    if (unlikely(p == buf_end)) {
        goto error;
    }
    if (*p == '-') {
        negate_e = true;
        ++p;
    } else if (*p == '+') {
        ++p;
    }
    if (unlikely(p == buf_end)) {
        goto error;
    }
    for (;;) {
        char c = *p;
        uint16_t wraparoo = ((uint16_t) (unsigned char) c) - '0';
        if (likely(wraparoo < 10)) {
            if (unlikely(__builtin_mul_overflow(e, 10, &e)))
                goto error;
            if (unlikely(__builtin_add_overflow(e, (int16_t) wraparoo, &e)))
                goto error;
        } else {
            goto error;
        }
        ++p;
        if (p == buf_end) {
            goto done;
        }
    }

done:
    if (negate_e)
        e = -e;

    int32_t s = e + scale;
    if (span_dot) {
        s -= (span_end - span_dot - 1);
    }

    if (s < 0) {
        span_end = span_rstrip_n(span_begin, span_dot, span_end, -s);
    }

    int64_t r = 0;
    for (const char *q = span_begin; q != span_end; ++q) {
        char c = *q;
        if (c == '.')
            continue;
        if (unlikely(__builtin_mul_overflow(r, 10, &r)))
            goto error;
        if (unlikely(__builtin_add_overflow(r, c - '0', &r)))
            goto error;
    }
    if (r != 0) {
        for (; s > 0; --s) {
            if (unlikely(__builtin_mul_overflow(r, 10, &r)))
                goto error;
        }
        if (negate) {
            r = -r;
        }
    }
    return r;

error:
    return INT64_MIN;
}
