<p align="center"><img src="docs/icon.png" width="128" alt=""></p>

# Apex Station

A free, open-source Mac app for the **Flydigi Apex 5**. It does what Flydigi's Space Station does
on Windows: remap every button, set up the back paddles, macros, sticks, triggers, vibration,
gyro and lighting, and save it all to the controller.

![Apex Station](docs/screenshot.png)

Everything is stored **on the controller**, so the app doesn't need to be running while you play,
and your setup follows the controller to any computer.

## What it does

Click any part of the controller to change it.

- **Buttons and paddles:** make any button act as another one, including M1–M4, LM and RM. Turbo
  that fires while held or toggles on and off, at 1–30 presses a second.
- **Macros:** record a sequence by pressing buttons on the controller, or build it tap by tap.
  Choose whether it plays once, repeats while held, or toggles. Up to 5 per profile.
- **Sticks:** dead zone, full-output point, response curve, precision (8–12 bit) and sensitivity.
- **Triggers:** start and end points, and the force-feedback modes: racing, recoil, sniper, lock
  and vibration.
- **Vibration, gyro and lighting:** motor strength, gyro as a stick or mouse with an activation
  button, and light-bar colours, effects and brightness.
- **Profiles:** all four on-board profiles, with switching, renaming and reset.
- **Controller settings:** polling rate (up to 1000 Hz), sleep timer, Fast Swap, Home as the Xbox
  button, and the screen.
- **Live view:** see every button, stick, trigger and the real polling rate as you press.
- **Backups:** every profile is saved to your Mac before anything on the controller changes.

## Playing games on a Mac

Turn on **Full controller** in the app's settings once. After that, Steam and any game built on
SDL see a real "Flydigi Apex 5", with back paddles, gyro, rumble and about 1000 Hz polling over
the cable. The setting is stored on the controller.

Games that use Apple's Game Controller framework don't recognise the Apex 5's PC mode. For those,
switch the controller to **Switch → Wired** mode. macOS sees it as a Pro Controller, at about
100 Hz.

## Install

1. Download `Apex-Station-x.y.z.zip` from [Releases](../../releases), unzip it, and move
   **Apex Station** to Applications.
2. The app isn't notarised by Apple, so macOS blocks it the first time. Open it once, then go to
   **System Settings → Privacy & Security** and click **Open Anyway**. Or run this in Terminal:
   ```sh
   xattr -dr com.apple.quarantine "/Applications/Apex Station.app"
   ```
3. Plug in the Apex 5 with a USB-C cable and set it to **PC → Wired** on the controller.

Needs macOS 15 or later, on Apple Silicon or Intel. The app needs no permissions, drivers or
system extensions.

## Build it yourself

You need Apple's Command Line Tools (`xcode-select --install`) and [Bun](https://bun.sh). Xcode
isn't needed.

```sh
bun run test          # protocol tests, using data captured from a real Apex 5
bun run build         # build/Apex Station.app
bun run install-app   # build and copy to /Applications
bun run release       # universal build, zipped for download
bun scripts/icon.ts   # re-render the app icon
```

`Sources/ApexKit` holds the controller protocol: profile, lighting, macro and settings formats.
It has no UI and no hardware access, so it can be reused. `Sources/ApexStation` is the app.
`tools/` has the command-line probes used to work out the protocol.

## Safety

The app only uses the commands Space Station uses for settings, profiles and lighting. It never
touches firmware. Each change writes only the bytes that differ, reads them back to check, and
keeps a backup in `~/Library/Application Support/Apex Station/Backups`.

Not affiliated with Flydigi.
