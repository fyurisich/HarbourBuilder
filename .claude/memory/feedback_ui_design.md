---
name: UI design preferences for IDE layout
description: Specific layout rules and pixel-level preferences for the hbcpp IDE on macOS
type: feedback
---

IDE follows Borland C++Builder classic layout with these rules:

**Main Bar (top)**
- Full screen width, borderless (NSWindowStyleMaskBorderless), no shadow
- Toolbar buttons: 32px height, NSBezelStyleSmallSquare, width fits text (min 32px)
- Palette component buttons in tabs: 52x50px, NSBezelStyleSmallSquare
- Tab selector (NSSegmentedControl): at the BOTTOM of the window, flush with bottom edge
- Splitter between toolbar and palette: 8px wide, draggable

**Inspector (left)**
- Width ~18% of screen minus adjustments
- Starts right below IDE bar (no gap)
- Has combo selector for controls at top
- Height does NOT need to match editor — currently 50px shorter than editor

**Code Editor (right, background)**
- Starts ~80px below IDE bar bottom (offset from inspector top)
- Extends to full screen bottom (no dock margin)
- Dark theme (VS Code style), syntax highlighting, line numbers
- Width: from inspector right edge to screen right edge

**Form Designer (floating)**
- Fixed size 400x300
- Centered horizontally in editor area
- Positioned at 35% vertical in editor area (above center, so code visible below)
- Floats ON TOP of the editor (created after editor, shown with Show())

**Menu accelerators**
- Do NOT use & in menu text (that's Windows convention)
- Use explicit ACCEL parameter: MENUITEM "New" OF oFile ACTION ... ACCEL "n"
- Standard macOS shortcuts: Cmd+N, Cmd+O, Cmd+S, Cmd+Z, Cmd+X, Cmd+C, Cmd+V, Cmd+F, Cmd+H, Cmd+R, Cmd+Q

**App naming**
- App menu shows "hbcpp"
- Binary: hbcpp_macos
- Source: hbcpp_macos.prg
- Window title: "hbcpp (GUI framework for Harbour)"
