#pragma once

#include <stdint.h>

// Writes at most (max(scale, 20) + 2) bytes to out.
int json_gen_unum(char *out, uint64_t x, uint8_t scale);

// Writes at most (max(scale, 20) + 3) bytes to out.
int json_gen_inum(char *out, int64_t x, uint8_t scale);
