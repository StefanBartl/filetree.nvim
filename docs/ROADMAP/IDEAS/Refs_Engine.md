# Referenz-Engine — Refs beim Move/Rename mitziehen

Status: 🔲 Konzept. Teile davon existieren bereits (siehe Ist-Zustand), das Feature
ist also kein Greenfield, sondern eine **Vereinheitlichung + Ausbau**.

Idee (Originalformulierung): In `./README.md` steht eine Referenz auf `/Test.md`.
Ich verschiebe `Test.md` nach `/docs/Test.md` — filetree scannt das cwd nach
Referenzen, listet sie auf und fragt, ob alle / nur ausgewählte / keine
aktualisiert werden sollen. Erst Markdown, später Lua, später JS/TS.

---

## 1. Ist-Zustand (was schon im Repo steckt)

Wichtig, weil das Konzept unten kein neues Subsystem baut, sondern das
vorhandene generalisiert.

**Markdown-Refs — Pipeline existiert komplett**, in
[util/markdown_refs.lua](lua/filetree/util/markdown_refs.lua):

- `prefetch(path)` startet den Scan **bevor** mutiert wird (race-frei: die
  Mutation passiert erst im `await`-Callback, der Scan sieht die Datei also
  immer noch am alten Ort), `await_all()` für Batches.
- `retarget(ref, new_path)` bewahrt den Link-Stil (`./x` bleibt `./x`,
  absolut bleibt absolut), `relative_target()` als Fallback.
- `update(refs)` schreibt `](old)` → `](new)`, **content-verifiziert** (eine
  Zeile wird nur angefasst, wenn sie noch exakt das gescannte Target enthält),
  und patcht offene Buffer statt nur Disk.
- UX: `confirm_choice` → *Update all / Inspect first / Leave as-is*, "Inspect"
  öffnet [util/refs_picker.lua](lua/filetree/util/refs_picker.lua)
  (Telescope → fzf-lua → Quickfix-Fallback, Multi-Select via Tab/C-a).

Angebunden ist das an: [smart_rename](lua/filetree/features/fileops/smart_rename/init.lua),
[copy_move](lua/filetree/features/fileops/copy_move/init.lua) (nur `cut`, nicht `copy`),
[rename_batch](lua/filetree/features/fileops/rename_batch/init.lua),
[trash](lua/filetree/features/fileops/trash/init.lua) (dort: Refs als `REF!` markieren
bzw. Delete abbrechen).

**Code-Refs — existieren, aber nur halb**: `update_references_fallback()` in
[smart_rename/init.lua:396](lua/filetree/features/fileops/smart_rename/init.lua:396)
macht nach dem Rename einen ripgrep-Scan + textuellen Rewrite für **lua**
(`require`, inkl. Submodul-Kaskade bei Verzeichnis-Renames), **python**
(`from x import`) und **ts/js** (`from "./x"`, `import("./x")`) — als Fallback,
wenn kein LSP-Client `workspace/willRenameFiles` bedient hat (lua_ls tut das nie).

## 2. Die eigentlichen Lücken

1. **Zwei getrennte Welten.** Markdown-Refs haben Prefetch, Auswahl-UX, Picker,
   Buffer-Patching. Code-Refs haben nichts davon: sie laufen **still und
   ungefragt** durch, ohne Vorschau, ohne Auswahl, ohne Undo. Die UX, die du
   dir wünschst, existiert also — nur nicht für Code.
2. **Nur beim Rename.** Der Code-Ref-Rewrite hängt ausschließlich in
   `smart_rename`. Ein Move über `x`/`p` (copy_move) oder ein `rename_batch`
   zieht `require`-Pfade **nicht** mit.
3. **Markdown braucht eine Fremd-Plugin-Soft-Dep** (`markdown.nvim`,
   `find_references`). Ohne sie: `{}`, das Feature ist stumm aus. Für ein
   Kernfeature von filetree.nvim zu wenig.
4. **Kein dedizierter Move.** Verschieben geht nur zweistufig (`x` … navigieren
   … `p`). Ein `M` mit Ziel-Prompt fehlt.
5. **Link-Formen unvollständig.** `apply_ref` kann nur `](target)`. Nicht
   abgedeckt: Reference-Definitions (`[id]: pfad`), Wiki-Links, HTML
   (`<img src=…>`), Frontmatter-Pfade; Anchors (`](x.md#abschnitt)`) klappen nur
   zufällig, weil der Anchor Teil des Targets ist.

---

## 3. Zielbild: eine Ref-Engine mit Provider-Registry

Ein Modul `filetree.refs` als **einzige** Stelle, die weiß:
"Datei X wandert nach Y — wer zeigt auf X, und wie muss der Verweis danach lauten?"

```
                      ┌──────────────────────────────┐
  smart_rename ──┐    │  filetree.refs               │
  copy_move    ──┼──► │  scan → resolve → confirm →  │ ──► apply (Buffer/Disk)
  rename_batch ──┤    │  apply                       │
  trash        ──┘    └──────────┬───────────────────┘
                                 │ Provider-Registry
             ┌───────────────────┼────────────────────┬─────────────┐
          markdown              lua               python         ts/js
```

### Provider-Interface

```lua
---@class FiletreeRefProvider
---@field name string                          -- "markdown" | "lua" | ...
---@field handles fun(path: string): boolean   -- Ist diese Datei überhaupt referenzierbar?
---@field extensions string[]                  -- In welchen Dateien wird gesucht (rg -g)
---@field needles fun(old: string, root: string): string[]  -- Fixed-Strings für den rg-Vorfilter
---@field extract fun(file: string, lines: string[], old: string, root: string): FiletreeRef[]
---@field retarget fun(ref: FiletreeRef, new: string): string
```

```lua
---@class FiletreeRef
---@field file string       -- Datei, die den Verweis enthält (absolut)
---@field line integer      -- 1-basiert
---@field col? integer
---@field text string       -- Zeileninhalt zum Scan-Zeitpunkt (Content-Verify)
---@field target string     -- Verweis, wie er dasteht ("./Test.md", "foo.bar")
---@field new_target string -- von retarget() gesetzt
---@field provider string
---@field display string    -- für den Picker
```

Das Datenmodell ist bewusst **fast identisch** zu dem, was `markdown_refs`
heute von markdown.nvim bekommt (`file/line/target/display`) — bestehende
Aufrufer und der `refs_picker` funktionieren mit minimalem Umbau weiter.

### Pipeline (für jede FS-Mutation gleich)

1. **Prefetch** beim Tastendruck — `refs.prefetch({paths}, opts)` → Handle.
   Läuft, während der User tippt/navigiert. Mechanik aus
   `markdown_refs.prefetch/await_all` 1:1 übernommen.
2. **Scan** in zwei Stufen: `rg --files-with-matches --fixed-strings` mit den
   Provider-`needles` als grober Vorfilter (schnell, ignoriert `.git`,
   `node_modules`, respektiert `.gitignore`), danach `extract()` pro Kandidat
   für die exakte Trefferliste mit Zeile/Spalte. Kein Vollscan des cwd.
3. **Mutation** (rename/move) — im `await`-Callback, also garantiert nach dem Scan.
4. **Resolve** — `retarget(ref, new_path)` pro Ref, stil-erhaltend.
5. **Confirm** — ein Chooser über *alle* Provider zusammen:
   `"7 Referenzen in 4 Dateien (5 markdown, 2 lua)"` →
   **Alle aktualisieren / Auswählen / Diff ansehen / Nichts tun**.
6. **Apply** — gruppiert pro Datei, content-verifiziert; offene Buffer werden
   live gepatcht (Logik aus `markdown_refs.update()` hochziehen), unmodifizierte
   Buffer `noautocmd` zurückgeschrieben, modifizierte bleiben modified.

### Undo

Neu und wichtig, sobald mehr als Markdown angefasst wird: `refs.apply()` gibt ein
Undo-Token zurück (betroffene Dateien + Original-Zeilen). `:Filetree refs undo`
rollt den letzten Apply zurück. Bei offenen Buffern reicht deren natives Undo;
für Disk-Dateien braucht es das Token. Vorbild:
[trash/undo.lua](lua/filetree/features/fileops/trash/undo.lua).

---

## 4. UX: der `M`-Move

Neues Feature `fileops/move` — eigenes Modul statt Keymap in `copy_move`, weil
der Ziel-Prompt nichts mit der Clipboard-Logik zu tun hat:

```
M   → Prefetch startet sofort für Node (oder alle Marks)
    → kit.input "Move to: " mit Completion auf Verzeichnisse (default: cwd-relativ)
    → Konflikt-Check (Overwrite / Keep both / Cancel — Logik aus copy_move wiederverwenden)
    → fsops.rename_file()   (zentraler Mutations-Chokepoint, Windows-Retry inklusive)
    → buffer.relocate()
    → refs-Pipeline Schritt 4–6
```

Der Chooser danach:

```
  7 reference(s) to Test.md in 4 file(s)
    ▸ Update all
    ▸ Select…            → refs_picker (Tab/C-a Multi-Select, Preview)
    ▸ Show diff          → Scratch-Buffer, unified diff aller Änderungen
    ▸ Leave as-is
```

"Select…" ist laut deiner Einschätzung der seltenste Fall — deshalb Option 2,
nicht Option 1, und ohne eigenen Keymap-Shortcut.

---

## 5. Provider-Ausbau in Phasen

### Phase 1 — Markdown, in-tree

Eigener Scanner; `markdown.nvim` wird von der Voraussetzung zum Beschleuniger
(wenn vorhanden, weiter dessen `find_references` benutzen — das Interface passt).
Abzudecken:

| Form | Beispiel |
|---|---|
| Inline-Link | `[text](./Test.md)` |
| Image | `![alt](./img/x.png)` |
| Anchor/Title | `[t](./Test.md#kapitel "Titel")` |
| Reference-Def | `[id]: ./Test.md` |
| Wiki-Link | `[[Test]]`, `[[Test|Alias]]` (opt-in, nicht Standard-Markdown) |
| HTML im MD | `<img src="./img/x.png">`, `<a href="…">` |

Wichtig beim Matching: Target **relativ zur referenzierenden Datei** auflösen,
dann auf absoluten Pfad normalisieren und mit `old_path` vergleichen — nicht
textuell. Sonst matcht `../Test.md` aus `docs/` nicht, und `Test.md` matcht
fälschlich in jedem Unterverzeichnis. Auf Windows: `path.slashify` +
case-insensitiver Vergleich.

Zusätzlich **Verzeichnis-Move**: jede Ref, deren aufgelöster Pfad unter dem
alten Verzeichnis liegt, wird umgeschrieben (Präfix-Match auf Segmentgrenze).

### Phase 2 — Lua

Der Rewrite existiert schon (`file_to_lua_module`, Submodul-Kaskade,
`require "x"` und `require("x")`). Zu tun:

- aus `smart_rename` in einen Provider herausziehen,
- `extract()` ergänzen, damit Treffer *mit Zeilennummer* rauskommen (heute wird
  blind gepatcht, deshalb gibt es keine Vorschau),
- damit automatisch auch für Move/Batch verfügbar,
- Kanten: `require` in Strings/Kommentaren, `pcall(require, "x")`,
  `vim.pack`/`lazy`-Specs mit Modulnamen, `package.path`-Sonderfälle.
  Der `lua/`-Root-Match ist bereits greedy auf das *letzte* `/lua/` — gut so.

### Phase 3 — Python

Ebenfalls vorhanden (`file_to_python_module`). Gleiche Behandlung wie Lua;
zusätzlich relative Imports (`from .x import y`) — heute nicht abgedeckt.

### Phase 4 — JS/TS

Bewusst zuletzt, weil hier die meiste Arbeit steckt:

- extensionslose Specifier, `/index`-Collapse, `.js`-Endung in ESM-Imports auf
  TS-Quellen, `.mjs`/`.cjs`,
- `tsconfig.json` `paths`/`baseUrl`-Aliase (`@/components/x`) — ohne die ist der
  Rewrite in modernen Projekten fast wertlos; also `tsconfig`/`jsconfig` parsen
  (inkl. `extends`) und Alias-Targets mit auflösen,
- `require()` (CJS), dynamisches `import()`, `export … from`,
- `package.json` `exports`/`imports` (`#internal/x`), Monorepo-Workspaces.

Realistischer Schnitt: **4a** = relative Specifier + `/index` + Extensions
(existiert im Kern schon), **4b** = tsconfig-Aliase. Alles darüber nur, wenn
kein LSP da ist — `tsserver` beherrscht `willRenameFiles` und ist dann ohnehin
die bessere Quelle. Genau dafür ist die Reihenfolge "LSP zuerst, textual als
Fallback" in `smart_rename` schon richtig gebaut.

---

## 6. Config-Schema

Ersetzt die heute pro Feature dreifach duplizierten `check_markdown_refs` /
`refs_picker_prefer` (siehe [@types/config.lua:254](lua/filetree/@types/config.lua:254),
`:401`, `:433`, `:569`) durch **einen** Block, den die Features referenzieren:

```lua
refs = {
  enabled   = true,
  providers = {
    markdown = true,
    lua      = true,
    python   = true,
    ts_js    = false,   -- opt-in, solange Phase 4b nicht steht
  },
  on_move   = "ask",    -- "ask" | "auto" | "off"
  on_rename = "ask",
  on_delete = "ask",    -- trash: Refs als REF! markieren
  copy      = false,    -- Kopien brechen nie eine Referenz
  picker    = "auto",   -- auto | telescope | fzf-lua | quickfix
  prefer_lsp = true,    -- willRenameFiles gewinnt, textual nur als Fallback
  scan = {
    root              = "project",  -- "project" | "cwd"
    respect_gitignore = true,
    max_files         = 5000,       -- darüber: warnen statt scannen
    timeout_ms        = 3000,
  },
  undo = true,
}
```

Migration: alte Keys werden weiter gelesen und mit Deprecation-Notiz auf den
neuen Block gemappt.

---

## 7. Risiken / Kanten

- **Race "Datei weg vor Scan"** — gelöst durch Prefetch/`await`; muss bei jedem
  neuen Aufrufer diszipliniert eingehalten werden.
- **Stale Refs** bei offenen, ungespeicherten Buffern — gelöst durch
  Content-Verify (`apply_ref` prüft die Zeile); für die Code-Provider ebenso zu
  übernehmen.
- **Performance** — rg-Vorfilter ist Pflicht; ohne `rg` degradiert das Feature
  auf "still aus" (heutiges Verhalten) statt auf einen Lua-Vollscan.
- **False Positives** in Code (Modulname in String/Kommentar). Genau deshalb ist
  die Vorschau/Auswahl bei Code-Refs wertvoller als bei Markdown.
- **Windows** — Separator und Case: `path.slashify` konsequent an allen
  Vergleichsstellen, Vergleiche case-insensitiv.
- **Symlinks** — seit `link_create` real möglich: Refs auf einen Symlink dürfen
  nicht auf dessen Ziel umgeschrieben werden.
- **Binär/große Dateien** — Extension-Whitelist des Providers schützt bereits.

---

## 8. Umsetzungsreihenfolge

| # | Schritt | Aufwand |
|---|---|---|
| 1 | `filetree.refs` + Provider-Registry + Ref-Datenmodell; `markdown_refs` als erster Provider dahinter (Verhalten unverändert) | M |
| 2 | Gemeinsame Confirm/Picker/Apply-Schicht + Undo-Token | M |
| 3 | Markdown-Provider in-tree (alle Link-Formen, Pfad-Auflösung statt Textvergleich) | M–L |
| 4 | Lua-Provider aus `smart_rename` herausgelöst, mit Zeilentreffern | S–M |
| 5 | `M`-Move-Feature (Ziel-Prompt, Konflikt-Reuse, Marks-Support) | S |
| 6 | Refs-Pipeline an `copy_move` (cut) und `rename_batch` für **alle** Provider | S |
| 7 | Config-Block `refs` + Migration alter Keys + Doku | S |
| 8 | Python-Provider (inkl. relativer Imports) | S |
| 9 | TS/JS Phase 4a, danach 4b (tsconfig-Aliase) | L |

## 9. Tests

[TESTS/smart_rename_refs](TESTS/smart_rename_refs) existiert bereits mit Fixtures —
das Muster ausbauen: pro Provider ein Fixture-Baum, Tabellen-Test
`(altes Layout, Move, erwartetes Layout)`, plus Negativfälle (Ref in Kommentar,
gleichnamiges Präfix `testfs.rem` vs. `testfs.rem_other`, Ref auf Symlink,
ungespeicherter Buffer mit verschobenen Zeilen).
