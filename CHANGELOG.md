# Changelog

## 2026-04-10

### Fixed
- TBrowse: HEADERS parser in RestoreFormFromCode consumed FOOTERS quoted strings,
  inflating column count on each save/load cycle until hitting MAX_BROWSE_COLS (16).
  Bounded extraction to stop before COLSIZES/FOOTERS keywords (Linux, macOS, Windows).
- TBrowse: added missing `FOOTERS` clause to `#xcommand BROWSE` in hbbuilder.ch so
  generated code with footers compiles without syntax errors.
- TBrowse: added `SetFooters()` method to TBrowse class for runtime footer assignment.
- RestoreFormFromCode: added missing `nCount` local declaration (W0001 warning fix).
- macOS bundle: synced hbbuilder.ch (added COLSIZES/FOOTERS) and classes.prg (SetFooters).
