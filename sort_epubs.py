#!/usr/bin/env python3
"""Sort EPUB files into a {Genre}/{Nachname, Vorname}/{Titel}.epub hierarchy.

For every EPUB found below the source directory the script extracts the
filename, the OPF metadata and a text sample from the beginning of the book,
sends them to the Mistral API for classification against a fixed list of
German genres, and then moves (or copies) the file into the target hierarchy.

Requires only the Python standard library.

Usage:
    python3 sort_epubs.py SOURCE_DIR TARGET_DIR --api-key YOUR_MISTRAL_KEY
    python3 sort_epubs.py SOURCE_DIR TARGET_DIR              # uses $MISTRAL_API_KEY
    python3 sort_epubs.py SOURCE_DIR TARGET_DIR --dry-run    # preview only
"""

import argparse
import html.entities
import json
import os
import re
import shutil
import sys
import time
import unicodedata
import urllib.error
import urllib.request
import zipfile
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath
from xml.etree import ElementTree

# ---------------------------------------------------------------------------
# Normalized German genres. Books are always sorted into exactly one of these.
# ---------------------------------------------------------------------------
GENRES = [
    # Belletristik
    "Abenteuer",
    "Belletristik",
    "Comic & Manga",
    "Erotik",
    "Fantasy",
    "Historischer Roman",
    "Horror",
    "Humor & Satire",
    "Kinder- & Jugendbuch",
    "Klassiker",
    "Krimi & Thriller",
    "Kurzgeschichten",
    "Liebesroman",
    "Lyrik & Drama",
    "Märchen & Sagen",
    "Science-Fiction",
    # Sachbücher
    "Biografie & Memoiren",
    "Geschichte",
    "Gesundheit & Ernährung",
    "Kochbuch",
    "Kunst & Kultur",
    "Philosophie",
    "Politik & Gesellschaft",
    "Ratgeber & Selbsthilfe",
    "Reise",
    "Religion & Spiritualität",
    "Sachbuch",
    "True Crime",
    "Wirtschaft & Finanzen",
    "Wissenschaft & Technik",
    # Fallback
    "Unbekannt",
]

MISTRAL_URL = "https://api.mistral.ai/v1/chat/completions"

XMLNS = {
    "container": "urn:oasis:names:tc:opendocument:xmlns:container",
    "opf": "http://www.idpf.org/2007/opf",
    "dc": "http://purl.org/dc/elements/1.1/",
}


# ---------------------------------------------------------------------------
# EPUB parsing
# ---------------------------------------------------------------------------
_XML_PREDEFINED_ENTITIES = {"amp", "lt", "gt", "quot", "apos"}

# Characters that are illegal in XML 1.0 (e.g. stray control bytes from a
# mis-decoded Latin-1 source). Anything outside these ranges is dropped.
_XML_ILLEGAL_RE = re.compile(
    "[^\t\n\r\u0020-\ud7ff\ue000-\ufffd\U00010000-\U0010ffff]"
)

# XML declaration at the very start of a document (optionally after a BOM).
_XML_DECL_RE = re.compile(r"^\ufeff?\s*<\?xml.*?\?>\s*", re.DOTALL)


# Declarations that really mean Windows-1252 in the wild (per WHATWG); decoding
# these as strict Latin-1 would turn bytes like 0x97 ("—") into C1 controls.
_LATIN1_ALIASES = {
    "iso-8859-1", "iso8859-1", "iso_8859-1", "8859-1", "latin-1", "latin1",
    "l1", "cp819", "ascii", "us-ascii",
}


def _normalize_encoding(enc):
    return "cp1252" if enc.lower() in _LATIN1_ALIASES else enc


def _decode_xml_bytes(data):
    """Best-effort decode of XML bytes: BOM, then declared, then common codecs."""
    if data.startswith(b"\xef\xbb\xbf"):
        return data[3:].decode("utf-8", "replace")
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16", "replace")

    encodings = []
    match = re.match(rb"""\s*<\?xml[^>]*?encoding=["']([\w.\-]+)["']""", data)
    if match:
        encodings.append(_normalize_encoding(match.group(1).decode("ascii", "replace")))
    encodings += ["utf-8", "cp1252"]

    for enc in encodings:
        try:
            return data.decode(enc)
        except (LookupError, UnicodeDecodeError):
            continue
    return data.decode("latin-1", "replace")  # never fails


def _fix_xml_text(text):
    """Repair common non-conformities: HTML entities, bare '&', bad chars."""

    def repl(match):
        name = match.group(1)
        if name in _XML_PREDEFINED_ENTITIES:
            return match.group(0)
        char = html.entities.html5.get(name + ";")
        return html.escape(char) if char is not None else match.group(0)

    text = re.sub(r"&([A-Za-z][A-Za-z0-9]{0,31});", repl, text)
    # Escape any '&' that does not start a valid XML reference.
    text = re.sub(
        r"&(?!#[0-9]+;|#x[0-9A-Fa-f]+;|amp;|lt;|gt;|quot;|apos;)", "&amp;", text
    )
    return _XML_ILLEGAL_RE.sub("", text)


def parse_xml_lenient(data):
    """Parse XML bytes; real-world EPUBs are frequently non-conforming."""
    try:
        return ElementTree.fromstring(data)
    except ElementTree.ParseError:
        pass
    # Decode with the right codec, drop the (now inaccurate) encoding
    # declaration so ElementTree accepts the str, and repair the content.
    text = _XML_DECL_RE.sub("", _decode_xml_bytes(data), count=1)
    return ElementTree.fromstring(_fix_xml_text(text))


class _TextExtractor(HTMLParser):
    """Collects the visible text of an (X)HTML document."""

    _SKIP_TAGS = {"script", "style", "head", "title"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self._skip_depth = 0
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag in self._SKIP_TAGS:
            self._skip_depth += 1

    def handle_endtag(self, tag):
        if tag in self._SKIP_TAGS and self._skip_depth > 0:
            self._skip_depth -= 1

    def handle_data(self, data):
        if self._skip_depth == 0:
            self.parts.append(data)

    def text(self):
        return re.sub(r"\s+", " ", " ".join(self.parts)).strip()


def _html_to_text(raw):
    extractor = _TextExtractor()
    try:
        extractor.feed(raw)
    except Exception:
        pass
    return extractor.text()


def _find_opf_path(zf):
    """Locate the OPF package document, tolerating non-standard layouts."""
    names = zf.namelist()
    # Case-insensitive lookup, ignoring a leading "./".
    lookup = {n.lstrip("./").lower(): n for n in names}

    container = lookup.get("meta-inf/container.xml")
    if container:
        try:
            root = parse_xml_lenient(zf.read(container))
            rootfile = root.find(".//container:rootfile", XMLNS)
            full = rootfile.get("full-path") if rootfile is not None else None
            if full:
                return lookup.get(full.lstrip("./").lower(), full)
        except Exception:
            pass  # fall through to scanning for a .opf file

    # Fallback: no usable container.xml — pick the shallowest .opf in the zip.
    opfs = sorted(
        (n for n in names if n.lower().endswith(".opf")),
        key=lambda n: (n.count("/"), len(n)),
    )
    if opfs:
        return opfs[0]
    raise ValueError("Weder container.xml noch .opf-Datei gefunden")


def read_epub(path, sample_chars=4000):
    """Return (metadata dict, text sample) for an EPUB file."""
    with zipfile.ZipFile(path) as zf:
        opf_path = _find_opf_path(zf)
        opf_root = parse_xml_lenient(zf.read(opf_path))
        metadata = _parse_opf_metadata(opf_root)
        sample = _extract_sample(zf, opf_root, opf_path, sample_chars)
    return metadata, sample


def _parse_opf_metadata(opf_root):
    meta = {}

    def dc_all(tag):
        return [
            (el.text or "").strip()
            for el in opf_root.findall(f".//dc:{tag}", XMLNS)
            if el.text and el.text.strip()
        ]

    titles = dc_all("title")
    meta["title"] = titles[0] if titles else ""

    creators = []
    for el in opf_root.findall(".//dc:creator", XMLNS):
        name = (el.text or "").strip()
        if not name:
            continue
        file_as = el.get(f"{{{XMLNS['opf']}}}file-as", "")
        creators.append({"name": name, "file_as": file_as})
    meta["creators"] = creators

    meta["subjects"] = dc_all("subject")
    meta["language"] = ", ".join(dc_all("language"))
    meta["publisher"] = ", ".join(dc_all("publisher"))
    descriptions = dc_all("description")
    meta["description"] = _html_to_text(descriptions[0])[:1500] if descriptions else ""
    return meta


def _extract_sample(zf, opf_root, opf_path, sample_chars):
    """Concatenate text from the first real content documents in spine order."""
    manifest = {}
    for item in opf_root.findall(".//opf:manifest/opf:item", XMLNS):
        manifest[item.get("id")] = {
            "href": item.get("href", ""),
            "media_type": item.get("media-type", ""),
        }

    opf_dir = PurePosixPath(opf_path).parent
    names = set(zf.namelist())
    names_lower = {n.lower(): n for n in names}
    chunks = []
    collected = 0

    for itemref in opf_root.findall(".//opf:spine/opf:itemref", XMLNS):
        item = manifest.get(itemref.get("idref"))
        if not item or "html" not in item["media_type"]:
            continue
        href = urllib.request.unquote(item["href"])
        doc_path = str((opf_dir / href)) if str(opf_dir) != "." else href
        # Normalize any ../ segments
        doc_path = str(PurePosixPath(os.path.normpath(doc_path)))
        if doc_path not in names:
            doc_path = names_lower.get(doc_path.lower())
            if doc_path is None:
                continue
        try:
            text = _html_to_text(zf.read(doc_path).decode("utf-8", "replace"))
        except Exception:
            continue
        # Skip cover pages, title pages, TOCs etc. that carry almost no text
        if len(text) < 200:
            continue
        chunks.append(text)
        collected += len(text)
        if collected >= sample_chars:
            break

    return " ".join(chunks)[:sample_chars]


# ---------------------------------------------------------------------------
# Mistral classification
# ---------------------------------------------------------------------------
SYSTEM_PROMPT = """\
Du bist ein erfahrener Bibliothekar und klassifizierst E-Books.

Antworte ausschliesslich mit einem JSON-Objekt in genau dieser Form:
{
  "genre": "<eines der erlaubten Genres>",
  "author_last_name": "<Nachname der Hauptautorin / des Hauptautors>",
  "author_first_name": "<Vorname(n); leerer String falls unbekannt oder nicht vorhanden>",
  "title": "<bereinigter Buchtitel>"
}

Regeln:
- "genre" MUSS exakt einer der folgenden Werte sein: {genres}
- Wähle das passendste Genre anhand von Metadaten, Dateiname und Textauszug.
  Nur wenn wirklich keine Zuordnung möglich ist, verwende "Unbekannt".
- Bei mehreren Autoren nimm die erstgenannte Person.
- Pseudonyme und Einwort-Namen: kompletter Name in "author_last_name",
  "author_first_name" bleibt leer. Ist der Autor unbekannt, setze
  "author_last_name" auf "Unbekannt".
- "title": der eigentliche Buchtitel in korrekter Gross-/Kleinschreibung,
  ohne Dateiendungen, ohne Verlagsangaben, ohne Reihennummern-Präfixe wie
  "01 - ". Ein Untertitel darf bleiben, wenn er Teil des Titels ist.
"""


def build_user_prompt(path, meta, sample):
    creators = "; ".join(
        c["name"] + (f" (file-as: {c['file_as']})" if c["file_as"] else "")
        for c in meta["creators"]
    )
    parts = [
        f"Dateiname: {path.name}",
        f"Ordner: {path.parent.name}",
        f"Titel (Metadaten): {meta['title'] or '-'}",
        f"Autor(en) (Metadaten): {creators or '-'}",
        f"Sprache: {meta['language'] or '-'}",
        f"Verlag: {meta['publisher'] or '-'}",
        f"Schlagwörter: {', '.join(meta['subjects']) or '-'}",
        f"Beschreibung: {meta['description'] or '-'}",
        "",
        "Textauszug vom Buchanfang:",
        sample or "(kein Text extrahierbar)",
    ]
    return "\n".join(parts)


def call_mistral(api_key, model, user_prompt, max_retries=4, timeout=60):
    payload = {
        "model": model,
        "temperature": 0,
        "response_format": {"type": "json_object"},
        "messages": [
            {
                "role": "system",
                "content": SYSTEM_PROMPT.replace(
                    "{genres}", json.dumps(GENRES, ensure_ascii=False)
                ),
            },
            {"role": "user", "content": user_prompt},
        ],
    }
    body = json.dumps(payload).encode("utf-8")

    last_error = None
    for attempt in range(max_retries):
        request = urllib.request.Request(
            MISTRAL_URL,
            data=body,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                data = json.loads(response.read().decode("utf-8"))
            return data["choices"][0]["message"]["content"]
        except urllib.error.HTTPError as err:
            if err.code == 401:
                raise SystemExit("Fehler: Mistral API-Key wurde abgelehnt (401).")
            if err.code in (429, 500, 502, 503, 504) and attempt < max_retries - 1:
                retry_after = err.headers.get("Retry-After")
                wait = float(retry_after) if retry_after else 2.0 * (2**attempt)
                time.sleep(wait)
                last_error = err
                continue
            raise
        except (urllib.error.URLError, TimeoutError) as err:
            if attempt < max_retries - 1:
                time.sleep(2.0 * (2**attempt))
                last_error = err
                continue
            raise
    raise RuntimeError(f"Mistral API nicht erreichbar: {last_error}")


def parse_classification(raw):
    """Parse the model's JSON answer and validate the genre."""
    text = raw.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text)
    data = json.loads(text)

    genre = str(data.get("genre", "")).strip()
    if genre not in GENRES:
        # tolerate case/whitespace deviations, otherwise fall back
        lookup = {g.casefold(): g for g in GENRES}
        genre = lookup.get(genre.casefold(), "Unbekannt")

    last = str(data.get("author_last_name", "")).strip() or "Unbekannt"
    first = str(data.get("author_first_name", "")).strip()
    title = str(data.get("title", "")).strip()
    return genre, last, first, title


# ---------------------------------------------------------------------------
# Target paths and file moving
# ---------------------------------------------------------------------------
def sanitize_component(name, max_len=120):
    """Make a string safe to use as a single file/directory name."""
    name = unicodedata.normalize("NFC", name)
    name = re.sub(r'[<>:"/\\|?*\x00-\x1f]', " ", name)
    name = re.sub(r"\s+", " ", name).strip(" .")
    name = name[:max_len].strip(" .")
    return name or "Unbekannt"


def build_target(target_root, genre, last, first, title):
    author = f"{last}, {first}" if first else last
    return (
        target_root
        / sanitize_component(genre)
        / sanitize_component(author)
        / (sanitize_component(title, max_len=150) + ".epub")
    )


def resolve_collision(source, destination):
    """Return final destination, or None if an identical file already exists."""
    if not destination.exists():
        return destination
    if destination.stat().st_size == source.stat().st_size:
        return None  # very likely the same book
    stem, parent = destination.stem, destination.parent
    for i in range(2, 100):
        candidate = parent / f"{stem} ({i}).epub"
        if not candidate.exists():
            return candidate
        if candidate.stat().st_size == source.stat().st_size:
            return None
    raise RuntimeError(f"Zu viele Namenskollisionen für {destination}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def find_epubs(source, target):
    """All EPUBs below source, excluding anything already inside target."""
    epubs = []
    for path in sorted(source.rglob("*")):
        if not (path.is_file() and path.suffix.lower() == ".epub"):
            continue
        try:
            path.relative_to(target)
            continue  # already sorted, skip
        except ValueError:
            pass
        epubs.append(path)
    return epubs


def main():
    parser = argparse.ArgumentParser(
        description="Sortiert EPUBs per Mistral-Klassifikation in "
        "Genre/Autor/Titel.epub um."
    )
    parser.add_argument("source", type=Path, help="Quellverzeichnis mit EPUBs")
    parser.add_argument("target", type=Path, help="Zielverzeichnis für die Hierarchie")
    parser.add_argument(
        "--api-key",
        default=os.environ.get("MISTRAL_API_KEY"),
        help="Mistral API-Key (Standard: Umgebungsvariable MISTRAL_API_KEY)",
    )
    parser.add_argument(
        "--model",
        default="mistral-small-latest",
        help="Mistral-Modell (Standard: mistral-small-latest)",
    )
    parser.add_argument(
        "--copy",
        action="store_true",
        help="Dateien kopieren statt verschieben",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Nur anzeigen, was passieren würde; keine Dateien bewegen",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=1.0,
        help="Pause in Sekunden zwischen API-Aufrufen (Standard: 1.0)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        help="Nur die ersten N Bücher verarbeiten (zum Testen)",
    )
    args = parser.parse_args()

    if not args.api_key:
        parser.error("Kein API-Key: --api-key angeben oder MISTRAL_API_KEY setzen.")
    if not args.source.is_dir():
        parser.error(f"Quellverzeichnis nicht gefunden: {args.source}")

    source = args.source.resolve()
    target = args.target.resolve()

    epubs = find_epubs(source, target)
    if args.limit:
        epubs = epubs[: args.limit]
    if not epubs:
        print("Keine EPUBs gefunden.")
        return

    print(f"{len(epubs)} EPUBs gefunden in {source}")
    if args.dry_run:
        print("Trockenlauf – es werden keine Dateien bewegt.\n")

    moved, skipped, failed = 0, 0, []
    for index, path in enumerate(epubs, start=1):
        prefix = f"[{index}/{len(epubs)}]"
        rel = path.relative_to(source)
        try:
            meta, sample = read_epub(path)
        except Exception as err:
            print(f"{prefix} FEHLER  {rel} – EPUB nicht lesbar: {err}")
            failed.append((path, f"EPUB nicht lesbar: {err}"))
            continue

        try:
            raw = call_mistral(
                args.api_key, args.model, build_user_prompt(path, meta, sample)
            )
            genre, last, first, title = parse_classification(raw)
        except SystemExit:
            raise
        except Exception as err:
            print(f"{prefix} FEHLER  {rel} – Klassifikation fehlgeschlagen: {err}")
            failed.append((path, f"Klassifikation fehlgeschlagen: {err}"))
            time.sleep(args.delay)
            continue

        if not title:
            title = meta["title"] or path.stem

        destination = build_target(target, genre, last, first, title)
        rel_dest = destination.relative_to(target)

        if destination == path:
            print(f"{prefix} OK      {rel} ist bereits richtig einsortiert")
            skipped += 1
        else:
            final = resolve_collision(path, destination)
            if final is None:
                print(f"{prefix} DUPLIKAT {rel} – existiert bereits als {rel_dest}")
                skipped += 1
            else:
                verb = "KOPIERE" if args.copy else "VERSCHIEBE"
                print(f"{prefix} {verb} {rel} -> {final.relative_to(target)}")
                if not args.dry_run:
                    final.parent.mkdir(parents=True, exist_ok=True)
                    if args.copy:
                        shutil.copy2(path, final)
                    else:
                        shutil.move(str(path), str(final))
                moved += 1

        time.sleep(args.delay)

    print(f"\nFertig: {moved} einsortiert, {skipped} übersprungen, "
          f"{len(failed)} fehlgeschlagen.")
    if failed:
        print("\nFehlgeschlagene Dateien:")
        for path, reason in failed:
            print(f"  {path}: {reason}")
        sys.exit(1)


if __name__ == "__main__":
    main()
