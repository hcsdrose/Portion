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

Without the certificate, `build.sh` falls back to an ad-hoc signature. To recover the permission after an ad-hoc build: quit Portion, run `tccutil reset ScreenCapture app.portion.Portion`, then reopen Portion and allow it again.

## Build the app and DMG

```bash
./build.sh                  # → dist/Portion-1.0.0.dmg (universal: Apple Silicon + Intel)
VERSION=1.1.0 ./build.sh    # set the version
```

The app bundle is at `build/Portion.app`. The DMG in `dist/` contains the app and an Applications shortcut.

## Sharing builds with other people

The certificate is only trusted on your Mac, so Gatekeeper blocks the first launch elsewhere. Users can right-click Portion → **Open**, or run `xattr -dr com.apple.quarantine /Applications/Portion.app`. For proper distribution, build with `SIGN_IDENTITY="Developer ID Application: …" ./build.sh`, then notarize it.

## How it works

- Portion captures half of a display with ScreenCaptureKit and draws it live into a borderless window titled **Portion**. Call apps share that window.
- That window normally hangs off the bottom-right corner of the rightmost display, overlapping it by one pixel. If the window were *fully* off-screen, ScreenCaptureKit couldn't snapshot it, and share pickers would show a blank thumbnail.
- When sharing starts, the window shows a branded card (`IntroCard.swift`), so it's easy to spot in pickers. macOS doesn't report when another app starts capturing a window. Instead, `ShareDetector.swift` watches for the "sharing" indicator windows that Chrome ("… is sharing a window.") and Zoom ("zoom share toolbar window") open, and dismisses the card when one appears. A 60-second fallback covers other apps.
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
  BorderOverlay.swift            Red outline around the shared area
Resources/Info.plist             Bundle metadata (LSUIElement = menu bar only)
Scripts/make-icon.swift          Generates the app icon
Scripts/make-signing-cert.sh     One-time setup: local code-signing keychain
Scripts/make-readme-images.swift Draws the README illustrations into docs/images/
build.sh                         Builds .app, signs it, and packages the .dmg
```

To regenerate the README illustrations:

```bash
swiftc -parse-as-library Scripts/make-readme-images.swift Sources/Portion/IntroCard.swift \
  -o /tmp/make-readme-images && /tmp/make-readme-images
```
