#pragma once

#include "common.h"

enum {
    JSON_CLASS_BAD,
    JSON_CLASS_ARRAY,
    JSON_CLASS_DICT,
    JSON_CLASS_STR,
    JSON_CLASS_NUM,
    JSON_CLASS_BOOL,
    JSON_CLASS_NULL,
};

typedef struct {
    const char *begin;
    const char *end;
} JsonSpan;

typedef struct {
    const char *key;
    size_t nkey;
    const char *v_begin;
    const char *v_end;
} JsonFieldEntry;

#define JSON_FENTRY(K) {(K), strlen(K), NULL, NULL}

typedef struct {
    const char *v_begin;
    const char *v_end;
} JsonElemEntry;

typedef struct {
    size_t i;
    const char *v_begin;
    const char *v_end;
} JsonSparseElemEntry;

in_header int json_parse_bool(const char *buf, const char *buf_end)
{
    size_t n = buf_end - buf;
    if (n == 4 && memcmp("true", buf, 4) == 0)
        return 1;
    if (n == 5 && memcmp("false", buf, 5) == 0)
        return 0;
    return -1;
}

in_header bool json_is_null(const char *buf, const char *buf_end)
{
    if (buf_end - buf != 4)
        return false;
    return memcmp("null", buf, 4) == 0;
}

in_header JsonSpan json_span_from_fentry(JsonFieldEntry e)
{
    return (JsonSpan) {e.v_begin, e.v_end};
}

in_header JsonSpan json_span_from_eentry(JsonElemEntry e)
{
    return (JsonSpan) {e.v_begin, e.v_end};
}

in_header JsonSpan json_span_from_seentry(JsonSparseElemEntry e)
{
    return (JsonSpan) {e.v_begin, e.v_end};
}

in_header bool json_span_is_null(JsonSpan x)
{
    return json_is_null(x.begin, x.end);
}

in_header int json_span_parse_bool(JsonSpan x)
{
    return json_parse_bool(x.begin, x.end);
}

in_header bool json_span_empty(JsonSpan x)
{
    return x.begin == x.end;
}
