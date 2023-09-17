#if JSON_PREEMPTIBLE
# include "preempt.h"
# define PREEMPT_DECLF(QualAndRettype_, Name_, ...)     QualAndRettype_ PREEMPT_ ## Name_(__VA_ARGS__, __attribute__((unused)) PreemptDevice *__preempt)
# define PREEMPT_DECLF_V(QualAndRettype_, Name_, ...)   QualAndRettype_ PREEMPT_ ## Name_(__attribute__((unused)) PreemptDevice *__preempt)
# define PREEMPT_INCR(X_)                               (preempt_maybe_yield(__preempt), ++(X_))
# define PREEMPT_DECR(X_)                               (preempt_maybe_yield(__preempt), --(X_))
# define PREEMPT_CALL(F_, ...)                          PREEMPT_ ## F_(__VA_ARGS__, __preempt)
# define PREEMPT_CALL_V(F_, ...)                        PREEMPT_ ## F_(__preempt)
#else
# define PREEMPT_DECLF(QualAndRettype_, Name_, ...)     QualAndRettype_ Name_(__VA_ARGS__)
# define PREEMPT_DECLF_V(QualAndRettype_, Name_, ...)   QualAndRettype_ Name_(void)
# define PREEMPT_INCR(X_)                               (++(X_))
# define PREEMPT_DECR(X_)                               (--(X_))
# define PREEMPT_CALL(F_, ...)                          F_(__VA_ARGS__)
# define PREEMPT_CALL_V(F_, ...)                        F_()
#endif

enum {
    FLAG_WHITESPACE = 1 << 0,
    FLAG_TOKEN      = 1 << 1,
    CLASS_OFFSET    = 2,
};

#define MAKE_CLASS(C_) ((C_) << CLASS_OFFSET)

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Woverride-init"
static const uint8_t MAIN_TABLE[256] = {
    [' ']           = FLAG_WHITESPACE,
    ['\t']          = FLAG_WHITESPACE,
    ['\n']          = FLAG_WHITESPACE,
    ['\r']          = FLAG_WHITESPACE,

    ['0' ... '9']   = FLAG_TOKEN | MAKE_CLASS(JSON_CLASS_NUM),
    ['a' ... 'z']   = FLAG_TOKEN,
    ['.']           = FLAG_TOKEN,
    ['-']           = FLAG_TOKEN | MAKE_CLASS(JSON_CLASS_NUM),
    ['+']           = FLAG_TOKEN,
    ['E']           = FLAG_TOKEN,

    ['t']           = FLAG_TOKEN | MAKE_CLASS(JSON_CLASS_BOOL),
    ['f']           = FLAG_TOKEN | MAKE_CLASS(JSON_CLASS_BOOL),
    ['n']           = FLAG_TOKEN | MAKE_CLASS(JSON_CLASS_NULL),

    ['"']           = MAKE_CLASS(JSON_CLASS_STR),
    ['[']           = MAKE_CLASS(JSON_CLASS_ARRAY),
    ['{']           = MAKE_CLASS(JSON_CLASS_DICT),
};
#pragma GCC diagnostic pop

PREEMPT_DECLF(
    static inline const char *,
    skip_whitespace,
        const char *s,
        const char *s_end)
{
    while (s != s_end && (MAIN_TABLE[(unsigned char) *s] & FLAG_WHITESPACE)) {
        PREEMPT_INCR(s);
    }
    return s;
}

PREEMPT_DECLF(
    const char *,
    json_skip_ws,
        const char *buf,
        const char *buf_end)
{
    return PREEMPT_CALL(skip_whitespace, buf, buf_end);
}

PREEMPT_DECLF(
    uint8_t,
    json_classify,
        const char *buf,
        const char *buf_end)
{
    buf = PREEMPT_CALL(skip_whitespace, buf, buf_end);
    if (unlikely(buf == buf_end))
        return JSON_CLASS_BAD;
    return MAIN_TABLE[(unsigned char) *buf] >> CLASS_OFFSET;
}

PREEMPT_DECLF(
    static const char *,
    skip_str_unchecked,
        const char *buf,
        const char *buf_end)
{
    PREEMPT_INCR(buf);

    for (;;) {

#if JSON_PREEMPTIBLE
        for (;;) {
            if (unlikely(buf == buf_end))
                return NULL;
            if (*buf == '"')
                break;

            PREEMPT_INCR(buf);
        }
#else
        if (unlikely(buf == buf_end))
            return NULL;
        buf = memchr(buf, '"', buf_end - buf);
        if (unlikely(!buf))
            return NULL;
#endif

        ssize_t offset = -1;
        while (buf[offset] == '\\') {
            PREEMPT_DECR(offset);
        }

        PREEMPT_INCR(buf);
        if (likely(offset & 1)) {
            // The number of backslashes before '"' is even, so it is not escaped.
            return buf;
        }
    }
}

PREEMPT_DECLF(
    static inline const char *,
    skip_str,
        const char *buf,
        const char *buf_end)
{
    if (unlikely(buf == buf_end))
        return NULL;
    if (unlikely(*buf != '"'))
        return NULL;
    return PREEMPT_CALL(skip_str_unchecked, buf, buf_end);
}

PREEMPT_DECLF(
    static const char *,
    skip_obj,
        const char *buf,
        const char *buf_end)
{
    if (unlikely(buf == buf_end))
        return NULL;

    char x = *buf;
    if ((x & 0xDF) == 0x5B) {
        // x is either '[' or '{'
        static const int8_t table[256] = {
            ['['] = 1,
            ['{'] = 1,
            [']'] = -1,
            ['}'] = -1,
        };
        size_t level = 1;
        PREEMPT_INCR(buf);
        for (;;) {
            if (unlikely(buf == buf_end))
                return NULL;
            char y = *buf;
            if (y == '"') {
                buf = PREEMPT_CALL(skip_str_unchecked, buf, buf_end);
                if (unlikely(!buf))
                    return NULL;
            } else {
                level += table[(unsigned char) y];
                if (level == 0) {
                    return buf + 1;
                }
                PREEMPT_INCR(buf);
            }
        }

    } else if (x == '"') {
        return PREEMPT_CALL(skip_str_unchecked, buf, buf_end);

    } else {
        // Skip either a number or one of the following tokens: "true", "false", "null".
        do {
            PREEMPT_INCR(buf);
        } while (buf != buf_end && (MAIN_TABLE[(unsigned char) *buf] & FLAG_TOKEN));
        return buf;
    }
}

PREEMPT_DECLF(
    int,
    json_array_next,
        JsonSpan a,
        JsonSpan *e)
{
    if (e->end == NULL) {
        a.begin = PREEMPT_CALL(skip_whitespace, a.begin, a.end);
        if (unlikely(a.begin == a.end)) {
            return -1;
        }
        if (unlikely(a.begin[0] != '[')) {
            return -1;
        }
        PREEMPT_INCR(a.begin);

        a.begin = PREEMPT_CALL(skip_whitespace, a.begin, a.end);
        if (unlikely(a.begin == a.end)) {
            return -1;
        }
        if (a.begin[0] == ']') {
            return 0;
        }

    } else {
        a.begin = e->end;

        a.begin = PREEMPT_CALL(skip_whitespace, a.begin, a.end);
        if (unlikely(a.begin == a.end)) {
            return -1;
        }
        char c = a.begin[0];
        if (c == ']') {
            return 0;
        }
        if (unlikely(c != ',')) {
            return -1;
        }
        PREEMPT_INCR(a.begin);
        a.begin = PREEMPT_CALL(skip_whitespace, a.begin, a.end);
    }

    e->begin = a.begin;
    a.begin = PREEMPT_CALL(skip_obj, a.begin, a.end);
    if (unlikely(!a.begin)) {
        return -1;
    }
    e->end = a.begin;
    return 1;
}

PREEMPT_DECLF(
    int,
    json_dict_next,
        JsonSpan d,
        JsonSpan *k,
        JsonSpan *v)
{
    if (v->end == NULL) {
        d.begin = PREEMPT_CALL(skip_whitespace, d.begin, d.end);
        if (unlikely(d.begin == d.end)) {
            return -1;
        }
        if (unlikely(d.begin[0] != '{')) {
            return -1;
        }
        PREEMPT_INCR(d.begin);

        d.begin = PREEMPT_CALL(skip_whitespace, d.begin, d.end);
        if (unlikely(d.begin == d.end)) {
            return -1;
        }
        if (d.begin[0] == '}') {
            return 0;
        }

    } else {
        d.begin = v->end;

        d.begin = PREEMPT_CALL(skip_whitespace, d.begin, d.end);
        if (unlikely(d.begin == d.end)) {
            return -1;
        }
        char c = d.begin[0];
        if (c == '}') {
            return 0;
        }
        if (unlikely(c != ',')) {
            return -1;
        }
        PREEMPT_INCR(d.begin);
        d.begin = PREEMPT_CALL(skip_whitespace, d.begin, d.end);
    }

    k->begin = d.begin;
    d.begin = PREEMPT_CALL(skip_str, d.begin, d.end);
    if (unlikely(!d.begin)) {
        return -1;
    }
    k->end = d.begin;

    d.begin = PREEMPT_CALL(skip_whitespace, d.begin, d.end);
    if (unlikely(d.begin == d.end)) {
        return -1;
    }
    if (unlikely(d.begin[0] != ':')) {
        return -1;
    }
    PREEMPT_INCR(d.begin);
    d.begin = PREEMPT_CALL(skip_whitespace, d.begin, d.end);
    if (unlikely(d.begin == d.end)) {
        return -1;
    }

    v->begin = d.begin;
    d.begin = PREEMPT_CALL(skip_obj, d.begin, d.end);
    if (unlikely(!d.begin)) {
        return -1;
    }
    v->end = d.begin;
    return 1;
}

PREEMPT_DECLF(
    static inline bool,
    span_eq,
        const char *a,
        const char *b,
        size_t n)
{
#if JSON_PREEMPTIBLE
    size_t i = 0;
    while (i < n) {
        if (a[i] != b[i]) {
            return false;
        }
        PREEMPT_INCR(i);
    }
    return true;
#else
    if (!n)
        return true;
    return memcmp(a, b, n) == 0;
#endif
}

PREEMPT_DECLF(
    int,
    json_parse_dict_fields,
        const char *buf,
        const char *buf_end,
        JsonFieldEntry *entries,
        int nentries)
{
    JsonSpan d = {buf, buf_end};
    JsonSpan k = {0};
    JsonSpan v = {0};
    JsonFieldEntry *entries_end = entries + nentries;
    int r;

    while ((r = PREEMPT_CALL(json_dict_next, d, &k, &v)) > 0) {
        for (JsonFieldEntry *e = entries; e != entries_end; ++e) {
            size_t nk = k.end - k.begin - 2;
            if (nk == e->nkey && PREEMPT_CALL(span_eq, e->key, k.begin + 1, nk)) {
                e->v_begin = v.begin;
                e->v_end = v.end;
                break;
            }
        }
    }
    return r;
}

PREEMPT_DECLF(
    int,
    json_parse_dict_fields_exact,
        const char *buf,
        const char *buf_end,
        JsonFieldEntry *entries,
        int nentries)
{
    JsonSpan d = {buf, buf_end};
    JsonSpan k = {0};
    JsonSpan v = {0};
    JsonFieldEntry *entries_end = entries + nentries;
    int r;

    while ((r = PREEMPT_CALL(json_dict_next, d, &k, &v)) > 0) {
        for (JsonFieldEntry *e = entries; e != entries_end; ++e) {
            int r2 = PREEMPT_CALL(json_streq_exact_b, k.begin, k.end, e->key, e->key + e->nkey);
            if (r2 > 0) {
                e->v_begin = v.begin;
                e->v_end = v.end;
                break;
            } else if (r2 < 0) {
                return -1;
            }
        }
    }
    return r;
}

PREEMPT_DECLF(
    int,
    json_parse_array_elems,
        const char *buf,
        const char *buf_end,
        JsonElemEntry *entries,
        int nentries)
{
    JsonSpan a = {buf, buf_end};
    JsonSpan v = {0};
    JsonElemEntry *entries_end = entries + nentries;
    int r;
    while ((r = PREEMPT_CALL(json_array_next, a, &v)) > 0) {
        if (entries == entries_end) {
            return 0;
        }
        *entries++ = (JsonElemEntry) {v.begin, v.end};
    }
    return r;
}

PREEMPT_DECLF(
    int,
    json_parse_array_elems_sparse,
        const char *buf,
        const char *buf_end,
        JsonSparseElemEntry *entries,
        int nentries)
{
    JsonSpan a = {buf, buf_end};
    JsonSpan v = {0};
    JsonSparseElemEntry *entries_end = entries + nentries;
    int r;
    size_t i = 0;
    while ((r = PREEMPT_CALL(json_array_next, a, &v)) > 0) {
        for (;;) {
            if (entries == entries_end) {
                return 0;
            }
            if (entries->i == i) {
                entries->v_begin = v.begin;
                entries->v_end = v.end;
                ++entries;
            } else {
                break;
            }
        }
        ++i;
    }
    return r;
}

PREEMPT_DECLF(
    bool,
    json_streq,
        const char *buf,
        const char *buf_end,
        const char *s)
{
    size_t nbuf = buf_end - buf;
    if (nbuf < 2)
        return false;
    if (buf[0] != '"')
        return false;

    size_t n = nbuf - 2;
    size_t i = 0;
    while (i < n) {
        char c = s[i];
        if (c == '\0')
            return false;
        if (buf[i + 1] != c)
            return false;
        PREEMPT_INCR(i);
    }
    return buf_end[-1] == '"' && s[n] == '\0';
}

PREEMPT_DECLF(
        static inline const char *,
        find_next_escape,
            const char *buf, const char *buf_end)
{
#if JSON_PREEMPTIBLE
    while (buf != buf_end) {
        if (*buf == '\\') {
            break;
        }
        PREEMPT_INCR(buf);
    }
    return buf;
#else
    if (buf != buf_end)
        buf = memchr(buf, '\\', buf_end - buf);
    return buf ? buf : buf_end;
#endif
}

static inline int unesc_single(char c)
{
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Woverride-init"
    static const int8_t table[256] = {
        [0 ... 255] = -1,
        ['"'] = '"',
        ['\\'] = '\\',
        ['/'] = '/',
        ['b'] = '\b',
        ['f'] = '\f',
        ['n'] = '\n',
        ['r'] = '\r',
        ['t'] = '\t',
    };
#pragma GCC diagnostic pop
    return table[(unsigned char) c];
}

static int parse_hex_escape(const char *s)
{
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Woverride-init"
    static const int8_t table[256] = {
        [0 ... 255] = -1,
        ['0'] = 0,
        ['1'] = 1,
        ['2'] = 2,
        ['3'] = 3,
        ['4'] = 4,
        ['5'] = 5,
        ['6'] = 6,
        ['7'] = 7,
        ['8'] = 8,
        ['9'] = 9,
        ['a'] = 10, ['A'] = 10,
        ['b'] = 11, ['B'] = 11,
        ['c'] = 12, ['C'] = 12,
        ['d'] = 13, ['D'] = 13,
        ['e'] = 14, ['E'] = 14,
        ['f'] = 15, ['F'] = 15,
    };
#pragma GCC diagnostic pop

#define PARSE_DIGIT(X) table[(unsigned char) (X)]

    uint16_t res;
    int8_t digit;

    if (unlikely((digit = PARSE_DIGIT(s[0])) < 0))
        goto bad;
    res = digit;

    res <<= 4;
    if (unlikely((digit = PARSE_DIGIT(s[1])) < 0))
        goto bad;
    res |= digit;

    res <<= 4;
    if (unlikely((digit = PARSE_DIGIT(s[2])) < 0))
        goto bad;
    res |= digit;

    res <<= 4;
    if (unlikely((digit = PARSE_DIGIT(s[3])) < 0))
        goto bad;
    res |= digit;

#undef PARSE_DIGIT

    return res;
bad:
    return -1;
}

#define UNESC_TEMPLATE() \
    if (unlikely(j == j_end || j[0] != '"')) { \
        UNESC_RETURN_BAD(1); \
    } \
    PREEMPT_DECR(j_end); \
    PREEMPT_INCR(j); \
    for (;;) { \
        const char *next_esc = PREEMPT_CALL(find_next_escape, j, j_end); \
        UNESC_PRODUCE_CHUNK(j, next_esc); \
        if (next_esc == j_end) { \
            break; \
        } \
        PREEMPT_INCR(next_esc); \
        if (unlikely(next_esc == j_end)) { \
            UNESC_RETURN_BAD(2); \
        } \
        char c = *next_esc; \
        if (c == 'u') { \
            PREEMPT_INCR(next_esc); \
            if (unlikely(j_end - next_esc < 4)) { \
                return -1; \
            } \
            int res = parse_hex_escape(next_esc); \
            if (unlikely(res < 0)) { \
                UNESC_RETURN_BAD(3); \
            } \
            if (res < 128) { \
                UNESC_PRODUCE_1(res); \
            } else if (res < 2048) { \
                UNESC_PRODUCE_1(0xC0 | (res >> 6)); \
                UNESC_PRODUCE_1(0x80 | (res & 63)); \
            } else { \
                UNESC_PRODUCE_1(0xE0 | (res >> 12)); \
                UNESC_PRODUCE_1(0x80 | ((res >> 6) & 63)); \
                UNESC_PRODUCE_1(0x80 | (res & 63)); \
            } \
            j = next_esc + 4; \
        } else { \
            int res = unesc_single(c); \
            if (unlikely(res < 0)) { \
                UNESC_RETURN_BAD(4); \
            } \
            UNESC_PRODUCE_1(res); \
            j = next_esc + 1; \
        } \
    }

PREEMPT_DECLF(
    static inline void,
    my_memcpy,
        char *dst,
        const char *src,
        size_t n)
{
    size_t i = 0;
    while (i < n) {
        dst[i] = src[i];
        PREEMPT_INCR(i);
    }
}

PREEMPT_DECLF(
    ssize_t,
    json_unesc,
        const char *j,
        const char *j_end,
        char *out)
{
    char *cur = out;

#define UNESC_PRODUCE_CHUNK(Src_, SrcEnd_) \
    do { \
        const char *src_ = (Src_); \
        size_t n_ = (SrcEnd_) - src_; \
        PREEMPT_CALL(my_memcpy, cur, src_, n_); \
        cur += n_; \
    } while (0)
#define UNESC_PRODUCE_1(C_) (*cur++ = (C_))
#define UNESC_RETURN_BAD(N_) return -1

    UNESC_TEMPLATE()

#undef UNESC_PRODUCE_CHUNK
#undef UNESC_PRODUCE_1
#undef UNESC_RETURN_BAD

    return cur - out;
}

PREEMPT_DECLF(
    static inline bool,
    my_memeq_special,
        const char *p,
        const char *q,
        size_t n)
{
    size_t i = 0;
    while (i < n) {
        char c = p[i];
        if (c == '\0' || c != q[i]) {
            return false;
        }
        PREEMPT_INCR(i);
    }
    return true;
}

PREEMPT_DECLF(
    int,
    json_streq_exact,
        const char *j,
        const char *j_end,
        const char *s)
{
#define UNESC_PRODUCE_CHUNK(Src_, SrcEnd_) \
    do { \
        const char *src_ = (Src_); \
        size_t n_ = (SrcEnd_) - src_; \
        if (!PREEMPT_CALL(my_memeq_special, s, src_, n_)) { \
            return 0; \
        } \
        s += n_; \
    } while (0)
#define UNESC_PRODUCE_1(C_) \
    do { \
        char x_ = *s++; \
        if (unlikely(x_ == '\0' || x_ != (char) (C_))) { \
            return 0; \
        } \
    } while (0)
#define UNESC_RETURN_BAD(N_) return -1

    UNESC_TEMPLATE()

#undef UNESC_PRODUCE_CHUNK
#undef UNESC_PRODUCE_1
#undef UNESC_RETURN_BAD

    return *s == '\0';
}

PREEMPT_DECLF(
    int,
    json_streq_exact_b,
        const char *j,
        const char *j_end,
        const char *buf,
        const char *buf_end)
{
#define UNESC_PRODUCE_CHUNK(Src_, SrcEnd_) \
    do { \
        const char *src_ = (Src_); \
        size_t nx_ = (SrcEnd_) - src_; \
        size_t nleft_ = buf_end - buf; \
        if (nleft_ < nx_) { \
            return 0; \
        } \
        if (!PREEMPT_CALL(span_eq, src_, buf, nx_)) { \
            return 0; \
        } \
        buf += nx_; \
    } while (0)

#define UNESC_PRODUCE_1(C_) \
    do { \
        if (buf == buf_end || *buf != (char) (C_)) { \
            return 0; \
        } \
        ++buf; \
    } while (0)

#define UNESC_RETURN_BAD(N_) return -1

    UNESC_TEMPLATE()

#undef UNESC_PRODUCE_CHUNK
#undef UNESC_PRODUCE_1
#undef UNESC_RETURN_BAD

    return buf == buf_end;
}
