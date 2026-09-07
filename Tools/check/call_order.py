#!/usr/bin/env python3
"""Are static-method call sites still in the declaration's argument order?

The error this exists for: a helper grows a parameter, the caller passes it in
the wrong slot, and Swift refuses with "argument 'x' must precede argument 'y'"
— a compile error a checkout without a Swift compiler otherwise only learns
about from CI. `init_labels.py` answers the same question for initializers by
label; this one covers `Type.method(...)`, which nothing checked, and adds the
ordering test Swift actually enforces.

Deliberately conservative: it reads only fully-labelled calls to a name
declared exactly once as a static or class method, and stays quiet about
overloads, unlabelled parameters and anything else it cannot read confidently.
"""
import re, sys, pathlib

root = pathlib.Path(sys.argv[1]).resolve()
files = sorted(list((root / "Sortomat").rglob("*.swift")) +
               list((root / "SortomatTests").rglob("*.swift")))

def strip(src):
    # Order matters: raw strings, then multi-line, then plain, then comments —
    # a `/*` inside a string literal is text, not the start of a comment.
    src = re.sub(r'#"(?:.|\n)*?"#', '"S"', src)
    src = re.sub(r'"""(?:.|\n)*?"""', '"S"', src)
    src = re.sub(r'"(?:[^"\\\n]|\\.)*"', '"S"', src)
    src = re.sub(r'//[^\n]*', '', src)
    src = re.sub(r'/\*(?:.|\n)*?\*/', '', src)
    return src

def balanced(src, open_idx, opener="(", closer=")"):
    """Text inside the pair that starts at open_idx, or None if unbalanced."""
    depth, i = 0, open_idx
    while i < len(src):
        if src[i] == opener: depth += 1
        elif src[i] == closer:
            depth -= 1
            if depth == 0: return src[open_idx + 1:i], i
        i += 1
    return None, None

def split_args(text):
    out, depth, cur = [], 0, ""
    for ch in text:
        if ch in "([{": depth += 1
        elif ch in ")]}": depth -= 1
        if ch == "," and depth == 0:
            out.append(cur); cur = ""
        else:
            cur += ch
    if cur.strip(): out.append(cur)
    return out

sources = {f: strip(f.read_text()) for f in files}
blob = "\n".join(sources.values())

# Type.method -> ordered [(label, required)] , or None once ambiguous.
methods = {}
decl = re.compile(r'\b(?:public\s+|private\s+|internal\s+|final\s+|fileprivate\s+)*'
                  r'(?:struct|class|actor|enum|extension)\s+(\w+)')
for m in decl.finditer(blob):
    owner = m.group(1)
    brace = blob.find("{", m.end())
    if brace == -1: continue
    body, _ = balanced(blob, brace, "{", "}")
    if body is None: continue
    for fm in re.finditer(r'\b(?:static|class)\s+func\s+(\w+)\s*(?:<[^>(]*>)?\s*\(', body):
        key = f"{owner}.{fm.group(1)}"
        params, _ = balanced(body, fm.end() - 1)
        if params is None:
            methods[key] = None
            continue
        ordered, readable = [], True
        for p in split_args(params):
            p = p.strip()
            lm = re.match(r'([\w`]+)\s*(?:(\w+)\s*)?:', p)
            if not lm or lm.group(1) == "_":
                readable = False; break
            ordered.append((lm.group(1), "=" not in p))
        if not readable:
            methods[key] = None
        elif key in methods:
            methods[key] = None          # overloaded: which one is unknowable
        else:
            methods[key] = ordered

problems = 0
checked = 0
call = re.compile(r'\b([A-Z]\w+)\.(\w+)\s*\(')
for path, src in sorted(sources.items()):
    for m in call.finditer(src):
        key = f"{m.group(1)}.{m.group(2)}"
        declared = methods.get(key)
        if not declared: continue
        args, close = balanced(src, m.end() - 1)
        if args is None: continue
        labels, positional = [], False
        for a in split_args(args):
            lm = re.match(r'\s*([\w`]+)\s*:(?!:)', a)
            if lm: labels.append(lm.group(1))
            elif a.strip(): positional = True
        if positional or not labels: continue
        checked += 1
        names = [label for label, _ in declared]
        unknown = [l for l in labels if l not in names]
        required = [label for label, req in declared if req]
        missing = [r for r in required if r not in labels]
        # Swift takes arguments in declaration order; a defaulted parameter may
        # be left out, so the call's labels must be a subsequence of the
        # declaration's — not merely the same set.
        out_of_order = False
        if not unknown:
            cursor, order = 0, list(names)
            for l in labels:
                nxt = order.index(l, cursor) if l in order[cursor:] else -1
                if nxt == -1: out_of_order = True; break
                cursor = nxt + 1
        if not unknown and not missing and not out_of_order: continue
        bits = []
        if unknown: bits.append("unknown label(s): " + ", ".join(unknown))
        if missing: bits.append("missing: " + ", ".join(missing))
        if out_of_order:
            bits.append("out of order: passed " + ", ".join(labels)
                        + "; declared " + ", ".join(names))
        problems += 1
        line = src[:m.start()].count("\n") + 1
        print(f"{path.name}:{line}  {key}(…)  {'; '.join(bits)}")

print(f"{root.name}: {checked} static call sites read, {problems} suspect")
