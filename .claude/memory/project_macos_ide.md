---
name: HbBuilder IDE current state
description: HbBuilder visual IDE for Harbour — macOS Cocoa, C++Builder style, multi-form, two-way tools, Run pipeline
type: project
---

HbBuilder 1.0 — Visual development environment for Harbour (C++Builder inspired)

**Key files:**
- `samples/hbbuilder_macos.prg` — main IDE source (renamed from hbcpp_macos.prg)
- `samples/build_mac.sh` — build script, SRC=hbbuilder_macos, PROG=HbBuilder
- `backends/cocoa/cocoa_core.m` — Cocoa/AppKit: forms, controls, toolbar, palette, code editor, dialogs
- `backends/cocoa/cocoa_inspector.m` — Inspector: Properties/Events tabs, two-way sync callback
- `harbour/classes.prg` — TControl, TForm, TLabel, TEdit, TButton, TCheckBox, TComboBox, TGroupBox, TToolBar, TComponentPalette, TMenuPopup, TApplication
- `harbour/hbbuilder.ch` — xBase commands + C++Builder constants (renamed from commands.ch)
- `harbour/inspector_mac.prg` — Harbour inspector wrappers

**Architecture (4 windows):**
1. IDE Bar (APPBAR) — toolbar icons + component palette tabs
2. Object Inspector — combo + Properties/Events tabs + color/font pickers
3. Code Editor (dark theme) — tabs (Project1.prg + FormN.prg), syntax highlighting, gutter
4. Form Designer — dot grid, snap-to-grid 8px, overlay for selection/resize/drop

**Features implemented:**
- Multi-form projects: aForms array, File > New Form, View > Forms dialog
- Two-way tools: RegenerateFormCode reads live designer → updates code editor tab
- Component drop: palette click → crosshair → draw rect → create control + sync code
- Inspector edits → SyncDesignerToCode via INS_SetOnPropChanged callback
- Run (F9): save .prg → Harbour compile → clang C → link → Terminal.app launch
- Event handlers: double-click in Events tab → generate METHOD in CLASS
- TApplication: CreateForm calls form's CreateForm method, Run activates main form
- About dialog with Harbour ship logo

**How to apply:** Build: `cd samples && ./build_mac.sh`. Run: `./HbBuilder`.
