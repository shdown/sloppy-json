#pragma once

#include "common.h"
#include "json_common.h"

// Skips until either a non-whitespace (as per JSON standard) symbol is found, or the end of the
// buffer is reached.
const char *json_skip_ws(const char *buf, const char *buf_end);

// Classifies the JSON object at {buf ... buf_end}. Returns:
//  * '[' if array;
//  * '{' if dict;
//  * '"' if string;
//  * '#' if number;
//  * '?' if boolean;
//  * '_' if null;
//  * '\0' if not a valid JSON object.
char json_classify(const char *buf, const char *buf_end);

// If '*e' is '{0}', writes the span of the first element into '*e' and returns 1.
// Otherwise, if '*e' spans an element of the array, writes the span of the next element into '*e'
// and returns 1.
// If there is no first/next element, returns 0.
// On error, returns -1.
int json_array_next(JsonSpan a, JsonSpan *e);

// If '*k'/'*v' are '{0}', writes the spans of the first key-value pair into '*k'/'*v' and returns
// 1.
// Otherwise, if '*k'/'*v' span a key-value pair, writes the spans of the next key-value pair into
// '*k'/'*v' and returns 1.
// If there is no first/next key-value pair, returns 0.
// On error, returns -1.
int json_dict_next(JsonSpan a, JsonSpan *k, JsonSpan *v);

// Iterates over key-value pairs of JSON dictionary at {buf ... buf_end}, and, whenever for some
// 0 <= i < nentries,
//     {current_key ... current_key_end}
// matches ("sloppy" match, without regard to JSON escapes)
//     {entries[i].key ... entries[i].key + entries[i].nkey}',
// writes 'entries[i].v_begin = current_value, entries[i].v_end = current_value_end'.
// Returns 0 on success, -1 on error.
int json_parse_dict_fields(const char *buf, const char *buf_end, JsonFieldEntry *entries, int nentries);

// Iterates over key-value pairs of JSON dictionary at {buf ... buf_end}, and, whenever for some
// 0 <= i < nentries,
//     {current_key ... current_key_end}
// matches (exact match)
//     {entries[i].key ... entries[i].key + entries[i].nkey}',
// writes 'entries[i].v_begin = current_value, entries[i].v_end = current_value_end'.
// Returns 0 on success, -1 on error.
int json_parse_dict_fields_exact(const char *buf, const char *buf_end, JsonFieldEntry *entries, int nentries);

// Fills 'entries' with 'nentries' (or less, if the total number of elements is less than that)
// first elements of the JSON array at {buf ... buf_end}.
// Returns 0 on success, -1 on error.
int json_parse_array_elems(const char *buf, const char *buf_end, JsonElemEntry *entries, int nentries);

// Fills 'entries' with corresponding elements of the JSON array; namely, it assigns
//   'entries[j].v_begin' and 'entries[j].v_end' to the span of the element with index of
//     'entries[j].i',
// where 0 <= j < nentries.
// Entries must be sorted by the 'i' field in non-decreasing order.
// Returns 0 on success, -1 on error.
int json_parse_array_elems_sparse(const char *buf, const char *buf_end, JsonSparseElemEntry *entries, int nentries);

// Checks if {buf ... buf_end} is a JSON string equal to the C string 's'.
// This is "sloppy" comparison, which does not account for JSON escapes.
bool json_streq(const char *buf, const char *buf_end, const char *s);

// Unescapes the JSON string {j ... j_end} into 'out'.
// Returns the number of bytes written.
ssize_t json_unesc(const char *j, const char *j_end, char *out);

// Checks if {buf ... buf_end} is a JSON string equal to the C string 's'.
// This is "exact" comparison.
int json_streq_exact(const char *j, const char *j_end, const char *s);

// Checks if {buf ... buf_end} is a JSON string equal to {buf ... buf_end}.
// This is "exact" comparison.
int json_streq_exact_b(const char *j, const char *j_end, const char *buf, const char *buf_end);

in_header bool json_span_streq(JsonSpan x, const char *s)
{
    return json_streq(x.begin, x.end, s);
}

in_header char json_span_classify(JsonSpan x)
{
    return json_classify(x.begin, x.end);
}

in_header int json_span_streq_exact(JsonSpan x, const char *s)
{
    return json_streq_exact(x.begin, x.end, s);
}

in_header int json_span_streq_exact_b(JsonSpan x, const char *buf, const char *buf_end)
{
    return json_streq_exact_b(x.begin, x.end, buf, buf_end);
}
