#include "json_esc.h"

static const char table[256] = {
    ['"']  = '"',
    ['\\'] = '\\',
    ['/']  = '/',
    ['\b'] = 'b',
    ['\f'] = 'f',
    ['\n'] = 'n',
    ['\r'] = 'r',
    ['\t'] = 't',
};

size_t json_esc_nextra(const char *s, size_t ns)
{
    size_t r = 0;
    for (size_t i = 0; i < ns; ++i) {
        r += (table[(unsigned char) s[i]] != 0);
    }
    return r;
}

size_t json_esc(const char *s, size_t ns, char *out)
{
    char *out_end = out;
    for (size_t i = 0; i < ns; ++i) {
        char c = s[i];
        char esc = table[(unsigned char) c];
        if (esc == '\0') {
            *out_end++ = c;
        } else {
            *out_end++ = '\\';
            *out_end++ = esc;
        }
    }
    return out_end - out;
}
