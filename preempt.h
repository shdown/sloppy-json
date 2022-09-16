#pragma once

#include "common.h"
#include "fiber.h"

typedef struct {
    uint32_t left;
    uint32_t allowance;
    FiberParams fib_par;
} PreemptDevice;

in_header PreemptDevice preempt_new(uint32_t allowance, FiberParams fib_par)
{
    return (PreemptDevice) {
        .left      = allowance,
        .allowance = allowance,
        .fib_par   = fib_par,
    };
}

in_header void preempt_maybe_yield(PreemptDevice *p)
{
    if (unlikely(!--p->left)) {
        p->left = p->allowance;
        fiber_yield(&p->fib_par);
    }
}

in_header void preempt_yield(PreemptDevice *p)
{
    p->left = p->allowance;
    fiber_yield(&p->fib_par);
}

in_header void preempt_maybe_yield_n(PreemptDevice *p, uint32_t n)
{
    if (unlikely(p->left <= n)) {
        p->left = p->allowance;
        fiber_yield(&p->fib_par);
    } else {
        p->left -= n;
    }
}
