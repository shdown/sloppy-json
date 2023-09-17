#pragma once

#include "common.h"
#include <ucontext.h>

// A fiber is a cooperative multitasking process.
//
// To start a fiber or continue its execution, you need to call 'fiber_kick().'
// The code of the fiber will then start executing immediately after and until
// either the fiber yields or returns from its main function. In both cases,
// the control returns 'fiber_kick()'.
//
// It is undefined behaviour to kick a fiber that is already "dead" (has
// returned from its main function). Therefore, you need to check the state
// of the fiber via some third-party mechanism after you call 'fiber_kick()'
// to maintain an up-to-date information on whether or not it is dead.

#ifndef FIBER_STACKSZ
# define FIBER_STACKSZ (4 * 1024 * 1024)
#endif

static __attribute__((unused, noinline, noreturn))
void fiber_handle_error(const char *expr)
{
    // We try to use here as few stack space as possible.
#define WRITE_S(S_) \
    do { \
        for (const char *p_ = (S_); *p_; ++p_) { \
            while (write(2, p_, 1) == 0) {} \
        } \
    } while (0)

    WRITE_S("FATAL: FIBER_CHECK(");
    WRITE_S(expr);
    WRITE_S(") failed!\n");

#undef WRITE_S
    abort();
}

#define FIBER_CHECK(Expr_) \
    do { \
        if (unlikely((Expr_) < 0)) { \
            fiber_handle_error(#Expr_); \
        } \
    } while (0)

// POSIX context stuff only allows us to smuggle a number of ints, not pointers.
// As on x86-64, sizeof(void *) > sizeof(int), we need to convert int pairs <=> pointers.
#define FIBER_PARAM_LIST \
    int __a0, int __a1, \
    int __b0, int __b1

#define FIBER_UNPACK_II_INTO_P(X0_, X1_) \
    ({ \
        uint32_t __u0 = (X0_); \
        uint32_t __u1 = (X1_); \
        (void *) (uintptr_t) ((((uint64_t) __u1) << 32) | __u0); \
    })

// We pass two pointers to the fiber, the "userdata" (whatever provided by the user) and
// a pointer to 'FiberParams' to be able to yield.
// Hint: store the "is_done" flag in the buffer pointed to by "userdata".
#define FIBER_GET_USERDATA() FIBER_UNPACK_II_INTO_P(__a0, __a1)

#define FIBER_GET_PARAMS() ((FiberParams) {FIBER_UNPACK_II_INTO_P(__b0, __b1)})

// We use this '>> 31 >> 1' thing to avoid UB on 32-bit platforms.
#define FIBER_PACK_P_INTO_II(P_) \
    ((int) (uintptr_t) (P_)), \
    ((int) (((uintptr_t) (P_)) >> 31 >> 1))

typedef struct {
    ucontext_t *ctx_pair;
} FiberParams;

typedef struct {
    char stack[FIBER_STACKSZ];
    ucontext_t ctx_pair[2];
} Fiber;

in_header void fiber_create(Fiber *fib, void (*f)(FIBER_PARAM_LIST), void *f_arg)
{
    FIBER_CHECK(getcontext(&fib->ctx_pair[0]));
    fib->ctx_pair[0].uc_link = &fib->ctx_pair[1];
    fib->ctx_pair[0].uc_stack.ss_sp = fib->stack;
    fib->ctx_pair[0].uc_stack.ss_size = FIBER_STACKSZ;
    ucontext_t *arg2 = fib->ctx_pair;
    makecontext(
        &fib->ctx_pair[0],
        (void (*)(void)) f,
        4, FIBER_PACK_P_INTO_II(f_arg), FIBER_PACK_P_INTO_II(arg2));
}

in_header void fiber_kick(Fiber *fib)
{
    FIBER_CHECK(swapcontext(&fib->ctx_pair[1], &fib->ctx_pair[0]));
}

in_header void fiber_yield(FiberParams *fib_par)
{
    FIBER_CHECK(swapcontext(&fib_par->ctx_pair[0], &fib_par->ctx_pair[1]));
}
