#!/usr/bin/env python3
"""Does every type that claims a project protocol actually implement it?

Not a Swift parser — a reader with the same question a compiler asks first.
Swift protocols in this project carry no default implementations except the
ones written in `extension <Protocol>`, so a requirement that appears in
neither the type, its extensions, nor a protocol extension is a compile error.
"""
import re, sys, pathlib, collections

root = pathlib.Path(sys.argv[1]).resolve()
files = sorted(list((root / "Sortomat").rglob("*.swift")) +
               list((root / "SortomatTests").rglob("*.swift")))

def strip(src):
    src = re.sub(r'"""(?:.|\n)*?"""', '""', src)
    src = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', src)
    src = re.sub(r'//[^\n]*', '', src)
    src = re.sub(r'/\*(?:.|\n)*?\*/', '', src)
    return src

def body_of(src, open_idx):
    """Substring between the brace at open_idx and its match."""
    depth, i = 0, open_idx
    while i < len(src):
        if src[i] == '{': depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0: return src[open_idx+1:i]
        i += 1
    return src[open_idx+1:]

sources = {f: strip(f.read_text()) for f in files}
blob = "\n".join(sources.values())

# ---- protocols and their requirements -------------------------------------
protocols = {}          # name -> {'reqs': set(), 'inherits': set()}
for m in re.finditer(r'\b(?:public\s+|internal\s+)?protocol\s+(\w+)\s*(?::\s*([^{]+))?\{', blob):
    name, inherits = m.group(1), m.group(2) or ""
    body = body_of(blob, m.end() - 1)
    reqs = set()
    for r in re.finditer(r'\bfunc\s+(\w+)\s*\(([^)]*)\)', body):
        labels = [p.strip().split()[0] for p in r.group(2).split(',') if p.strip()]
        reqs.add(("func", r.group(1), len(labels)))
    for r in re.finditer(r'\bvar\s+(\w+)\s*:', body):
        reqs.add(("var", r.group(1), 0))
    protocols[name] = {
        "reqs": reqs,
        "inherits": {i.strip() for i in inherits.split(',') if i.strip()},
    }

# ---- members supplied by protocol extensions (defaults) -------------------
defaults = collections.defaultdict(set)
for m in re.finditer(r'\bextension\s+(\w+)\s*(?::[^{]+)?\{', blob):
    name = m.group(1)
    if name not in protocols: continue
    body = body_of(blob, m.end() - 1)
    for r in re.finditer(r'\bfunc\s+(\w+)\s*\(', body): defaults[name].add(r.group(1))
    for r in re.finditer(r'\bvar\s+(\w+)\s*:', body): defaults[name].add(r.group(1))

# ---- concrete types, their declared conformances and their members --------
members = collections.defaultdict(set)
claims = collections.defaultdict(set)
where = {}

decl = re.compile(r'\b(?:public\s+|private\s+|internal\s+|final\s+|fileprivate\s+)*'
                  r'(struct|class|enum|actor|extension)\s+(\w+)\s*(?::\s*([^{]+?))?\s*\{')
for path, src in sources.items():
    for m in decl.finditer(src):
        kind, name, inherits = m.group(1), m.group(2), m.group(3) or ""
        if kind != "extension" and name in protocols: continue
        body = body_of(src, m.end() - 1)
        for r in re.finditer(r'\bfunc\s+(\w+)\s*\(', body): members[name].add(r.group(1))
        for r in re.finditer(r'\b(?:var|let)\s+(\w+)\s*[:={]', body): members[name].add(r.group(1))
        for token in re.split(r'[,&]', inherits):
            token = token.split('<')[0].strip()
            if token in protocols:
                claims[name].add(token)
                where.setdefault((name, token), path.name)

def all_reqs(proto, seen=None):
    seen = seen or set()
    if proto in seen or proto not in protocols: return set()
    seen.add(proto)
    out = set(protocols[proto]["reqs"])
    for parent in protocols[proto]["inherits"]:
        out |= all_reqs(parent, seen)
    return out

def defaulted(proto, seen=None):
    seen = seen or set()
    if proto in seen or proto not in protocols: return set()
    seen.add(proto)
    out = set(defaults[proto])
    for parent in protocols[proto]["inherits"]:
        out |= defaulted(parent, seen)
    return out

problems = 0
for typename, protos in sorted(claims.items()):
    for proto in sorted(protos):
        missing = {r for r in all_reqs(proto)
                   if r[1] not in members[typename] and r[1] not in defaulted(proto)}
        if missing:
            problems += 1
            names = ", ".join(sorted(r[1] for r in missing))
            print(f"MISSING  {typename}: {proto}  ({where[(typename, proto)]})  -> {names}")

print(f"{root.name}: {len(protocols)} project protocols, "
      f"{sum(len(v) for v in claims.values())} conformances, {problems} incomplete")
