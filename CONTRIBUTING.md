# Contributing

Bug reports, captures from your controller and pull requests are all welcome.

## Setup

You need Apple's Command Line Tools (`xcode-select --install`) or Xcode, and [Bun](https://bun.sh).

```sh
bun run test          # protocol tests
bun run install-app   # build, copy to /Applications and relaunch
```

`bun run build` alone leaves the app in `build/Apex Station.app`. To follow what the app does
with the controller:

```sh
log stream --predicate 'subsystem == "dev.bomarov.ApexStation"'
```

## Layout

- `Sources/ApexKit`: the controller protocol (profiles, lighting, macros, settings, reports).
  No UI and no hardware access, so everything in it is tested.
- `Sources/ApexStation`: the app. `Hardware/` talks to the controller, `Views/` is SwiftUI.
- `Sources/ApexPad`: the helper that publishes the virtual Xbox controller. It's a separate
  binary because it needs an entitlement macOS only honours for signed code or with AMFI relaxed.
- `tools/`: the probes used to work out the protocol. Each file says how to build and run it.
- `Tests/ApexKitTests/Fixtures`: bytes read from a real Apex 5.

## Protocol changes

Decode from real bytes. If you work out a new field, capture what the controller sends or
stores (`tools/fdprobe.c`, `tools/reportlog.c` and `tools/profiletool.swift` help) and add the
capture as a fixture, with a test that reads it and checks what Space Station shows for the
same setting. That keeps the tests honest against the hardware, not just against the code.

The app only sends commands Space Station sends, and never writes firmware. Keep it that way:
if a change needs a command Space Station doesn't use, open an issue first.

Don't commit Flydigi's files (installers, the screen animation, firmware).

## Pull requests

PRs are squash-merged, and the PR title becomes the commit message and the changelog line. Use
a [conventional commit](https://www.conventionalcommits.org) title, e.g.
`fix: rumble stops after the controller sleeps`. `feat` and `fix` show up in release notes;
`docs`, `refactor`, `test`, `ci`, `chore` don't.

Say which connection (cable, receiver, Bluetooth) you tried a hardware change on.

## Releases

[release-please](https://github.com/googleapis/release-please) keeps a release PR open with
the next version and changelog. Merging it tags the release, and CI builds the universal app
and attaches `Apex-Station-x.y.z.zip` to it.
