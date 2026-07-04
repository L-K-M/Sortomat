# Sortomat

Menüleisten-App für macOS, die Ordner überwacht und neue Dateien anhand von
frei konfigurierbaren Regeln (Prompts) per Mistral-API einsortiert.

Jede Regel besteht aus: überwachtem Ordner, Zielordner, einer Sortier-Anweisung
in natürlicher Sprache und optional einem Dateiendungs-Filter. Für jede neue
Datei werden Name, Metadaten (inkl. Spotlight) und ein Inhaltsauszug (Text,
PDF, EPUB) an Mistral geschickt; das Modell antwortet mit einem Zielpfad
relativ zum Zielordner – oder «skip», wenn die Regel nicht zutrifft.

## Bauen & Installieren

```sh
./build.sh                      # erzeugt build/Sortomat.app (ad-hoc signiert)
cp -R build/Sortomat.app /Applications/
open /Applications/Sortomat.app
```

Autostart: Systemeinstellungen → Allgemein → Anmeldeobjekte → Sortomat hinzufügen.

Benötigt macOS 13+ und die Xcode Command Line Tools zum Bauen. Keine
externen Abhängigkeiten.

## Einrichten

1. Menüleisten-Symbol (Ablagekorb) → «Regeln & Einstellungen…»
2. Tab «Einstellungen»: Mistral API-Key eintragen (landet im Schlüsselbund).
3. Tab «Regeln»: Regel anlegen — Ordner wählen, Prompt schreiben, aktivieren.

Eine deaktivierte Beispielregel für E-Book-Sortierung
(`{Genre}/{Nachname, Vorname}/{Titel}.epub`, deutsche Genre-Liste) wird beim
ersten Start angelegt.

## Verhalten

- Ordner werden per Dispatch-Source sofort bei Änderungen geprüft, zusätzlich
  in einem konfigurierbaren Intervall (Standard 60 s) als Sicherheitsnetz.
- Dateien werden erst angefasst, wenn sie «stabil» sind (nicht in den letzten
  Sekunden verändert, Grösse konstant) – halbfertige Downloads bleiben liegen.
- Versteckte Dateien und Teil-Downloads (`.download`, `.crdownload`, `.part`, …)
  werden ignoriert; liegt der Zielordner im überwachten Ordner, wird er ausgenommen.
- Duplikate (gleicher Zielname und gleiche Grösse) werden nicht erneut bewegt;
  Namenskollisionen erhalten ` (2)`, ` (3)` ….
- Zielpfade vom Modell werden bereinigt (verbotene Zeichen, keine `..`-Segmente,
  originale Dateiendung wird erzwungen).
- Als «skip» klassifizierte oder fehlgeschlagene Dateien werden gemerkt und
  nicht bei jedem Scan erneut an die API geschickt (Fehler: erneuter Versuch
  nach 30 Minuten; Merkliste gilt pro App-Laufzeit).
- Aktivität: im Menü («Letzte Aktivität») und dauerhaft in
  `~/Library/Application Support/Sortomat/activity.log`.
- Konfiguration: `~/Library/Application Support/Sortomat/config.json`;
  der API-Key liegt im macOS-Schlüsselbund.

## Headless-Modus

```sh
MISTRAL_API_KEY=... ./build/Sortomat.app/Contents/MacOS/Sortomat scan-once
```

Verarbeitet alle aktiven Regeln einmal und beendet sich (Exit-Code 1 bei
Fehlern) – nützlich für Tests, Skripte oder launchd-Jobs.
`SORTOMAT_CONFIG_DIR` übersteuert das Konfigurationsverzeichnis.

## Datenschutz

Dateiname, Metadaten und ein Textauszug (bis ~4'000 Zeichen) jeder geprüften
Datei werden an die Mistral-API gesendet. Für Ordner mit sensiblen Dokumenten
keine Regel anlegen oder den Endungs-Filter entsprechend eng setzen.
