# Building Portion

This page is for developers. If you just want to use Portion, see the [README](README.md).

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not required.

## One-time setup: signing certificate

```bash
Scripts/make-signing-cert.sh
```

This creates a self-signed certificate called **Portion Signing** in its own keychain (`~/Library/Keychains/portion-signing.keychain-db`). The keychain's random password is stored in `~/Library/Application Support/Portion/`, so `build.sh` can unlock it and sign without ever prompting.

**Why a certificate:** macOS ties the Screen Recording permission to the app's code signature. An ad-hoc signature changes with every build, so macOS would forget the permission after each rebuild. A stable certificate keeps it.

**Why a separate keychain:** signing from the login keychain prompts for the login keychain password. On managed Macs that password often no longer matches the Mac password.

Without the certificate, `build.sh` falls back to an ad-hoc signature. To recover the permission after an ad-hoc build: quit Portion, run `tccutil reset ScreenCapture com.christopherrose.Portion`, then reopen Portion and allow it again.

## Build the app and DMG

```bash
./build.sh                  # → dist/Portion-1.0.0.dmg (universal: Apple Silicon + Intel)
VERSION=1.1.0 ./build.sh    # set the version
```

The app bundle is at `build/Portion.app`. The DMG in `dist/` contains the app and an Applications shortcut.

Every build is sandboxed (`Resources/Portion.entitlements`) and includes a privacy manifest (`Resources/PrivacyInfo.xcprivacy`), just like the App Store version, so local testing matches what App Review sees.

## Mac App Store builds

```bash
TEAM_ID=… APP_STORE_PROFILE=path/to/profile.provisionprofile VERSION=1.0.0 BUILD=1 ./build.sh appstore
```

This needs full Xcode installed, an Apple Distribution certificate, a Mac Installer Distribution certificate, and a Mac App Store provisioning profile for `com.christopherrose.Portion`. It embeds the profile, records the Xcode/SDK versions that App Store Connect checks, signs with the store entitlements, and writes `dist/Portion-<version>.pkg` for Transporter. For the whole process, see [AppStore/README.md](AppStore/README.md).

## Sharing builds with other people

The certificate is only trusted on your Mac, so Gatekeeper blocks the first launch elsewhere. Users can right-click Portion → **Open**, or run `xattr -dr com.apple.quarantine /Applications/Portion.app`. For proper distribution, build with `SIGN_IDENTITY="Developer ID Application: …" ./build.sh`, then notarize it.

## Look and feel

Portion's style matches [christopherrose.com](https://christopherrose.com): black and white, with the purple-to-pink accent gradient (`#aa3bff` → `#ff3bac`) and the [Rubik](https://fonts.google.com/specimen/Rubik) typeface. The colors and font live in `Sources/Portion/Brand.swift`. The app icon comes from `Scripts/make-icon.swift`. After changing it, delete `Resources/AppIcon.icns` and rebuild to regenerate it.

## How it works

- Portion captures half of a display with ScreenCaptureKit and draws it live into a borderless window titled **Portion**. Call apps share that window.
- That window normally hangs off the bottom-right corner of the rightmost display, overlapping it by one pixel. If the window were *fully* off-screen, ScreenCaptureKit couldn't snapshot it, and share pickers would show a blank thumbnail. Zoom only captures the on-screen part of a window (it would get that single pixel), so during a Zoom call the window sits exactly over the shared half instead, behind all other windows. Portion's capture excludes its own windows and the window ignores clicks, so where the desktop shows through, it shows an exact copy of the desktop.
- When sharing starts, the window shows a branded card (`IntroCard.swift`), so it's easy to spot in pickers. macOS doesn't report when another app starts capturing a window. Instead, `ShareDetector.swift` watches for the "sharing" indicator windows that Chrome ("… is sharing a window.") and Zoom ("zoom share toolbar window", matched by bundle ID `us.zoom.xos`, since Zoom's process name has changed over the years) open, and dismisses the card when one appears. A 60-second fallback covers other apps. When sharing started on its own with a call, the card stays up until the share begins, since the picker may not open for a while.
- `CallDetector.swift` starts sharing the left half when a Zoom meeting window ("Zoom Meeting") or a Google Meet call tab ("Meet - abc-defg-hij") is on screen, or when Chrome's "Choose what to share with meet.google.com" picker opens, so the Portion window is already in the picker. It stops sharing it started a few seconds after the call window, the sharing indicator and microphone use are all gone. Browsers only report the active tab's title, so microphone use (read through Core Audio's `kAudioDevicePropertyDeviceIsRunningSomewhere`, never the audio itself) is what keeps a call alive while the Meet tab is in the background. Choosing Stop Sharing keeps it off for the rest of that call. Each call is told apart by its Meet code.
- If the capture stream stops (sleep, lock, display changes), Portion restarts it into the same window, so the call keeps sharing.

## Project layout

```
Package.swift                    Swift package (macOS 13+)
Sources/Portion/
  main.swift                     App entry (menu-bar-only app)
  AppDelegate.swift              Menu bar UI and sharing logic
  RegionCapture.swift            ScreenCaptureKit stream for the half-screen region
  MirrorWindow.swift             The "Portion" window that you share in calls
  IntroCard.swift                Branded card shown in the Portion window when sharing starts
  ShareDetector.swift            Notices when Zoom / Meet start sharing, to dismiss the card
  CallDetector.swift             Starts and stops sharing with Zoom / Meet calls
  BorderOverlay.swift            Gradient outline around the shared area
  Brand.swift                    Brand colors and the Rubik font (matches christopherrose.com)
Resources/Info.plist             Bundle metadata (LSUIElement = menu bar only)
Resources/Portion.entitlements   App Sandbox (required for the Mac App Store)
Resources/PrivacyInfo.xcprivacy  Privacy manifest: no tracking, no data collected
AppStore/                        App Store listing text, screenshots and submission guide
Resources/Fonts/                 Rubik typeface, bundled under the SIL Open Font License
Scripts/make-icon.swift          Generates the app icon
Scripts/make-signing-cert.sh     One-time setup: local code-signing keychain
Scripts/make-graphics.swift      Draws the README illustrations and App Store screenshots
build.sh                         Builds and signs the .app, then packages a .dmg (or an App Store .pkg)
```

To regenerate the README illustrations and App Store screenshots:

```bash
swiftc -parse-as-library Scripts/make-graphics.swift Sources/Portion/IntroCard.swift \
  Sources/Portion/Brand.swift -o /tmp/make-graphics && /tmp/make-graphics
```
