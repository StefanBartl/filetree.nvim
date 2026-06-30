# filetree.nvim — Integration Test Guide

Manueller Testlauf: neotree + filetree.nvim ohne echte User-Config.
T
---

## Setup

```
cd e:/repos/filetree.nvim
nvim --clean -u test/minimal_neotree.lua .
```

Beim ersten Start lädt lazy.nvim neo-tree und alle Abhängigkeiten in
`%TEMP%/filetree-test/`. Das dauert ~30 Sekunden. Danach startet nvim mit
dem Repo-Root als Working Directory.

**State-Dir:** `%TEMP%/filetree-test/` (Windows) / `/tmp/filetree-test/` (Unix)  
Um sauber neu zu starten, diesen Ordner löschen.

---

## Globale Test-Keymaps

| Key           | Aktion                                         |
|---------------|------------------------------------------------|
| `<C-e>`       | neo-tree auf-/zuklappen                        |
| `<leader>e`   | aktuelle Datei im Baum anzeigen (reveal)       |
| `<leader>H`   | `:checkhealth filetree` öffnen                 |
| `<leader>fa`  | aktiven Adapter in Notification ausgeben       |
| `<leader>fn`  | aktuellen Tree-Node als `vim.inspect()` ausgeben (Cursor muss im Tree sein) |

---

## Checkliste

### 0. Grundstruktur — bevor irgendetwas anderes

| # | Test | Erwartung | Ergebnis |
|---|------|-----------|----------|
| 0.1 | `:checkhealth filetree` | Alle Adapter-Zeilen OK/WARN, keine ERROR; alle Features als "enabled" oder "not configured" | |
| 0.2 | `<leader>fa` | `"Active adapter: neotree"` in der Notification | |
| 0.3 | `<C-e>` → Tree öffnet sich, dann `<leader>fn` | Node-Table erscheint: `{ id = "...", name = "...", type = "file"|"directory", path = "...", ... }` | |
| 0.4 | `<leader>fn` ohne Tree offen | Notification: `"No node under cursor"` (kein Fehler, kein Stack-Trace) | |

---

### A. Adapter-Basics — current_hl

Testet: `get_current_node()`, `get_visible_nodes()`, Extmarks.

| # | Test | Erwartung |
|---|------|-----------|
| A.1 | Tree öffnen (`<C-e>`), Cursor in Tree bewegen | Aktuelle Zeile hat `CursorLine`-Highlight; übergeordnetes Verzeichnis hat `Visual`-Highlight |
| A.2 | Cursor im Tree hoch/runter (`j`/`k`) | Highlight folgt dem Cursor mit leichter Verzögerung (debounce 100 ms) |
| A.3 | Tree schließen, in Editor öffnen, andere Datei öffnen | Beim nächsten Tree-Öffnen ist das Highlight auf der aktuellen Datei |

---

### B. CWD / Reveal

Testet: Autocmds, `adapter.open_reveal()`.

| # | Test | Erwartung |
|---|------|-----------|
| B.1 | Datei öffnen (`:e lua/filetree/init.lua`) | Tree scrollt automatisch zur Datei (auto_reveal) |
| B.2 | Nach B.1: `:pwd` im Editor | Zeigt das Verzeichnis der zuletzt geöffneten Datei (cwd_sync) |
| B.3 | `<leader>e` wenn Cursor auf einer Datei im Editor | Tree öffnet sich und zeigt die aktuelle Datei markiert |
| B.4 | Datei in Unterordner öffnen | cwd wechselt zum Ordner der Datei; Tree zeigt Ordner im Fokus |

---

### C. Virtual Text / Extmarks — marks + git_status

Testet: `nvim_buf_set_extmark`, EOL-Virt-Text.

**marks** (Keymap `m` im Tree):

| # | Test | Erwartung |
|---|------|-----------|
| C.1 | Cursor auf Datei im Tree, `m` drücken | `✓` erscheint am Ende der Zeile (EOL, grün) |
| C.2 | `m` auf derselben Datei nochmal | `✓` verschwindet (Toggle) |
| C.3 | Mehrere Dateien markieren | Alle zeigen `✓` gleichzeitig |
| C.4 | Tree schließen und wieder öffnen | Marks sind weg (keine Persistenz erwartet — das ist richtig) |

**git_status** (automatisch, kein Keymap nötig):

| # | Test | Erwartung |
|---|------|-----------|
| C.5 | Datei editieren und speichern (`:w`) | Nach ~300 ms erscheint `~` (modified) am Ende der Tree-Zeile |
| C.6 | Neue Datei anlegen (`:e test/newfile.lua`, `:w`) | Zeigt `?` (untracked) im Tree |
| C.7 | `git add` in Terminal, dann Tree-Cursor bewegen | Zeigt `+` (staged) |

---

### D. Floating Windows — node_info + preview

Testet: `nvim_open_win`, Buffer-Keymaps, Close-on-q.

**node_info** (Keymap `I` im Tree):

| # | Test | Erwartung |
|---|------|-----------|
| D.1 | Cursor auf Datei, `I` drücken | Floating Window erscheint mit: Pfad, Typ, Größe (bytes + MiB), Permissions, mtime, Zeilenanzahl |
| D.2 | `q` oder `<Esc>` im Float | Fenster schließt sich |
| D.3 | `I` nochmal auf derselben Datei drücken | Fenster schließt sich (Toggle: gleicher Pfad = close) |
| D.4 | `I` auf Verzeichnis | Float zeigt Typ `directory`, keine Zeilenanzahl |
| D.5 | `I` auf sehr große Datei (>5 MB) | Zeilenanzahl steht auf `(skipped — file too large)` |

**preview** (Keymap `<Tab>` im Tree — Default seit Phase 4):

| # | Test | Erwartung |
|---|------|-----------|
| D.6 | Cursor auf Lua-Datei, `<Tab>` drücken | Floating Window mit Dateiinhalt (max 100 Zeilen) |
| D.7 | `q` schließt den Preview | |

---

### E. Input / Search — filter + live_search

Testet: `vim.ui.input`, Floating-Prompt-Buffer, Dimming.

**filter** (Keymap `/` im Tree):

| # | Test | Erwartung |
|---|------|-----------|
| E.1 | `/` im Tree drücken | Floating Input-Prompt erscheint |
| E.2 | `init` eintippen + Enter | Nicht-passende Nodes erscheinen gedimmt (Comment-Highlight) |
| E.3 | `:Filetree filter clear` | Dimming aufgehoben, alle Nodes normal |

**live_search** (Keymap `gs` im Tree):

| # | Test | Erwartung |
|---|------|-----------|
| E.4 | `gs` im Tree drücken | Floating Prompt-Buffer am unteren Rand des Trees |
| E.5 | Tippen | Nicht-passende Nodes werden live gedimmt (Debounce ~80 ms) |
| E.6 | `<Esc>` | Prompt schließt sich, Dimming aufgehoben |
| E.7 | Enter | Filter bleibt (commit_to_filter = true) |

---

### F. Clipboard / Copy

Testet: `vim.fn.setreg`, Notifications.

**path_copy** (Keymaps `<leader>yp`/`[a`/`]a`/`<leader>yn` im Tree):

| # | Test | Erwartung |
|---|------|-----------|
| F.1 | `<leader>yp` | Floating Picker mit 7 Format-Optionen |
| F.2 | `[a` | Notification: `"Copied: /absolute/path"`, im Editor `<C-r>+` einfügen bestätigt es |
| F.3 | `]a` | Relativer Pfad zum cwd |
| F.4 | `<leader>yn` | Nur Dateiname |

**copy_file_list** (Keymaps `[f`/`]f`/`[F`/`]F` im Tree):

| # | Test | Erwartung |
|---|------|-----------|
| F.5 | Cursor auf Verzeichnis, `[f` | Notification mit Preview der ersten 5 Datei-Pfade (absolut); `<C-r>+` im Editor zeigt alle Pfade |
| F.6 | `]f` | Relative Pfade |
| F.7 | `[F` / `]F` | Nur Verzeichnisse (rekursiv) |
| F.8 | `[f` auf einer Datei (nicht Verzeichnis) | Nur diese eine Datei (kein Fehler) |

**lua_require_copy** (Keymap `rq` im Tree):

| # | Test | Erwartung |
|---|------|-----------|
| F.9 | Cursor auf `lua/filetree/init.lua`, `rq` | Clipboard enthält `require('filetree')` |
| F.10 | Cursor auf `lua/filetree/features/marks/init.lua`, `rq` | `require('filetree.features.marks')` |
| F.11 | Cursor auf Verzeichnis `lua/filetree/features/`, `rq` | Alle Lua-Module des Verzeichnisses in Clipboard |

---

### G. Navigation — tree_traverse

Testet: `adapter.open_reveal()`, CWD-Sync.

| # | Test | Erwartung |
|---|------|-----------|
| G.1 | Tree-Cursor auf Datei/Ordner, `-` | Tree-Root wechselt zum übergeordneten Verzeichnis; Notification `"cwd → /parent"` |
| G.2 | Tree-Cursor auf Verzeichnis, `+` | Verzeichnis wird neuer Root |
| G.3 | `:pwd` nach G.1/G.2 | CWD stimmt mit dem neuen Tree-Root überein |
| G.4 | `-` aus dem Repo-Root heraus | Wechselt zum Parent des Repos (kein Fehler) |

---

### H. Find / Grep Menu

Testet: `vim.ui.select`-Fallback, telescope/fzf-Cascade.

| # | Test | Erwartung |
|---|------|-----------|
| H.1 | Cursor auf Verzeichnis im Tree, `<M-p>` | `vim.ui.select`-Picker mit 2 Optionen: `find_files` / `live_grep` |
| H.2 | Option `find_files` auswählen | Telescope (oder fzf-lua, oder vim.ui.select) öffnet sich mit cwd = das Verzeichnis |
| H.3 | Option `live_grep` | Grepper öffnet sich mit cwd = das Verzeichnis |
| H.4 | `<M-p>` auf Datei (nicht Verzeichnis) | Verwendet den Parent-Ordner der Datei als cwd |
| H.5 | Option `find_files` → kein Picker installiert | Input-Prompt erscheint: `"Filename pattern: "`, nach Eingabe zeigt `vim.ui.select` die Treffer |

---

### I. Phase 3 — Remapping-System

Um diese Tests zu aktivieren, die auskommentierten Blöcke in `minimal_neotree.lua` einkommentieren.

**I.1 — Keymap remap (`keymaps = { ["gs"] = "<leader>gs" }`):**

| # | Test | Erwartung |
|---|------|-----------|
| I.1 | `gs` im Tree drücken | Kein Live-Search (Key wurde umgemappt) |
| I.2 | `<leader>gs` im Tree drücken | Live-Search öffnet sich |

**I.2 — Keymap disable (`keymaps = { ["I"] = false }`):**

| # | Test | Erwartung |
|---|------|-----------|
| I.3 | `I` im Tree drücken | Nichts passiert (kein node_info Float) |
| I.4 | `:Filetree info` | Float öffnet sich (Command funktioniert weiterhin) |

**I.3 — Command rename (`command = { name = "Ft", aliases = { "Filetree" } }`):**

| # | Test | Erwartung |
|---|------|-----------|
| I.5 | `:Ft marks show` | Marks-Float öffnet sich |
| I.6 | `:Filetree marks show` | Funktioniert auch (Alias) |
| I.7 | Tab-Completion auf `:Ft<Tab>` | Sub-Commands werden angezeigt |

**I.4 — Autocmd disable (`autocmds = { auto_reveal = false }`):**

| # | Test | Erwartung |
|---|------|-----------|
| I.8 | Datei öffnen (`:e lua/filetree/init.lua`) | Tree scrollt NICHT zur Datei (auto_reveal deaktiviert) |
| I.9 | `<leader>e` | Reveal funktioniert noch (manuell via Command) |

---

### J. ignore_list + :Ft alias

**J.1 — ignore_list Standard (kein Config-Eintrag nötig, ist by default aktiv):**

| # | Test | Erwartung |
|---|------|-----------|
| J.1 | Tree öffnen | `.git` Ordner ist NICHT sichtbar (von Anfang an versteckt) |
| J.2 | `H` im Tree drücken | Alle versteckten Items (inkl. `.git`) werden eingeblendet |
| J.3 | `H` nochmal | Wieder ausgeblendet |

**J.2 — ignore_list deaktivieren (`ignore_list = false` in minimal_neotree.lua einkommentieren):**

| # | Test | Erwartung |
|---|------|-----------|
| J.4 | Tree öffnen | `.git` ist sichtbar |

**J.3 — ignore_list mit custom Liste (`ignore_list = { ".git", "node_modules" }`):**

| # | Test | Erwartung |
|---|------|-----------|
| J.5 | Tree öffnen | Nur `.git` und `node_modules` versteckt; andere Ordner (z.B. `build`) sichtbar |

**J.4 — :Ft Alias (immer aktiv, kein Config nötig):**

| # | Test | Erwartung |
|---|------|-----------|
| J.6 | `:Ft marks show` | Marks-Float öffnet sich (identisch zu `:Filetree marks show`) |
| J.7 | `:Ft<Tab>` | Tab-Completion zeigt Sub-Commands |

---

## Bekannte Einschränkungen dieser Test-Umgebung

- **Kein git-Blame**: braucht `git log`, funktioniert nur in echtem Git-Repo (das ist hier gegeben, solange der Test im Repo-Root gestartet wird)
- **Kein harpoon**: nicht installiert in dieser Config, harpoon_integration wird nicht getestet
- **POSIX-Features** (`file_permissions`): auf Windows no-op, nicht in Test-Config aktiviert
- **Telescope/fzf**: nicht installiert → find_or_grep_menu fällt auf `vim.ui.select` zurück (das ist das erwartete Verhalten)
- **Keine Persistenz** zwischen Sitzungen: `marks`, `bookmarks`, `session` etc. schreiben nach `%TEMP%/filetree-test/data/nvim/filetree/` — wird bei `rm -rf /tmp/filetree-test` geleert

---

## Typische Fehlerbilder

| Symptom | Wahrscheinliche Ursache |
|---------|------------------------|
| Keymaps im Tree nicht vorhanden | FileType-Autocmd hat nicht gefeuert — `:set ft?` im Tree-Buffer sollte `neo-tree` zeigen |
| `adapter = nil` bei `<leader>fa` | `setup()` fehlgeschlagen — `:checkhealth filetree` zeigt den Grund |
| EOL Virt-Text erscheint nicht | `get_visible_nodes()` gibt leere Liste zurück — `<leader>fn` prüfen ob `get_current_node()` überhaupt etwas liefert |
| Floating Window öffnet sich nicht | `nvim_open_win` Fehler — meist `width`/`height` = 0 weil Adapter-Methode nil zurückgab |
| `rq` kopiert falsches Modul | `/lua/` nicht im Pfad gefunden — Tree-Root-Pfad prüfen, muss unter einem `lua/`-Verzeichnis liegen |
