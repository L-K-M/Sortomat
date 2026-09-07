import re, sys, os, glob

root = os.path.abspath(sys.argv[1])
src = open(os.path.join(root, "Sortomat/Model/L10n.swift")).read()

def table(name):
    m = re.search(r"static let %s: \[String: String\] = \[" % name, src)
    start = m.end()
    # find matching close: scan for "\n    ]" at column 4
    end = src.index("\n    ]", start)
    body = src[start:end]
    return dict(re.findall(r'^\s*"([^"]+)":\s*(.*?),?\s*$', body, re.M))

en, de = table("english"), table("german")

used_t, used_plural = set(), set()
for path in glob.glob(os.path.join(root, "Sortomat/**/*.swift"), recursive=True) + \
            glob.glob(os.path.join(root, "SortomatTests/**/*.swift"), recursive=True):
    if path.endswith("L10n.swift"):
        continue
    text = open(path).read()
    for k in re.findall(r'L10n\.t\(\s*"([^"]+)"', text):
        used_t.add(k)
    for k in re.findall(r'L10n\.plural\(\s*"([^"]+)"', text):
        used_plural.add(k)

need = set(used_t) | {k + s for k in used_plural for s in (".one", ".other")}
problems = []
for k in sorted(need):
    if k not in en: problems.append(f"USED-BUT-NO-EN  {k}")
    if k not in de: problems.append(f"USED-BUT-NO-DE  {k}")
for k in sorted(set(en) - set(de)): problems.append(f"EN-ONLY         {k}")
for k in sorted(set(de) - set(en)): problems.append(f"DE-ONLY         {k}")

spec = re.compile(r'%(?:\d+\$)?[-+ #0]*[\d*]*(?:\.\d+)?(?:hh|h|ll|l|q|L|z|j|t)?([@dioxXufFeEgGcspn%])')
for k in sorted(set(en) & set(de)):
    a = [s for s in spec.findall(en[k]) if s != '%']
    b = [s for s in spec.findall(de[k]) if s != '%']
    if a != b:
        problems.append(f"ARITY           {k}: en={a} de={b}")

print(f"{os.path.basename(root)}: en={len(en)} de={len(de)} used={len(need)} problems={len(problems)}")
for p in problems: print("   ", p)
