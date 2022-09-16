#pragma once

#include "common.h"
#include "json_common.h"
#include "preempt.h"

const char *PREEMPT_json_skip_ws(const char *buf, const char *buf_end, PreemptDevice *p);

char PREEMPT_json_classify(const char *buf, const char *buf_end, PreemptDevice *p);

int PREEMPT_json_array_next(JsonSpan a, JsonSpan *e, PreemptDevice *p);

int PREEMPT_json_dict_next(JsonSpan a, JsonSpan *k, JsonSpan *v, PreemptDevice *p);

int PREEMPT_json_parse_dict_fields(const char *buf, const char *buf_end, JsonFieldEntry *entries, int nentries, PreemptDevice *p);

int PREEMPT_json_parse_dict_fields_exact(const char *buf, const char *buf_end, JsonFieldEntry *entries, int nentries, PreemptDevice *p);

int PREEMPT_json_parse_array_elems(const char *buf, const char *buf_end, JsonElemEntry *entries, int nentries, PreemptDevice *p);

int PREEMPT_json_parse_array_elems_sparse(const char *buf, const char *buf_end, JsonSparseElemEntry *entries, int nentries, PreemptDevice *p);

bool PREEMPT_json_streq(const char *buf, const char *buf_end, const char *s, PreemptDevice *p);

ssize_t PREEMPT_json_unesc(const char *j, const char *j_end, char *out, PreemptDevice *p);

int PREEMPT_json_streq_exact(const char *j, const char *j_end, const char *s, PreemptDevice *p);

int PREEMPT_json_streq_exact_b(const char *j, const char *j_end, const char *buf, const char *buf_end, PreemptDevice *p);

in_header bool PREEMPT_json_span_streq(JsonSpan x, const char *s, PreemptDevice *p)
{
    return PREEMPT_json_streq(x.begin, x.end, s, p);
}

in_header char PREEMPT_json_span_classify(JsonSpan x, PreemptDevice *p)
{
    return PREEMPT_json_classify(x.begin, x.end, p);
}

in_header int PREEMPT_json_span_streq_exact(JsonSpan x, const char *s, PreemptDevice *p)
{
    return PREEMPT_json_streq_exact(x.begin, x.end, s, p);
}

in_header int PREEMPT_json_span_streq_exact_b(JsonSpan x, const char *buf, const char *buf_end, PreemptDevice *p)
{
    return PREEMPT_json_streq_exact_b(x.begin, x.end, buf, buf_end, p);
}
