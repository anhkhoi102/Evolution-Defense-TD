# iOS readiness

Phase 4 of the campaign expansion: groundwork only. There is **no iOS app yet** (no iOS target, icon,
phone layout or signing). What exists is an architecture in which the game's code no longer depends on
the Mac, and a check that proves it.

## The check

`Scripts/ios-compile-check.sh` compiles and links the whole game (app code and the three library
modules) against the iOS Simulator SDK, by building the Mac target with iOS settings passed on the
command line. Result on 10 November 2026: **passes** (with the app icon skipped, because the icon set
has no iOS sizes yet).

It was **not run on a device or simulator**: no iOS simulator runtime is installed on this Mac, so
"compiles for iOS" is verified and "works on iOS" is not.

## What was done

| Area | Before | Now |
|---|---|---|
| Game rules, data, saving, balance | Already a platform-neutral Swift package | Package declares iOS 17 as a supported platform |
| Platform code | AppKit calls spread over 16 files | One file, `EvolutionDefense/Platform/Platform.swift`, plus the input adapter and the developer tools |
| Colours | `NSColor` in every renderer (61 uses) | `PlatformColor` (NSColor or UIColor) |
| Images in SwiftUI | `Image(nsImage: NSImage(cgImage:))` | `Image(decorative:scale:)`, which exists on both |
| Pointer input | The scene took `NSEvent` mouse events | The scene has three neutral calls: `pointerMoved(to:)`, `pointerPressed(at:)`, `pointerCancelled()`. `Input/GameSpriteView.swift` maps mouse events to them on the Mac and touches on iOS (finger down or moving = preview, lifting = act, two-finger tap = cancel) |
| Keyboard | `NSEvent` key monitor inside the game view | `KeyboardMonitor` in the platform file (no-op on iOS; every action already has an on-screen control) |
| App lifecycle | `NSApp.terminate`, `willTerminate` | `Platform.quit()` / `canQuit` (the Quit button is hidden where apps do not quit) and `Platform.shouldSaveNotification` (quit on the Mac, going to the background on iOS) |
| Developer tools | `SnapshotTool` used AppKit window capture | Compiled on macOS only, with an inert stand-in elsewhere |
| Window sizing | Fixed minimum size and default size | Applied on macOS only |

Gameplay never depended on any of this: hit areas, speeds and timings come from the game data and the
simulation, not from views or events.

## Persistence review

* Saves go to the app's Application Support folder through `FileManager`, which is valid on iOS.
* Profile and checkpoint are JSON with defaults for missing fields; nothing is Mac-specific.
* A match is checkpointed at the start of every preparation phase, and again when
  `Platform.shouldSaveNotification` fires, so an iOS app sent to the background and later removed from
  memory resumes from the start of the current stage.
* Not done: iCloud sync between a Mac and an iPhone.

## What an iOS version still needs

| Item | Notes |
|---|---|
| iOS target in the Xcode project | The check builds the Mac target with overrides; a real target needs its own settings and Info.plist |
| App icon | iOS sizes in the icon set, and a `MenuIcon` image for the menu logo (`Platform.appIcon`) |
| Layout for small screens | The biggest job. Menus and panels use fixed widths (24 places with widths of 100 points or more, e.g. the 760-point Campaign card), and the HUD and bottom panel assume about 1100 × 700 points. An iPad in landscape is close; a phone needs a compact layout |
| Touch ergonomics | Build pads and buttons were sized for a mouse; pads may need a larger touch area (visual only, the hit test is in one place: `GameScene.slot(at:)`) |
| Hover-only hints | Tooltips (`.help`) and the hover line on the Campaign screen do not exist on touch; they need tap equivalents |
| Performance on phones | Never measured. The Mac benchmark holds 60 FPS with about 280 enemies; texture memory is kept down by per-age and per-map atlases |
| Audio session | `AVAudioSession` category and interruption handling (phone calls) |
| Testing on a device or simulator | Needs an iOS simulator runtime installed |
