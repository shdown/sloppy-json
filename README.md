sloppy-json is a span-oriented C JSON parser with a DSL to sweeten the process of parsing.

Overview
===
The `dsl` Python script generates C source from a `.dsl` file.
The `.dsl` file should contain a regular C source interspersed with DSL *gestures*, which are lines starting with `|`.
It maintains a dictionary of variables.

Gestures
===

Variable assignment and macro invocation
---

* `&VAR`

  Initialize the span `VAR` from C variable `VAR` of type `JsonSpan`.

* `VAR = &(EXPR_1, EXPR_2)`

  Initialize the span `VAR` from `(JsonSpan) {EXPR_1, EXPR_2}`.

* `@MACRO(MACRO_ARGS)`

  Invoke a macro.

* `VAR = @MACRO(MACRO_ARGS)`

  Invoke a macro that defines a new variable.

* `VAR_1 = VAR_2[INDEX]`

  Initialize the span `VAR_1` from `VAR_2[INDEX]`.
  `INDEX` must be a constant integer if `VAR_2` is a list, constant string (either double-quoted or single-quoted) if `VAR_2` is a dict.

* `VAR_1 = VAR_2`

  Initialize the span `VAR_1` from the span `VAR_2`.

Dollar expansion
---

Inside a macro call (`MACRO_ARGS`), the expansion of dollar expressions (`${...}`) is performed.

Inside a dollar expression, `VAR[INDEX]` syntax is allowed; the whole dollar expression is replaced with the name of a temporary variable.

You can specify any positive number of opening braces; the number of closing braces must match the number of opening ones, e.g. `${{...}}`, `${{{...}}}`, etc.

Iteration
---

* `!for VAR_1 in VAR_2 {` or `!for VAR_1 in VAR_2`

  Iterate over the list `VAR_2`; `VAR_1` is element.

* `!for VAR_1, VAR_2 in VAR_3 {` or `!for VAR_1, VAR_2 in VAR_3`

  Iterate over the dict `VAR_3`; `VAR_1` is key, `VAR_2` is value.

Error handling
---

`HANDLER` is either `-` (do nothing) or C code (e.g. `goto error;`).

* `!handler global push HANDLER`

  Push `HANDLER` to the global stack of error handlers.

* `!handler global pop`

  Pop an item from the global stack of error handlers.

* `!handler for VAR set HANDLER`

  Set an error handler for variable `VAR`.

Exact and sparse flags
---

`YESNO` is either `yes` or `no`.

* `!exact global set YESNO`

  Set the global exact flag to `YESNO`.

* `!exact for VAR set YESNO`

  Set the exact flag for variable `VAR` to `YESNO`.

* `!sparse for VAR set YESNO`

  Set the sparse flag for variable `VAR` to `YESNO`.

Preemption
---

`PREEMPT_DEVICE` is either `-` (no preempt device) or a C expression of type `PreemptDevice *`.

* `!preempt global set PREEMPT_DEVICE`

  Set the global preempt device to `PREEMPT_DEVICE`.

* `!preempt for VAR set PREEMPT_DEVICE`

  Set the preempt device for variable `VAR` to `PREEMPT_DEVICE`.

* `!yield`

  Yield now using the global preempt device.

* `!yield NUMBER`

  Decrement the global preempt device’s `left` field by `NUMBER`;
  if it is less than or equal to zero, reset it and yield.

Syntactic sugar
---

* `{`

  Produces `{`.

* `}`

  Produces `}`.

Example
===

```
#define DSL_VMACRO_FIRST_CHAR(V, Sp) \
    char V = exch_utils_extract_first_char_from_str(Sp);

#define DSL_VMACRO_STR(V, Sp, BufSize) \
    char V[BufSize]; \
    exch_utils_span_cpy_str_or_raw(Sp, V, sizeof(V));

#define DSL_VMACRO_NUM(V, Sp, Scale) \
    int64_t V = exch_utils_parse_num_or_str_into_int(Sp, Scale);

#define DSL_VMACRO_EXTERNAL_ID(V, Sp) \
    DSL_VMACRO_STR(V, Sp, 40)

#define DSL_VMACRO_CLORDID(V, Sp) \
    DSL_VMACRO_NUM(V, Sp, 0)

#define DSL_VMACRO_QTY_OR_PRICE(V, Sp) \
    DSL_VMACRO_STR(V, Sp, 32)

#define DSL_VMACRO_CUM_QTY(V, Sp_CumQty, Sp_OrderQty) \
    DSL_VMACRO_QTY_OR_PRICE(cum_qty_1_, Sp_CumQty) \
    DSL_VMACRO_QTY_OR_PRICE(cum_qty_2_, Sp_OrderQty) \
    ExchExecQty V = {.cum_qty = cum_qty_1_, .total_qty = cum_qty_2_};

#define DSL_VMACRO_EXCH_STA(V, Sp) \
    int V = parse_exch_sta(Sp);

#define DSL_VMACRO_TS(V, Sp) \
    uint64_t V = parse_timestamp(Sp) * 1000u;

/* ... */

static bool ws_order_msg(JsonSpan action, JsonSpan data, uint64_t exch_resp_utime)
{
|   &action
|   action_first_char = @first_char(action)
    if (unlikely(action_first_char == 'd')) {
        turbolog_sayf("WS order message: got action=delete: what does it mean?");
        return false;
    }

|   &data
|   !for E in data {
|       internal_id = @clordid(${ E['clOrdID'] })
|       external_id = @external_id(${ E['orderID'] })
|       cum_qty = @cum_qty(${ E['cumQty'] }, ${ E['orderQty'] })
|       exch_sta = @exch_sta(${ E['ordStatus'] })
|       exch_time = @ts(${ E['timestamp'] })
        trader_order_status_cb(internal_id, external_id, exch_sta, &cum_qty, exch_time, exch_resp_utime, NULL);
|   }

    return true;
}
```
