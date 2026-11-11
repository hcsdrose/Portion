# Portion

A simple macOS menu bar app for sharing just the **left half** or **right half** of your screen in Zoom, Google Meet, or any app that can share a single window.

## How it works

Portion captures half of your display with ScreenCaptureKit and draws it live into a window named **“Portion”**. In your call you share that window instead of your whole screen, so people see only that half. You can switch halves from the menu bar at any time, and the call keeps sharing without a restart.

The Portion window is hidden just off-screen by default, so you never see it yourself. When you start, it shows a blue **Portion** card instead of the live picture, so it's easy to spot in Zoom's or Meet's window picker. The card disappears as soon as you click **Share** in Zoom or in Meet (Chrome). Cancelling the picker leaves it up. In other apps it disappears after 60 seconds. A red outline marks the area being shared. The outline is not included in the shared picture.

## Using it

1. Click the Portion icon in the menu bar and choose **Share Left Half** or **Share Right Half**.
2. Share the Portion window in your call:
   - **Zoom:** Share Screen → pick the **Portion** window.
   - **Google Meet (Chrome):** Present now → **A window** → **Portion**.
3. To stop, choose **Stop Sharing** in Portion, and stop presenting in your call.

Menu options:

- **Display:** shown only when more than one monitor is connected. Picks which screen to split.
- **Outline Shared Area:** shows or hides the red outline.
- **Portion Window Placement:** if the Portion window doesn't appear in a share picker, choose **On Other Half, Behind Windows**. This keeps the window on-screen, behind your other windows, on the half you are *not* sharing.
- **Launch at Login**

### First run: Screen Recording permission

macOS will ask for permission to record your screen. Turn on **Portion** in **System Settings → Privacy & Security → Screen & System Audio Recording**, then quit and reopen Portion.

Zoom and Chrome also need this permission to share windows.

## Building the DMG

You need the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not required.

```bash
./build.sh                  # → dist/Portion-1.0.0.dmg (universal: Apple Silicon + Intel)
VERSION=1.1.0 ./build.sh    # set the version
```

Open the DMG and drag **Portion** into **Applications**.

### Signing notes

Run this once before your first build:

```bash
Scripts/make-signing-cert.sh
```

It creates a self-signed certificate called **Portion Signing** in its own keychain (`~/Library/Keychains/portion-signing.keychain-db`). The keychain has a random password, saved in `~/Library/Application Support/Portion/`. `build.sh` uses it to unlock the keychain and sign automatically, so you never get a keychain password prompt. A separate keychain avoids the login keychain, whose password can stop matching your Mac password on managed Macs. Every build then has the same identity, so macOS keeps the Screen Recording permission after you rebuild.

Without the certificate, `build.sh` falls back to an **ad-hoc** signature. macOS treats each ad-hoc build as a new app, so the permission is lost after every rebuild, even though the switch in Settings still looks on. To fix that, quit Portion, run `tccutil reset ScreenCapture app.portion.Portion`, then reopen Portion and allow it again.

- **Copying the DMG to another Mac:** Gatekeeper will block the first launch, because the certificate is only trusted on your Mac. Right-click Portion → **Open**, or run `xattr -dr com.apple.quarantine /Applications/Portion.app`. To distribute it properly, build with `SIGN_IDENTITY="Developer ID Application: …" ./build.sh`, then notarize it.

## Project layout

```
Package.swift                 Swift package (macOS 13+)
Sources/Portion/
  main.swift                  App entry (menu-bar-only app)
  AppDelegate.swift           Menu bar UI and sharing logic
  RegionCapture.swift         ScreenCaptureKit stream for the half-screen region
  MirrorWindow.swift          The "Portion" window that you share in calls
  IntroCard.swift             Branded card shown in the Portion window when sharing starts
  ShareDetector.swift         Notices when Zoom / Meet start sharing, to dismiss the card
  BorderOverlay.swift         Red outline around the shared area
Resources/Info.plist          Bundle metadata (LSUIElement = menu bar only)
Scripts/make-icon.swift       Generates the app icon
Scripts/make-signing-cert.sh  One-time setup: local code-signing certificate
build.sh                      Builds .app, signs it, and packages the .dmg
```
