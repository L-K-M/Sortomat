# Checks that need no compiler

CI is the only Swift compiler this project has, so a typo costs a full cycle —
and when Actions is unavailable it costs a day. These four scripts read the
sources and answer questions a compiler would answer first. They are not a
Swift parser and never will be; each is deliberately narrow, and each exists
because the mistake it catches has actually been made here.

    Tools/check/run                 # this checkout
    Tools/check/run /path/to/tree   # any other checkout or worktree

Every script prints a one-line summary ending in a count, so `run` is quiet
when all is well and specific when it is not.

## `l10n_keys.py` — every key exists, in both languages

`L10n.t` asserts in Debug on a missing key, so one absent string takes the
whole test suite down at the line that asked for it rather than failing one
assertion. This walks every `L10n.t`/`L10n.plural` call site and checks the key
is in both tables, that neither table has a key the other lacks, and that a
key's format specifiers agree between the two.

## `l10n_arity.py` — the arguments a string consumes

`String(format:)` reads its argument count from the *format string*, not from
the call. A German translation that grew a `%@` its English original never had
reads past the end of what the call site passed: not a wrong word on screen, a
crash, on German machines only. This compares each call site's argument count
against the slots its format string declares.

## `conformance.py` — a type that claims a protocol implements it

Caught a test stub that satisfied one of `FactSource`'s six requirements. The
project's protocols carry no default implementations except those written in
`extension <Protocol>`, so a requirement in neither the type, its extensions,
nor a protocol extension is a compile error.

## `init_labels.py` — call sites still match their initializers

The error it exists for: a struct gains, loses or renames a field and one call
site in another file is missed. It knows the rules that make a memberwise
argument omittable — a default value, a property wrapper, an implicitly-nil
`var` optional — and stays silent on anything it cannot read confidently:
unlabelled arguments, a type name declared twice, a trailing closure.

It checks *call sites*. Adding a stored property to a type with an explicit
initializer is an error inside that initializer, which no call site shows.

## What none of them do

They do not typecheck. An expression that is well-formed but wrongly typed, a
missing `import`, an actor-isolation violation, a `@MainActor` call from a
nonisolated context — all pass here and fail on CI. A clean run means the
cheap, mechanical mistakes are gone, not that the branch builds.
