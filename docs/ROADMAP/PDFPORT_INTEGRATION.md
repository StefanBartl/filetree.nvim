# Konzept: pdfport.nvim × filetree.nvim × Filetree-Manager

> Zuständigkeits-Aufteilung für das „PDF aus dem Tree öffnen"-Feature.
> Status: Konzept / Entscheidungsvorlage. Betrifft `filetree.nvim` (neues Feature)
> und `pdfport.nvim` (keine Pflicht­änderung).

---

## 1. Das Problem: doppelte Tree-Abstraktion

Beide Plugins lösen heute **unabhängig dieselbe Aufgabe** — „gib mir den Pfad des
Nodes unter dem Cursor in Filetree X":

| Plugin          | Ort                                            | Mechanismus                          |
| --------------- | ---------------------------------------------- | ------------------------------------ |
| `pdfport.nvim`  | `integrations/{neotree,nvim_tree,netrw,oil}.lua` + `integrations/init.lua` | `current_pdf_path()` per `filetype`-Switch |
| `filetree.nvim` | `adapter/{neotree,nvimtree,netrw,oil,mini_files}.lua` | `FiletreeAdapter.get_current_node()` (echter Port) |

`pdfport` erfindet damit — schlechter, per `ft ==`-Verzweigung — neu, was
`filetree` bereits als sauberen Port/Adapter besitzt. Sobald ein weiterer Tree
dazukommt, muss er an **zwei** Stellen gepflegt werden. Diese N×2-Matrix ist die
Redundanz, die wir auflösen.

---

## 2. Zielarchitektur: Port/Adapter, erweitert

Deine Vermutung ist korrekt. Drei Ebenen mit klaren, nicht-überlappenden Rollen:

```
┌──────────────────────────────────────────────────────────────────┐
│  pdfport.nvim  —  CORE / Domänenlogik                             │
│  "Öffne/konvertiere PDF an Pfad P"                                │
│  fallback_chain: pdftotext → pdfplumber → marker → … → claude     │
│  Public API:  require("pdfport_nvim").open{ path=P, mode=… }      │
│  ▸ weiß NICHTS von Filetrees (für den filetree-Pfad)             │
└──────────────────────────────────────────────────────────────────┘
                              ▲  optionaler require (pcall)
                              │
┌──────────────────────────────────────────────────────────────────┐
│  filetree.nvim  —  PORT + ADAPTER + BRIDGE                        │
│  ▸ adapter/*  : kennt jeden Tree (existiert bereits)             │
│  ▸ feature 'pdf_open' : Node-unter-Cursor → is_pdf? → pdfport    │
│    bindet Keymaps buffer-lokal am Tree-FileType                   │
└──────────────────────────────────────────────────────────────────┘
                              ▲  fertiges Feature / Keymap
                              │
┌──────────────────────────────────────────────────────────────────┐
│  neotree / nvimtree / oil / …  —  HOST                            │
│  empfängt das fertige Feature, weiß sonst nichts davon            │
└──────────────────────────────────────────────────────────────────┘
```

**Kernidee:** `filetree.nvim` bekommt ein neues Feature `pdf_open` — Bauart
identisch zum bestehenden `open_with` (`features/system/open_with/init.lua`). Es
nutzt **den vorhandenen Adapter** für den Node-Pfad (kein `filetype`-Switch mehr!)
und ruft **nur die Core-API** von pdfport auf.

---

## 3. Abhängigkeitsrichtung

* `filetree.nvim` → **optional** `pdfport.nvim` (via `pcall(require, "pdfport_nvim")`).
  Kein Hard-Dep. Fehlt pdfport, ist das Feature ein No-Op (Health-Warnung, wenn
  explizit `enabled = true`). Gleiches Soft-Dep-Muster wie markdown.nvim in
  color_my_ascii.
* `pdfport.nvim` → **hängt an nichts** aus filetree. Bleibt eigenständig
  (Telescope/fzf/eigene Tree-Integrationen für Standalone-User).

Der Pfeil, den du vorgeschlagen hast (`filetree → pdfport als Dependency`), ist
also richtig — aber **optional**, einseitig, und filetree ruft ausschließlich
`pdfport_nvim.open{}` auf, **nicht** `pdfport.neotree()` / `.integrations()`.

---

## 4. Was bleibt wo (Zuständigkeitsmatrix)

| Concern                                                   | Owner                                     |
| -------------------------------------------------------- | ----------------------------------------- |
| PDF → Text/Render, `fallback_chain`, Backends            | **pdfport.nvim** core                     |
| „Welcher Node liegt unter dem Cursor in Tree X"          | **filetree.nvim** adapter (existiert)     |
| „Cursor-auf-PDF → mit pdfport öffnen" + Keymaps im Tree  | **filetree.nvim** feature `pdf_open` (neu)|
| pdfport **standalone** im Tree (ohne filetree.nvim)      | **pdfport.nvim** `integrations/*` (bleibt)|
| Dummer Host sein                                          | neotree / nvimtree / …                    |

Wichtig: die `integrations/*`-Module in pdfport **bleiben erhalten** — sie sind
der Komfort für User, die pdfport **ohne** filetree.nvim in einem Tree nutzen.
filetree-User nutzen sie nicht; sie bekommen `pdf_open`.

---

## 5. Die Sorge mit der fallback_chain (dein Punkt 2 & 3)

> „nicht jeder filetree-User will pdftotext/marker/docling/ollama/claude installieren"

Muss er nicht:

1. **pdfport ist selbst optionale Dependency.** Wer pdfport nie installiert,
   bekommt das Feature einfach nicht — null Zusatz-Tools.
2. **filetree gibt keine Backends vor.** `pdf_open` ruft nur `.open{path, mode}`;
   *welche* Backends greifen, entscheidet allein pdfports eigenes `setup()`.
   filetree kennt die Chain nicht einmal.
3. **Default = `mode = "system"`** → öffnet im OS-PDF-Viewer, braucht kein
   einziges externes CLI. Text-Extraktion (`mode = "buffer"`) ist opt-in pro
   Keymap. Damit ist „default aktiv, aber nur mit hauseigenen Mitteln; einzelne
   Tools opt-in" exakt erfüllt. Und pdfports Chain degradiert ohnehin graziös.

---

## 6. Config-Oberfläche in filetree.nvim

```lua
require("filetree").setup({
  features = {
    pdf_open = {
      enabled      = true,        -- inert, falls pdfport.nvim fehlt
      default_mode = "system",    -- "system"|"buffer"|"float"|"terminal"
      keymaps = {
        open     = "P",           -- Default-Aktion = default_mode
        text     = false,         -- Text-Extraktion in Buffer (braucht Text-Backend)
        system   = false,
        terminal = false,
      },
    },
  },
})
```

filetree reicht `mode`/`backend_id` **durch** an pdfport, benennt aber nie ein
Backend selbst.

### Optionale Kür: Handler-Port statt fester pdfport-Kopplung

Für reines Hexagonal: `pdf_open` definiert einen winzigen „PDF-Handler-Port".
Default-Handler = `pcall` auf pdfport; ein User könnte via Config einen eigenen
`open = function(path, opts) … end` injizieren. Spiegelt filetrees Adapter-Philo­
sophie. Der `pcall`-pdfport-Default ist der pragmatische Kern; der Port ist die
Erweiterung, falls je ein zweites PDF-Backend auftaucht.

---

## 7. Implementierungs-Skizze `features/system/pdf_open/init.lua`

Analog zu `open_with` (gleiche `setup(config, adapter)`-Signatur, gleiche
FileType-Keymap-Registrierung):

```lua
local _adapter, _cfg = nil, { enabled = false, default_mode = "system", keymaps = {} }

local function current_pdf()
  if not _adapter then return nil end
  local node = _adapter.get_current_node()            -- ← Port, kein ft-Switch
  local path = node and node.path or nil
  if path and path:lower():match("%.pdf$") then return path end
  return nil
end

local function open(mode)
  local path = current_pdf()
  if not path then notify.warn("Kein PDF unter dem Cursor"); return end
  local ok, pdfport = pcall(require, "pdfport_nvim")   -- ← optionale Dependency
  if not ok then notify.warn("pdfport.nvim nicht installiert"); return end
  pdfport.open({ path = path, mode = mode or _cfg.default_mode })
end

function M.setup(config, adapter)
  if not config.enabled then return end
  _cfg, _adapter = vim.tbl_deep_extend("force", _cfg, config), adapter
  -- FileType-Autocmd auf _adapter.filetypes → keymaps buffer-lokal binden
  -- (Muster 1:1 aus open_with übernehmen)
end
```

Vorteil gegenüber pdfports heutigem `integrations/init.lua`: **keine einzige
Tree-spezifische Zeile** — `get_current_node()` abstrahiert neotree/nvimtree/
oil/… bereits weg. Ein neuer Tree = ein neuer filetree-Adapter, sonst nichts.

---

## 8. Migrationsschritte

1. **nvim-Config**: alte pdfport-Neotree-Wiring ist bereits entfernt
   (`config/neotree/keymaps/filesystem/init.lua` dokumentiert das; das frühere
   `…/filesystem/pdfport.lua` existiert nicht mehr). ✔ nichts zu tun.
2. **filetree.nvim**:
   - `lua/filetree/features/system/pdf_open/init.lua` anlegen.
   - In `features/init.lua` registrieren: `pdf_open = { mod = "…system.pdf_open", category = "system" }`.
   - `@types` + `config/DEFAULTS.lua` (Default `enabled = false` oder `true`+inert — s. u.).
   - `health.lua`: warnen, wenn `pdf_open.enabled` aber `pdfport_nvim` fehlt.
   - `cheatsheet`-Feature zeigt die neuen Keys im `?`-Overlay automatisch (prüfen).
   - Docs: `BINDINGS/KEYMAPS.md` + README (optionale pdfport-Dependency).
3. **pdfport.nvim**: keine Pflichtänderung. Optional README-Hinweis: „filetree.nvim-
   User aktivieren `pdf_open` statt pdfports Neotree-Integration zu verdrahten."

### Umgesetzte Entscheidungen (Stand Implementierung)

* **`enabled` default = ON** (nicht in `DEFAULT_DISABLED`), passt zum opt-out-Modell
  und zu „default aktiv". Ohne pdfport bleibt es nutzbar (System-Viewer-Fallback).
* **`default_mode = "buffer"`** (leichte Abweichung vom ursprünglichen Vorschlag
  „system"): die Kern-Wertschöpfung von pdfport ist die Textextraktion in nvim.
  Ohne pdfport fällt der Opener automatisch auf den OS-Viewer zurück → „zero-dep
  funktioniert" bleibt erfüllt. `default_mode = "system"` ist per Config ein
  Einzeiler, wer den reinen Viewer will.
* **Default-Keymap `gp`** („get pdf") für `default_mode`; text/system/terminal sind
  opt-in (default off). `gp` kollidiert mit keiner bestehenden Belegung
  (`P` ist von `copy_move` belegt).

### Gemeinsamer Opener statt verstreuter pdfport-Calls

Die Bridge lebt in **`filetree.util.pdf`** (`open(path, opts)` / `system_open` /
`is_pdf` / `has_pdfport`). Sie kapselt den korrekten `require("pdfport_nvim")` und
die **Table**-Signatur `pp.open({ path, mode, … })`. Zwei Konsumenten:

* das neue `pdf_open`-Feature, und
* das bestehende `preview`-Feature (`<Tab>`/`<CR>`-Dispatch).

> **Nebenfund/Fix:** `preview/open_pdf` war doppelt kaputt — `require("pdfport")`
> (Modul heißt `pdfport_nvim`, kein Shim vorhanden) und `pp.open(path)` (String
> statt Table). Es fiel dadurch bei *jeder* PDF still auf den System-Viewer zurück.
> Durch die Umstellung auf `filetree.util.pdf` ist beides behoben.

---

## 9. Warum das die richtige Aufteilung ist

* **Eine** Tree-Abstraktion statt zwei (filetrees Adapter gewinnt, pdfports
  ft-Switch entfällt für filetree-User).
* pdfport bleibt **framework-frei** und standalone-nutzbar (Telescope/fzf/eigene
  Integrationen unangetastet).
* filetree gewinnt beliebig viele Trees für das Feature „gratis" dazu — jeder
  neue Adapter bringt `pdf_open` automatisch mit.
* Neue PDF-Backends? Nur pdfport-Sache. Neue Trees? Nur filetree-Sache. Der Host
  bleibt dumm. Saubere, einseitige, **optionale** Kopplung.
