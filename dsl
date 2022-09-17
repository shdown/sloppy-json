#!/usr/bin/env python3
import sys
import traceback
import re


DSL_PREFIX = '/*|*/ '


class GlobalParams:
    def __init__(self):
        self.exact = False
        self.preempt_device = None
        self.error_handlers = [None]

    def push_error_handler(self, error_handler):
        self.error_handlers.append(error_handler)

    def pop_error_handler(self):
        if len(self.error_handlers) == 1:
            raise ValueError('cannot pop initial error handler')
        self.error_handlers.pop()


class AuxVarNameGenerator:
    def __init__(self):
        self.i = 0

    def __call__(self):
        self.i += 1
        return f'DSL_aux_{self.i}_'


class SpanVariable:
    def __init__(self, name, exact, preempt_device, error_handler):
        self.name = name
        self.loads = []
        self.exact = exact
        self.preempt_device = preempt_device
        self.error_handler = error_handler
        self.sparse = False

    def add_load(self, load):
        self.loads.append(load)

    def is_first_load(self, load):
        return self.loads and self.loads[0] is load

    def _prepare_parse_funcall(self, func_name, func_args, allow_exact):
        if allow_exact and self.exact:
            func_name += '_exact'
        if self.preempt_device is not None:
            func_name = 'PREEMPT_' + func_name
            func_args.append(self.preempt_device)

        expr = '%s(%s)' % (func_name, ', '.join(func_args))

        if self.error_handler is None:
            return '%s;' % expr
        else:
            return 'if (unlikely(%s < 0)) { %s }' % (expr, self.error_handler)

    def _gen_code_dict(self):
        lines = []
        aux_name = aux_var_name_generator()
        lines.append('JsonFieldEntry %s[] = {' % aux_name)

        key2index = {}
        for load in self.loads:
            key = load.index
            if key in key2index:
                continue
            index = len(key2index)
            key2index[key] = index
            lines.append('JSON_FENTRY("%s"),' % key)
        lines.append('};')

        lines.append(self._prepare_parse_funcall(
            'json_parse_dict_fields',
            [
                '%s.begin' % self.name,
                '%s.end' % self.name,
                aux_name,
                str(len(key2index)),
            ],
            allow_exact=True
        ))

        for load in self.loads:
            index = key2index[load.index]
            lines.append('JsonSpan %s = json_span_from_fentry(%s[%d]);' % (load.lhs, aux_name, index))

        return lines

    def _gen_code_list_sparse(self):
        sorted_loads = list(self.loads)
        sorted_loads.sort(key=lambda load: load.index)

        lines = []
        aux_name = aux_var_name_generator()
        lines.append('JsonSparseElemEntry %s[] = {' % aux_name)
        for load in sorted_loads:
            lines.append('{%d, NULL, NULL},' % load.index)
        lines.append('};')

        lines.append(self._prepare_parse_funcall(
            'json_parse_array_elems_sparse',
            [
                '%s.begin' % self.name,
                '%s.end' % self.name,
                aux_name,
                str(len(sorted_loads)),
            ],
            allow_exact=False
        ))

        for i, load in enumerate(sorted_loads):
            lines.append('JsonSpan %s = json_span_from_seentry(%s[%d]);' % (load.lhs, aux_name, i))
        return lines

    def _gen_code_list_dense(self):
        lines = []
        aux_name = aux_var_name_generator()
        n = 1 + max(load.index for load in self.loads)
        lines.append('JsonElemEntry %s[%d] = {0};' % (aux_name, n))

        lines.append(self._prepare_parse_funcall(
            'json_parse_array_elems',
            [
                '%s.begin' % self.name,
                '%s.end' % self.name,
                aux_name,
                str(n),
            ],
            allow_exact=False
        ))

        for load in self.loads:
            lines.append('JsonSpan %s = json_span_from_eentry(%s[%d]);' % (load.lhs, aux_name, load.index))
        return lines

    def gen_code(self):
        if all(type(x.index) is str for x in self.loads):
            return self._gen_code_dict()

        if all(type(x.index) is int for x in self.loads):
            if self.sparse:
                return self._gen_code_list_sparse()
            else:
                return self._gen_code_list_dense()

        raise ValueError('heterogeneous container indices')


class Load:
    def __init__(self, lhs, span_var, index):
        self.lhs = lhs
        self.span_var = span_var
        self.index = index

    def __call__(self):
        if not self.span_var.is_first_load(self):
            return None
        return self.span_var.gen_code()


class Registry:
    def __init__(self):
        self.reg = {}

    def assign(self, name):
        self.reg[name] = SpanVariable(
            name,
            exact=global_params.exact,
            preempt_device=global_params.preempt_device,
            error_handler=global_params.error_handlers[-1])

    def resolve(self, name):
        return self.reg[name]


class Dispatcher:
    def __init__(self):
        self.rules = []
        self.xlat = str.maketrans({
            ' ': r'\s+',
            '@': r'([_a-zA-Z][_a-zA-Z0-9]*)',
            ',': r'\s*,\s*',
            '{': r'\s*({?)\s*',
            '*': r'(\S.*)',
            '?': r'(yes|no)',
            '#': r'([1-9][0-9]*)',
        })

    def add_pattern(self, pattern, handler):
        regex = re.compile(pattern.translate(self.xlat))
        self.rules.append((regex, handler))

    def dispatch(self, s):
        for pattern, handler in self.rules:
            m = pattern.fullmatch(s)
            if m:
                return handler, m.groups()
        raise ValueError(f'cannot dispatch {repr(s)}')


registry = Registry()


global_params = GlobalParams()


aux_var_name_generator = AuxVarNameGenerator()


pragma_dispatcher = Dispatcher()


def parse_braced_expr(expr, braces, allow_bare_ident=False):
    segments = expr.split(braces[0], maxsplit=1)
    if len(segments) != 2:
        if allow_bare_ident:
            return expr.strip(), None
        raise ValueError('expected braced expression')
    x, y = segments[0].strip(), segments[1].strip()
    if not y.endswith(braces[1]):
        raise ValueError('mismatched braces')
    return x, y[:-len(braces[1])]


def parse_load(expr):
    container, index = parse_braced_expr(expr, braces='[]', allow_bare_ident=True)
    if index is None:
        return container, None
    first_sym = index[:1]
    if first_sym in '"\'':
        if not index.endswith(first_sym):
            raise ValueError('unterminated string')
        return container, index[1:-1]
    else:
        i = int(index)
        if i < 0:
            raise ValueError('negative array index')
        return container, i


def make_new_load(lhs, span_name, index):
    span_var = registry.resolve(span_name)
    load = Load(lhs, span_var, index)
    span_var.add_load(load)
    return load


def evaluate_expr_to_varname(expr):
    container, index = parse_load(expr)
    if index is None:
        return [], expr
    aux_name = aux_var_name_generator()
    registry.assign(aux_name)
    return [make_new_load(aux_name, container, index)], aux_name


def expand_dollar_exprs(s):
    prefixes = []
    chunks = []
    i = 0
    n = len(s)
    while True:
        j = s.find('${', i)
        if j == -1:
            chunks.append(s[i:])
            break
        chunks.append(s[i:j])

        j += 2
        levels = 1
        while j < n and s[j] == '{':
            j += 1
            levels += 1

        k = s.find('}' * levels, j)
        if k == -1:
            raise ValueError('cannot evaluate $-expression')
        cur_pfx, varname = evaluate_expr_to_varname(s[j:k])
        prefixes.extend(cur_pfx)
        chunks.append(varname)
        i = k + levels

    return prefixes, ''.join(chunks)


def transform_macro_call(expr, first_arg=None):
    func_name, raw_args = parse_braced_expr(expr[1:], braces='()')
    prefixes, args = expand_dollar_exprs(raw_args)
    macro_suffix = func_name.upper()
    if first_arg is None:
        return prefixes + [f'DSL_MACRO_{macro_suffix}({args})']
    else:
        return prefixes + [f'DSL_VMACRO_{macro_suffix}({first_arg}, {args})']


def parse_assignment(expr):
    segments = expr.split('=', maxsplit=1)
    if len(segments) != 2:
        raise ValueError('expected "VAR = EXPR" form')
    return segments[0].strip(), segments[1].strip()


def parse_yes_no(s):
    if s == 'yes':
        return True
    if s == 'no':
        return False
    return ValueError(f'expected either "yes" or "no", found {repr(s)}')


def parse_error_handler_descr(s):
    if s == '-':
        return None
    return s


def parse_preempt_device_descr(s):
    if s == '-':
        return None
    return s


def prepare_next_funcall(container_name, func_name, func_args):
    span_var = registry.resolve(container_name)
    preempt_device = span_var.preempt_device
    if preempt_device is not None:
        func_name = 'PREEMPT_' + func_name
        func_args.append(preempt_device)
    return '%s(%s)' % (func_name, ', '.join(func_args))


def handle_for_over_list(iter_name, container_name, suffix):
    registry.assign(iter_name)

    func_name = 'json_array_next'
    func_args = [
        container_name,
        '&' + iter_name,
    ]
    expr = prepare_next_funcall(container_name, func_name, func_args)
    return 'for (JsonSpan %s = {0}; %s > 0;)%s' % (
        iter_name, expr, suffix)


def handle_for_over_dict(k_iter_name, v_iter_name, container_name, suffix):
    registry.assign(k_iter_name)
    registry.assign(v_iter_name)

    func_name = 'json_dict_next'
    func_args = [
        container_name,
        '&' + k_iter_name,
        '&' + v_iter_name,
    ]
    expr = prepare_next_funcall(container_name, func_name, func_args)
    return 'for (JsonSpan %s = {0}, %s = {0}; %s > 0;)%s' % (
        k_iter_name, v_iter_name, expr, suffix)


def handle_handler_global_push(descr):
    global_params.push_error_handler(parse_error_handler_descr(descr))


def handle_handler_global_pop():
    global_params.pop_error_handler()


def handle_handler_for_set(varname, descr):
    span_var = registry.resolve(varname)
    span_var.error_handler = parse_error_handler_descr(descr)


def handle_exact_global(yes_no):
    global_params.exact = parse_yes_no(yes_no)


def handle_exact_for_set(varname, yes_no):
    span_var = registry.resolve(varname)
    span_var.exact = parse_yes_no(yes_no)


def handle_preempt_global_set(descr):
    global_params.preempt_device = parse_preempt_device_descr(descr)


def handle_preempt_for_set(varname, descr):
    span_var = registry.resolve(varname)
    span_var.preempt_device = parse_preempt_device_descr(descr)


def handle_sparse_for_set(varname, descr):
    span_var = registry.resolve(varname)
    span_var.sparse = parse_yes_no(descr)


def handle_yield(n=None):
    preempt_device = global_params.preempt_device
    if preempt_device is None:
        raise ValueError('cannot !yield without global preempt device')
    if n is None:
        return 'preempt_yield(%s);' % preempt_device
    elif n == '1':
        return 'preempt_maybe_yield(%s);' % preempt_device
    else:
        return 'preempt_maybe_yield_n(%s, %s);' % (preempt_device, n)


def handle_dsl_line(line):
    line = line.strip()
    sigil = line[:1]
    if sigil == '!':
        func, args = pragma_dispatcher.dispatch(line[1:])
        return func(*args)
    elif sigil == '@':
        return transform_macro_call(line)
    elif sigil == '&':
        varname = line[1:].strip()
        registry.assign(varname)
    elif sigil == '}':
        if line != '}':
            raise ValueError('expected "}" form')
        return '}'
    elif sigil == '{':
        if line != '{':
            raise ValueError('expected "{" form')
        return '{'
    else:
        lhs, rhs = parse_assignment(line)
        registry.assign(lhs)
        sigil = rhs[:1]
        if sigil == '&':
            amp, args = parse_braced_expr(rhs, braces='()')
            if amp != '&':
                raise ValueError('expected "VAR = &(EXPR1, EXPR2)" form')
            return 'JsonSpan %s = {%s};' % (lhs, args)
        elif sigil == '@':
            return transform_macro_call(rhs, first_arg=lhs)
        else:
            container, index = parse_load(rhs)
            if index is None:
                return f'JsonSpan {lhs} = {container};'
            return make_new_load(lhs, container, index)


def add_pragma_dispatcher_rules():
    pragma_dispatcher.add_pattern('for @ in @{', handle_for_over_list)
    pragma_dispatcher.add_pattern('for @,@ in @{', handle_for_over_dict)

    pragma_dispatcher.add_pattern('handler global push *', handle_handler_global_push)
    pragma_dispatcher.add_pattern('handler global pop', handle_handler_global_pop)
    pragma_dispatcher.add_pattern('handler for @ set *', handle_handler_for_set)

    pragma_dispatcher.add_pattern('exact global set ?', handle_exact_global)
    pragma_dispatcher.add_pattern('exact for @ set ?', handle_exact_for_set)

    pragma_dispatcher.add_pattern('sparse for @ set ?', handle_sparse_for_set)

    pragma_dispatcher.add_pattern('preempt global set *', handle_preempt_global_set)
    pragma_dispatcher.add_pattern('preempt for @ set *', handle_preempt_for_set)

    pragma_dispatcher.add_pattern('yield', handle_yield)
    pragma_dispatcher.add_pattern('yield #', handle_yield)


def print_error_and_die(linenum, t):
    etype, evalue, tb = t
    print(f'ERROR at line {linenum}: {etype.__name__}: {evalue}', file=sys.stderr)
    traceback.print_tb(tb)
    sys.exit(1)


def read_input(f):
    result = []
    for num, line in enumerate(f, start=1):
        if line[:1] == '|':
            try:
                obj = handle_dsl_line(line[1:])
            except ValueError:
                t = sys.exc_info()
                print_error_and_die(num, t)
            else:
                result.append((num, False, obj))
        else:
            line = line.rstrip('\n')
            result.append((num, True, line))
    return result


def write_output(processed_input):

    def _handle_object(obj, chunks):
        if obj is None:
            return
        elif type(obj) is str:
            chunks.append(obj)
        elif type(obj) is list:
            for obj2 in obj:
                _handle_object(obj2, chunks)
        else:
            obj2 = obj()
            _handle_object(obj2, chunks)

    for num, is_verbatim, obj in processed_input:
        if is_verbatim:
            print(obj)
            continue

        chunks = []
        try:
            _handle_object(obj, chunks)
        except ValueError:
            t = sys.exc_info()
            print_error_and_die(num, t)
        raw_s = ' '.join(chunks)
        print(DSL_PREFIX + (raw_s or '/*empty*/'))


def main():
    if len(sys.argv) != 2:
        print('USAGE: %s INPUT_FILE' % sys.argv[0], file=sys.stderr)
        sys.exit(2)

    add_pragma_dispatcher_rules()

    with open(sys.argv[1], 'r') as f:
        processed_input = read_input(f)
    write_output(processed_input)


if __name__ == '__main__':
    main()
