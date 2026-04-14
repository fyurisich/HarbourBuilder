# iOS Sample Project

A simple iOS application built with Harbour using the UI_* native UIKit API.

## Files

- **Project1.prg** - Main program with iOSApp class
- **Form1.prg** - TFormIOS class demonstrating form layout

## Building

From the project directory:

```bash
# Build for simulator
/Users/usuario/HarbourBuilder/source/backends/ios/build-ios-app.sh Project1.prg simulator

# Build for device
/Users/usuario/HarbourBuilder/source/backends/ios/build-ios-app.sh Project1.prg device
```

## Running on Simulator

```bash
/Users/usuario/HarbourBuilder/source/backends/ios/install-and-run.sh
```

## UI_* API

The iOS backend implements the same UI_* API as the Android backend:

| Function | Description |
|----------|-------------|
| `UI_FormNew(cTitle, nW, nH)` | Create form (UIViewController) |
| `UI_LabelNew(hParent, cText, nX, nY, nW, nH)` | Create UILabel |
| `UI_ButtonNew(hParent, cText, nX, nY, nW, nH)` | Create UIButton |
| `UI_EditNew(hParent, cText, nX, nY, nW, nH)` | Create UITextField |
| `UI_SetText(hCtrl, cText)` | Set control text |
| `UI_GetText(hCtrl)` | Get control text |
| `UI_OnClick(hCtrl, bBlock)` | Set click handler |
| `UI_SetFormColor(nClr)` | Set form background (BGR) |
| `UI_SetCtrlColor(hCtrl, nClr)` | Set control background (BGR) |
| `UI_SetCtrlFont(hCtrl, cFamily, nSize)` | Set font |
| `UI_FormRun(hForm)` | Start event loop (no-op on iOS) |

Colors use Win32 COLORREF format (0x00BBGGRR).
