# Android sample project

A minimal one-form project (Label + Edit + Button) that exercises the
Android backend end-to-end.

## Run it

1. Open `Project1.hbp` in HarbourBuilder (the Windows IDE, for now —
   macOS/Linux will follow when those backends gain the Android target).
2. Select **Run → Run on Android...**
3. The IDE will:
   - generate `source/backends/android/_generated.prg` from the form
   - build a signed `harbour-gui.apk`
   - boot the `HarbourBuilderAVD` emulator if needed
   - install the APK and launch the activity

You should see a native Android screen with:

- the **Label** `"Type your name:"`
- an **EditText** you can type into
- a **Button** `"Greet"` that updates the label to `"Hello, <name> !"`
  when tapped

## How the Android target works

The same `Form1.prg` runs on Win/macOS/Linux through `TForm` and on
Android through `UI_*` primitives. Coordinates in form-designer pixels
are scaled by `DisplayMetrics.density` on Android, so a 300×50 button
renders at the right physical size on any DPI.

See `docs/en/platform-android.html` for the full architecture.

## Prerequisites

- Android NDK r26d at `C:\Android\android-ndk-r26d\`
- Android SDK with build-tools 34 at `C:\Android\Sdk\`
- JDK 17 (Temurin portable) at `C:\JDK17\jdk-17.0.13+11\`
- AVD named `HarbourBuilderAVD` (Pixel 5, android-34)
- Git Bash at `C:\Program Files\Git\bin\bash.exe`

A one-click auto-installer wizard is on the roadmap (iteration 6).
