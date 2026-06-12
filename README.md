# Snoopy 📷

A tiny macOS menu bar app that plays customizable sounds for hardware events:
opening/closing the lid, plugging/unplugging USB devices, displays, audio
devices, and the charger.

## Features

- **Six event categories**, each with its own enable toggle and per-event sounds:
  - **Lid** — open / close (the open sound defaults to off; see Lock & Unlock)
  - **Lock & Unlock** — sound after password/Touch ID unlock (the camera-shutter
    "open" default lives here: unlock happens on a fully awake system, so the
    sound is never late or swallowed like wake-time playback can be), plus an
    optional lock sound
  - **USB devices** — plug in / unplug, any port
  - **Displays** — external monitor connect / disconnect
  - **Audio devices** — headphones, AirPods, USB audio connect / disconnect
  - **Charging** — charger plug in / unplug, fully-charged chime, and a
    low-battery warning at 20%
- **Sound sources**: 9 bundled presets, all built-in macOS system sounds
  (Glass, Tink, …), or any audio file on your Mac (`.mp3`, `.wav`, `.aiff`, …)
- **Debounced**: hubs and docks that enumerate many devices at once play one
  sound, not a burst
- **One plug, one sound**: a USB-C monitor or dock raises USB + display (+
  audio) events for a single cable plug — the most specific category wins
  (Displays > Audio > USB), so you hear only your chosen display sound. USB
  hubs and billboard devices (the plumbing inside monitors, docks, and
  chargers) are ignored entirely; bare USB devices play after a short ~2.5s
  hold used to detect multi-category plugs.
- **Volume slider** independent of system volume
- **Quick mute**: the main toggle at the top of the menu disables sounds instantly
- **Launch at login**
- Preview button next to each sound picker

## Download & install (no building needed)

1. Grab `Snoopy-vX.X.zip` from the
   [latest release](https://github.com/01000001x01001110x01010011x01001000/snoopy/releases/latest)
   and unzip it.
2. Move `Snoopy.app` to `/Applications`.
3. First launch: macOS will block it because the app isn't notarized by Apple.
   Open **System Settings → Privacy & Security**, scroll down, and click
   **Open Anyway** next to the Snoopy message (or run
   `xattr -d com.apple.quarantine /Applications/Snoopy.app` and open normally).
4. Look for the camera-shutter icon in the menu bar, pick your sounds, and
   enable **Launch at login**.

## Build & run

```bash
./build.sh        # builds and assembles Snoopy.app
open Snoopy.app   # run it — look for the shutter icon in the menu bar
```

To keep it around permanently:

```bash
cp -r Snoopy.app /Applications/
```

Then enable **Launch at login** from the menu. (Launch-at-login only works when the
app runs from a stable location like `/Applications`, not via `swift run`.)

## How it works

- **Lid detection**: subscribes to IOKit's `IOPMrootDomain` general-interest
  notifications and reacts to clamshell state changes
  (`kIOPMMessageClamshellStateChange`), reading `AppleClamshellState` from the
  I/O Registry. This works whether or not closing the lid puts the Mac to sleep
  (e.g. with an external display connected).
- **Playing sound before sleep**: closing the lid normally sleeps the Mac almost
  immediately, which would cut the sound off. Snoopy registers with
  `IORegisterForSystemPower` and briefly delays acknowledging the sleep
  (`IOAllowPowerChange`) until the close sound finishes — capped at 5 seconds.
- **USB**: IOKit matching notifications on `IOUSBHostDevice`
  (first-match = plugged, terminate = unplugged).
- **Displays**: `CGDisplayRegisterReconfigurationCallback` add/remove flags;
  the built-in panel is filtered out so clamshell mode doesn't double-fire.
- **Audio devices**: CoreAudio device-list diffing, plus a data-source listener
  on the built-in output for Macs where the headphone jack switches the device
  in place instead of adding one.
- **Charging / battery**: `IOPSNotificationCreateRunLoopSource` power-source
  notifications; full-charge and low-battery sounds fire once per
  plug/discharge session (low re-arms at 25%).
- **Audio**: `AVAudioPlayer`. **UI**: SwiftUI `MenuBarExtra` (macOS 13+).

## Project layout

```
Sources/Snoopy/
  SnoopyApp.swift        app entry + menu bar scene
  LidMonitor.swift       IOKit clamshell + sleep-delay plumbing
  DeviceWatchers.swift   USB / display / audio / power watchers
  SoundEvent.swift       event + category model, defaults, debounce windows
  AppModel.swift         settings, playback, debouncing, launch-at-login
  MenuView.swift         menu bar dropdown UI
  SoundLibrary.swift     preset/system/custom sound model
Resources/Sounds/     generated preset WAVs
scripts/generate_sounds.py   regenerates the presets
Support/Info.plist    bundle metadata (LSUIElement = menu-bar only)
build.sh              builds + assembles + ad-hoc signs Snoopy.app
```

## Notes

- Settings persist in `UserDefaults` under the `com.ansh.snoopy` bundle ID.
- The app is ad-hoc signed; that's fine for personal use. Distribution to other
  Macs would need a Developer ID certificate and notarization.
- To rename the app, change the name in `Package.swift`, `Support/Info.plist`,
  and `build.sh`.
