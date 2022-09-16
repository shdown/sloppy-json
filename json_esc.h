#pragma once

#include "common.h"

// Counts how many *extra* bytes (not counting 'ns') are needed to JSON-escape this buffer.
// 0 <= return value <= ns.
size_t json_esc_nextra(const char *s, size_t ns);

// Writes JSON-escaped {s ... s+ns} to 'out', returning the number of bytes written.
size_t json_esc(const char *s, size_t ns, char *out);
