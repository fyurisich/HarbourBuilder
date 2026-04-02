---
name: Build and run commands for macOS
description: How to build and run HbBuilder IDE on macOS
type: reference
---

Project dir: `/Users/usuario/HarbourBuilder` (renamed from hbcpp)
Build: `cd /Users/usuario/HarbourBuilder/samples && ./build_mac.sh`
Run: `./HbBuilder &`

Source: `hbbuilder_macos.prg`
Harbour is at ~/harbour. Build requires clang/clang++ with -fobjc-arc for Cocoa sources.
Linker needs: -framework Cocoa -framework UniformTypeIdentifiers
