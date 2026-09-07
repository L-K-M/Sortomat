#!/usr/bin/env python3
"""Do initializer call sites still match the type they are calling?

The error this exists for: a struct grows, loses or renames a field and one
call site in another file is missed. Deliberately conservative — it reports a
label the type has no parameter for, or a required parameter nobody passed,
and stays quiet about anything it cannot read confidently.
"""
import re, sys, pathlib, collections

root = pathlib.Path(sys.argv[1]).resolve()
files = sorted(list((root / "Sortomat").rglob("*.swift")) +
               list((root / "SortomatTests").rglob("*.swift")))

def strip(src):
    src = re.sub(r'"""(?:.|\n)*?"""', '"S"', src)
    src = re.sub(r'"(?:[^"\\\n]|\\.)*"', '"S"', src)
    src = re.sub(r'//[^\n]*', '', src)
    src = re.sub(r'/\*(?:.|\n)*?\*/', '', src)
    return src

def body_of(src, open_idx):
    depth, i = 0, open_idx
    while i < len(src):
        if src[i] == '{': depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0: return src[open_idx+1:i]
        i += 1
    return ""

def split_args(text):
    """Top-level comma split, ignoring nesting and closures."""
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

types = {}   # name -> {'inits': [ (set(required), set(all)) ], 'kind': str }
decl = re.compile(r'\b(?:public\s+|private\s+|internal\s+|final\s+|fileprivate\s+)*'
                  r'(struct|class|actor)\s+(\w+)\s*(?::\s*[^{]+?)?\s*\{')
for m in decl.finditer(blob):
    kind, name = m.group(1), m.group(2)
    body = body_of(blob, m.end() - 1)
    inits = []
    for im in re.finditer(r'(?<![.\w])init\??\s*\(', body):
        start = im.end() - 1
        depth, i = 0, start
        while i < len(body):
            if body[i] == '(': depth += 1
            elif body[i] == ')':
                depth -= 1
                if depth == 0: break
            i += 1
        params = split_args(body[start+1:i])
        required, allowed = set(), set()
        ok = True
        for p in params:
            p = p.strip()
            lm = re.match(r'([\w`]+)\s*(?:(\w+)\s*)?:', p)
            if not lm: ok = False; break
            label = lm.group(1)
            if label == "_": continue          # unlabelled — cannot match by name
            allowed.add(label)
            if "=" not in p: required.add(label)
        if ok: inits.append((required, allowed))
    if not inits and kind == "struct":
        # memberwise: stored properties in order. A computed property is not
        # one — `var body: some View {` is the whole of a SwiftUI view and
        # reading it as a field makes every view look mis-called.
        required, allowed = set(), set()
        for pm in re.finditer(r'^([ \t]*)((?:@\w+(?:\([^)]*\))?[ \t]+)*)'
                              r'((?:public|private|internal|fileprivate|static|lazy)[ \t]+)*'
                              r'(var|let)[ \t]+(\w+)[ \t]*(:[^\n]*|=[^\n]*)$', body, re.M):
            indent, wrappers, mods, kw, prop, rest = pm.groups()
            if "static" in pm.group(0): continue
            if len(indent) > 4: continue          # nested inside something else
            rest = rest.strip()
            annotated = rest.startswith(":")
            rest = rest.lstrip(":").strip()
            if kw == "var" and annotated:
                # computed / observed when a brace opens before any `=`
                brace, eq = rest.find("{"), rest.find("=")
                if brace != -1 and (eq == -1 or brace < eq): continue
            allowed.add(prop)
            has_default = ("=" in rest) or bool(wrappers)
            if annotated and kw == "var":
                # An optional `var` is implicitly nil, so the memberwise
                # initializer gives it a default and the caller may omit it.
                declared = rest.split("=")[0].strip()
                if declared.endswith("?") or declared.startswith("Optional<"):
                    has_default = True
            if not has_default: required.add(prop)
        if allowed: inits.append((required, allowed))
    if inits:
        if name in types: types[name]["ambiguous"] = True
        else: types[name] = {"inits": inits, "kind": kind, "ambiguous": False}

problems = 0
call = re.compile(r'\b([A-Z]\w+)\s*\(')
for path, src in sources.items():
    for m in call.finditer(src):
        name = m.group(1)
        if name not in types or types[name].get("ambiguous"): continue
        if re.search(r'[.\w]$', src[:m.start()].rstrip()[-1:] or " "): continue
        start = m.end() - 1
        depth, i = 0, start
        while i < len(src):
            if src[i] == '(': depth += 1
            elif src[i] == ')':
                depth -= 1
                if depth == 0: break
            i += 1
        if i >= len(src): continue
        args = split_args(src[start+1:i])
        labels, positional = set(), False
        for a in args:
            lm = re.match(r'\s*([\w`]+)\s*:(?!:)', a)
            if lm: labels.add(lm.group(1))
            elif a.strip(): positional = True
        if positional: continue          # unlabelled args: not readable by name
        trailing = re.match(r'\s*\{', src[i+1:])
        best = None
        for required, allowed in types[name]["inits"]:
            unknown = labels - allowed
            missing = required - labels
            score = len(unknown) * 10 + len(missing)
            if best is None or score < best[0]: best = (score, unknown, missing)
        if best and best[0] > 0:
            score, unknown, missing = best
            if trailing and not unknown: continue   # trailing closure fills one
            problems += 1
            bits = []
            if unknown: bits.append("unknown label(s): " + ", ".join(sorted(unknown)))
            if missing: bits.append("missing: " + ", ".join(sorted(missing)))
            line = src[:m.start()].count("\n") + 1
            print(f"{path.name}:{line}  {name}(…)  {'; '.join(bits)}")

print(f"{root.name}: {len(types)} constructible types, {problems} suspect call sites")
