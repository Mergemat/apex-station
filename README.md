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

- **Buttons and paddles:** click Assign and press the button it should act as. Works for every button, including M1–M4, LM and RM. Turbo
  that fires while held or toggles on and off, at 1–30 presses a second.
- **Macros:** record a sequence by pressing buttons on the controller, or build it tap by tap.
  Choose whether it plays once, repeats while held, or toggles, and the pause between repeats.
  Up to 5 per profile.
- **Sticks:** a response curve you drag into shape (dead zone, anti-dead zone, bends, full-output
  point), the Default/Instant/Delay presets, circle or square, precision (8–12 bit) and
  sensitivity. A circularity test shows how far the stick reaches in every direction.
- **Keyboard and mouse:** set buttons to keys, clicks or scrolling, sticks to WASD, arrows or the
  pointer, and gyro to the pointer. Like on Windows, the app does this while it runs.
- **Triggers:** start and end points, and the force-feedback modes: racing, recoil, sniper, lock
  and vibration.
- **Vibration, gyro and lighting:** motor strength, gyro as a stick or mouse with an activation
  button, and light-bar colours, effects, brightness and the vibration light effect.
- **Screen:** put your own picture or GIF on the controller's display (up to 150 frames).
- **Profiles:** all four on-board profiles, with switching, renaming, reset, and export/import
  as files.
- **Controller settings:** polling rate (up to 1000 Hz), sleep timer, Fast Swap, Home as the Xbox
  button, and the screen.
- **Live view:** see every button, stick, trigger and the real polling rate as you press, over
  the cable, Flydigi's 2.4 GHz receiver or PC Bluetooth. Settings need the cable or receiver:
  in Bluetooth mode the controller is a plain Xbox pad with no settings channel.
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

Needs macOS 15 or later, on Apple Silicon or Intel. No drivers or system extensions. Keyboard and
mouse mapping asks for Accessibility permission; nothing else needs any.

## Build it yourself

You need Apple's Command Line Tools (`xcode-select --install`) and [Bun](https://bun.sh). Xcode
isn't needed.

```sh
bun run test          # protocol tests, using data captured from a real Apex 5
bun run build         # build/Apex Station.app
bun run install-app   # build and copy to /Applications
bun run release       # universal build, zipped for download
bun scripts/icon.ts   # re-render the app icon
bun scripts/screen-default.ts ss4_setup.exe   # copy Flydigi's screen animation out of Space Station
```

The screen's stock animation is Flydigi's artwork, so it isn't included. Run the last command
with Space Station's Windows installer (needs `brew install innoextract`) and the app offers
**Restore Flydigi animation**.

`Sources/ApexKit` holds the controller protocol: profile, lighting, macro and settings formats.
It has no UI and no hardware access, so it can be reused. `Sources/ApexStation` is the app.
`tools/` has the command-line probes used to work out the protocol.

## Safety

The app only uses the commands Space Station uses for settings, profiles, lighting and the
screen. It never touches firmware. Each change writes only the bytes that differ, reads the profile back so the app shows what the controller stored, and
keeps a backup in `~/Library/Application Support/Apex Station/Backups`.

Not affiliated with Flydigi.
