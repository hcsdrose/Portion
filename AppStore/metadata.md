# App Store listing for Portion

Copy each field into **App Store Connect → Portion → App Store** tab. Each field below is limited to the characters Apple allows. Run `python3 AppStore/check-metadata.py` after editing to re-check the limits.

---

## App information

| Field | Value |
| --- | --- |
| Name | Portion |
| Subtitle | Share half your screen |
| Bundle ID | com.christopherrose.Portion |
| SKU | portion-mac |
| Primary language | English (U.S.) |
| Primary category | Productivity |
| Secondary category | Business |
| Content rights | Does not contain, show, or access third-party content |
| Age rating | 4+ (answer **None** or **No** to every question) |
| Copyright | 2026 Christopher Rose |
| Price | Your choice (Pricing and Availability tab) |

> If the name **Portion** is already taken, try: `Portion: Share Half Screen` (26 characters) or `Portion – Half-Screen Sharing` (29 characters).

## URLs

| Field | Value |
| --- | --- |
| Support URL (required) | https://christopherrose.com/portion |
| Marketing URL (optional) | https://christopherrose.com/portion |
| Privacy Policy URL (required) | https://christopherrose.com/portion/privacy |

These pages don't exist yet. Add them to christopherrose.com before you submit. The privacy policy text is in [`../PRIVACY.md`](../PRIVACY.md). The support page can be a short version of the [README](../README.md) plus a way to contact you.

---

## Promotional text

<!-- field: promo (max 170) -->
```
Present your slides, document or demo in any video call, and keep your notes, email and chat on the other half of the screen to yourself.
```

## Description

<!-- field: description (max 4000) -->
```
Share just half of your screen in video calls.

Portion lets you present one half of your Mac's screen, like your slides, a document or a demo, while the other half stays completely private. Keep your notes, email and chat right next to what you're presenting, and nobody in the call will see them.

HOW IT WORKS
1. Click the Portion icon in the menu bar and choose Share Left Half or Share Right Half.
2. In your video call, choose to share a window and pick "Portion".
3. That's it. Everyone in the call sees only the half you picked.

FEATURES
• Share the left or right half of any display
• A colored outline shows exactly what's being shared. The call never sees the outline.
• Switch halves in the middle of a call, without stopping or sharing again
• Easy to find: Portion shows up as a bold card in your call's window list
• Works with Zoom, Google Meet in Chrome, and other apps that can share a single window
• Supports multiple displays
• Lives quietly in the menu bar, with an option to open at login

PRIVATE BY DESIGN
Portion runs entirely on your Mac. It doesn't collect, store or send anything. There are no accounts, no analytics and no internet connection. The picture of your screen goes only into the Portion window that you choose to share.

REQUIREMENTS
macOS 13 Ventura or later. Portion needs the Screen Recording permission, which macOS asks for the first time you use it.
```

## Keywords

Separate keywords with commas and no spaces. Don't repeat the app name or category, and don't use other companies' names.

<!-- field: keywords (max 100) -->
```
screen share,half screen,split,present,presentation,meeting,video call,privacy,demo,teacher,window
```

## What's New (for updates only; leave empty on the first release)

<!-- field: whatsnew (max 4000) -->
```
Initial release.
```

---

## Screenshots

Upload the five files in [`screenshots/`](screenshots/), in order, under **macOS → Screenshots**. They're 2880 × 1800, one of Apple's accepted Mac sizes.

1. `01-share-half.png`: Share half your screen
2. `02-find-it.png`: Find it instantly
3. `03-private.png`: Everything else stays private
4. `04-menu-bar.png`: Lives in your menu bar
5. `05-switch.png`: Switch halves mid-call

## App icon

The icon comes from the app itself, so App Store Connect doesn't ask for one. [`icon-1024.png`](icon-1024.png) is there for your website, press, or social posts.

---

## App Privacy (App Store Connect → App Privacy)

- **Do you or your third-party partners collect data from this app?** No
- The result is **"Data Not Collected"**.
- The app's privacy manifest (`Resources/PrivacyInfo.xcprivacy`) says the same thing.

## Export compliance

Already answered in the app: `ITSAppUsesNonExemptEncryption` is set to NO, because Portion uses no encryption. App Store Connect won't ask.

---

## App Review information

**Sign-in required:** No.

**Contact:** your name, phone and email (App Review only; not shown publicly).

**Notes for the reviewer** (paste into App Review Information → Notes):

<!-- field: reviewnotes (max 4000) -->
```
Portion is a menu bar app. It has no Dock icon and no main window.

On first launch, a welcome message explains where to find it. Portion's icon (two side-by-side rectangles) is in the menu bar at the top right of the screen.

HOW TO TEST
1. Launch Portion and click Continue on the welcome message.
2. macOS asks for Screen Recording permission. Turn on Portion in System Settings > Privacy & Security > Screen & System Audio Recording, then quit and reopen Portion (macOS requires this).
3. Click the Portion menu bar icon and choose "Share Left Half". A purple-and-pink outline appears around the left half of the screen. The outline is only visible locally.
4. Open a video call app that can share a single window, such as Zoom or Google Meet in Chrome (meet.google.com/new).
5. Choose to share a window and pick the window named "Portion". It shows a purple card labeled "Portion".
6. After clicking Share, the card disappears and the call shows a live picture of only the left half of the screen. Choose "Share Right Half" in the Portion menu to switch halves without re-sharing.

WHY PORTION NEEDS SCREEN RECORDING
Portion copies half of the screen into its own window, called "Portion", which the call app then shares. Nothing is recorded, saved or sent anywhere. Portion has no network access.

ABOUT THE PORTION WINDOW
The "Portion" window is deliberately placed almost entirely off-screen, so the user doesn't see a second copy of their screen. It is still visible to the call app's window picker.

ABOUT READING WINDOW TITLES
While its purple card is showing, Portion checks the titles of on-screen windows a few times per second. It looks only for the indicator that Zoom or Chrome shows once sharing starts ("... is sharing a window"), then hides its card so the call sees the user's screen. Titles are never stored or sent anywhere, and the check stops as soon as sharing begins.
```
