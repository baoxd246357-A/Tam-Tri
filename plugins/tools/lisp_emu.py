"""Mo phong nho tap con AutoLISP de kiem tra license_module.lsp khop voi sdoplat_lic.py.
Bao loi neu so nguyen vuot khoang 32 bit co dau (AutoLISP se tran)."""
import re, sys, random, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sdoplat_lic as ref

class Sym(str): pass
def tokenize(src):
    src = re.sub(r';[^\n]*', '', src)
    return re.findall(r'"(?:\\.|[^"\\])*"|\'|\(|\)|[^\s()\'"]+', src)
def parse(tokens):
    def rd(i):
        t = tokens[i]
        if t == '(':
            out = []; i += 1
            while tokens[i] != ')':
                x, i = rd(i); out.append(x)
            return out, i + 1
        if t == "'":
            x, i = rd(i + 1); return [Sym('quote'), x], i
        if t.startswith('"'):
            return t[1:-1].replace('\\\\', '\\'), i + 1
        try: return int(t), i + 1
        except ValueError: return Sym(t.lower()), i + 1
    out = []; i = 0
    while i < len(tokens):
        x, i = rd(i); out.append(x)
    return out
I32 = lambda v: v if isinstance(v, int) and -2**31 <= v < 2**31 else (_ for _ in ()).throw(OverflowError(v))
class Env:
    def __init__(s): s.g = {}; s.fn = {}; s.stack = []
    def get(s, n):
        for f in reversed(s.stack):
            if n in f: return f[n]
        return s.g.get(n)
    def set(s, n, v):
        for f in reversed(s.stack):
            if n in f: f[n] = v; return v
        s.g[n] = v; return v
def ev(x, E):
    if isinstance(x, Sym):
        if x == 't': return True
        if x == 'nil': return None
        return E.get(x)
    if not isinstance(x, list): return x
    if not x: return None
    h = x[0]
    if h == 'quote': return x[1] if x[1] != [] else None
    if h == 'setq':
        v = None
        for k in range(1, len(x), 2): v = E.set(x[k], ev(x[k + 1], E))
        return v
    if h == 'if':
        c = ev(x[1], E)
        if c not in (None, False): return ev(x[2], E)
        return ev(x[3], E) if len(x) > 3 else None
    if h == 'cond':
        for cl in x[1:]:
            v = ev(cl[0], E)
            if v not in (None, False):
                r = v
                for e in cl[1:]: r = ev(e, E)
                return r
        return None
    if h == 'and':
        v = True
        for e in x[1:]:
            v = ev(e, E)
            if v in (None, False): return None
        return v
    if h == 'or':
        for e in x[1:]:
            v = ev(e, E)
            if v not in (None, False): return v
        return None
    if h == 'progn':
        r = None
        for e in x[1:]: r = ev(e, E)
        return r
    if h == 'while':
        while ev(x[1], E) not in (None, False):
            for e in x[2:]: ev(e, E)
        return None
    if h == 'repeat':
        for _ in range(ev(x[1], E)):
            for e in x[2:]: ev(e, E)
        return None
    if h == 'foreach':
        var = x[1]; lst = ev(x[2], E) or []
        E.stack.append({var: None})
        for it in lst:
            E.stack[-1][var] = it
            for e in x[3:]: ev(e, E)
        E.stack.pop(); return None
    a = [ev(e, E) for e in x[1:]]
    if h in E.fn:
        params, body = E.fn[h]; loc = {}
        names = [p for p in params if p != '/']; k = params.index('/') if '/' in params else len(params)
        for j, p in enumerate(names): loc[p] = a[j] if j < k and j < len(a) else None
        E.stack.append(loc); r = None
        for e in body: r = ev(e, E)
        E.stack.pop(); return r
    B = {
        '+': lambda *v: I32(sum(v)), '-': lambda a, *v: I32(a - sum(v)) if v else I32(-a),
        '*': lambda *v: I32(__import__('math').prod(v)), 'rem': lambda a, b: I32(int(a - b * int(a / b))),
        '1+': lambda a: I32(a + 1), 'logand': lambda *v: __import__('functools').reduce(lambda p, q: p & q, v),
        'logxor': lambda *v: __import__('functools').reduce(lambda p, q: p ^ q, v),
        'lsh': lambda v, n: I32(v << n if n >= 0 else v >> -n), 'ascii': lambda s: ord(s[0]),
        'substr': lambda s, st, ln=None: s[st - 1:] if ln is None else s[st - 1:st - 1 + ln],
        'strlen': len, 'strcat': lambda *s: ''.join(s), 'strcase': lambda s, up=None: s.lower() if up else s.upper(),
        'nth': lambda n, l: l[n] if n < len(l) else None, 'list': lambda *v: list(v), 'reverse': lambda l: l[::-1],
        '=': lambda a, b: True if a == b else None, '/=': lambda a, b: True if a != b else None,
        '<': lambda a, b: True if a < b else None, '>': lambda a, b: True if a > b else None,
        '<=': lambda a, b: True if a <= b else None, '>=': lambda a, b: True if a >= b else None,
        'append': lambda *l: [i for s in l for i in (s or [])], 'cons': lambda a, l: [a] + (l or []),
        'itoa': str, 'atoi': lambda s: int(re.match(r'-?\d*', s).group(0) or 0), 'max': max,
        'vl-string-search': lambda p, s: (s.find(p) if p in s else None),
        'type': lambda v: Sym('str') if isinstance(v, str) else Sym('list'),
        'sd:lic-mid': lambda: 'AAAA-BBBB-CCCC',
    }
    if h in B: return B[h](*a)
    raise NameError(h)

def load(path, repl):
    src = open(path).read()
    for k, v in repl.items(): src = src.replace(k, v)
    E = Env()
    for f in parse(tokenize(src)):
        if isinstance(f, list) and f and f[0] == 'defun':
            E.fn[f[1]] = (f[2], f[3:])
        elif isinstance(f, list) and f and f[0] == 'setq':
            ev(f, E)
    return E

if __name__ == '__main__':
    here = os.path.dirname(os.path.abspath(__file__))
    E = load(os.path.join(here, 'license_module.lsp'), {'@@SECRET@@': 'S'})
    E.fn.pop('sd:lic-mid', None)
    rnd = random.Random(7); n = 0
    for _ in range(300):
        s = ''.join(rnd.choice('ABCDEF0123456789-{}|:GVC') for _ in range(rnd.randint(5, 60)))
        assert ev([Sym('sd:lic-code'), s], E) == ref.lic_code(s), s
        assert ev([Sym('sd:lic-mid-of'), s], E) == ref.lic_mid_of(s), s
        n += 1
    assert ev([Sym('sd:lic-norm'), ' ab-c1 d!'], E) == 'ABC1D'
    for k in (0, 1, 9, 10):
        v = f"{k}:" + ev([Sym('sd:lic-ucheck'), k], E)
        assert ev([Sym('sd:lic-uparse'), v], E) == k, v
    assert ev([Sym('sd:lic-uparse'), '3:XXXXX-XXXXX-XXXXX'], E) is None   # bi sua
    assert ev([Sym('sd:lic-uparse'), 'abc'], E) is None
    print('OK: LISP khop Python tren', n, 'chuoi, khong tran so nguyen 32 bit')
