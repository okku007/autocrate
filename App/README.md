# Autocrate — Xcode app shell

The pure logic, cache, pipeline, and app-side UI/readers all live in the SwiftPM
package at the repo root (`AutocrateCore` + `AutocrateAppKit` targets) and are
built/tested headlessly with `swift test` / `swift build`. This `App/` folder is
the thin macOS app shell that can only be assembled in Xcode (it needs an app
bundle, Info.plist, font resources, and a TCC entitlement to run as a menu-bar item).

## One-time Xcode setup

1. **Create the app target.** Xcode → File → New → Project → macOS → App.
   - Product name `Autocrate`, Interface **SwiftUI**, Language **Swift**.
   - Deployment target **macOS 13.0**.
   - Save it so the project sits alongside this repo (or inside it).

2. **Add the local package.** File → Add Package Dependencies → **Add Local…** →
   select this repo's root (the folder with `Package.swift`). Add the
   **`AutocrateAppKit`** library product to the app target. (It transitively pulls
   in `AutocrateCore` and GRDB.)

3. **Use this entry point.** Delete the template's `ContentView.swift` and
   `…App.swift`, then add **`App/AutocrateApp.swift`** to the target. It renders
   `MenuPanelView()` from `AutocrateAppKit`.

4. **Info.plist.** Use the keys in **`App/Info.plist`** (or merge them into the
   target's generated Info settings):
   - `LSUIElement = YES` — menu-bar-only, no Dock icon.
   - `NSAppleEventsUsageDescription` — the Automation prompt text.
   - `ATSApplicationFontsPath = .` — load bundled fonts.

5. **Bundle the fonts.** Download **JetBrains Mono** and **Geist Pixel Square**
   (`vercel.com/font` or the `geist` npm package), drag the `.otf`/`.ttf` files
   into the target, and confirm they're in **Copy Bundle Resources**.

6. **Set your API key.** Edit `Sources/AutocrateAppKit/Secrets.swift` and replace
   `REPLACE_WITH_YOUR_KEY` with your free key from
   [getsongbpm.com/api](https://getsongbpm.com/api). Do **not** commit the real key.

7. **Run.** ⌘R. A `waveform` icon appears in the menu bar. On first use, macOS
   prompts for permission to control Music — grant it (or later toggle it in
   System Settings → Privacy & Security → Automation).

## Manual verification checklist (the headless tests can't cover these)

- Play a known electronic track → seed header shows BPM + Camelot; a ranked
  shortlist renders; the top row is accent-tinted.
- Tap a library row → it's revealed in Music. Option-tap → "Artist – Title"
  copied to the clipboard.
- A "DISCOVER — not in your library" section lists compatible tracks confirmed on
  Apple Music; tapping one opens it via its `music.apple.com` URL.
- Cycle the states: stop Music (`nothing playing`); play a track with no
  GetSongBPM data (`seed miss`); deny Automation (`permission` message); cold
  cache (`indexing — N of M` banner).

## Known live-API caveat

`GetSongBpmClient` (search + `/tempo` + `/key`) and `iTunesResolver` are network
glue. Confirm GetSongBPM's base host and JSON field names against one real
response and adjust the decode types if they differ — see the `NOTE:` comments in
`Sources/AutocrateCore/Data/GetSongBpmClient.swift`.
