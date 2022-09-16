#pragma once

#include "common.h"

// Returns 'INT64_MIN' on error.
int64_t json_parse_num(const char *buf, const char *buf_end, uint8_t scale);
