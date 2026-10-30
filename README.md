# UME-Core

A MAME core for [OpenEmu](https://openemu.org), built from MAME 0.289. It replaces the MAME 0.250 core OpenEmu installs by default, so arcade sets dumped for a recent MAME load again, and it comes as a prebuilt plugin: download, double-click, done.

## Features

- **MAME 0.289** arcade drivers (the `arcade` subtarget), with ROM sets audited the way MAME does it. A set that fails the audit is reported with the missing or wrong files instead of a silent crash.
- **Mouse as lightgun** for gun games such as `term2`: left and right click are the trigger and the second button.
- Eight joysticks mapped to OpenEmu's arcade controls, plus a keyboard device.
- Save states, rewind and OpenEmu's display-mode changes.
- Updates itself through OpenEmu's core updater once installed.

## Requirements

OpenEmu 2.4.1 on macOS 12.4 or later. OpenEmu.app is an Intel binary, so the core is x86_64 too; on Apple Silicon both run under Rosetta.

## Install

1. Download `MAME_<version>.zip` from the [latest release](https://github.com/slioce/UME-Core/releases/latest) and unzip it.
2. Double-click `MAME.oecoreplugin`. OpenEmu imports it into `~/Library/Application Support/OpenEmu/Cores/`, moves the previous MAME core to the Trash and asks to restart.
3. From then on OpenEmu checks this repository's `appcast.xml` at launch and installs newer versions by itself.

To install by hand instead, quit OpenEmu, copy `MAME.oecoreplugin` into `~/Library/Application Support/OpenEmu/Cores/`, and clear the quarantine flag that Safari sets on downloads:

```sh
xattr -dr com.apple.quarantine ~/Library/Application\ Support/OpenEmu/Cores/MAME.oecoreplugin
```

The plugin is signed ad hoc, not notarized. OpenEmu removes the quarantine flag when it imports a plugin, which is why the double-click route needs no extra step.

## ROMs

The core ships no ROMs. Add your sets to OpenEmu's Arcade library as MAME expects them: one `<driver>.zip` per game, named exactly after the MAME driver (`sf2ceua.zip` for driver `sf2ceua`), with the BIOS and device sets the game needs (`neogeo.zip`, `qsound_hle.zip`, …) in the same folder. Sets must match **MAME 0.289**; older sets often lack the PLD dumps added since. Mechanical machines, machines that need artwork and drivers MAME marks as not working are refused.

`make romaudit` (after a source build) audits a whole folder with the checks the core applies when it loads a game:

```sh
make romaudit                                   # OpenEmu's Arcade ROM folder
make romaudit ROMDIR=/path/to/roms
```

If a gun game follows the pointer but every shot lands in a corner, the game's own calibration in NVRAM (`~/Library/Application Support/OpenEmu/MAME/nvram/<driver>/`) predates pointer input. Recalibrate from the game's service menu, or delete that folder while no game is running.

## Build from source

Requires Xcode 16 or later, about 5 GB of disk and, for MAME itself, around 20 minutes on an Apple Silicon Mac. The project expects an OpenEmu checkout next to this one (for one header, `OEArcadeSystemResponderClient.h`); set `OPENEMU_DIR` in `Config/Local.mk` to use another location.

```sh
git clone --recurse-submodules https://github.com/slioce/UME-Core.git
git clone --depth 1 --recurse-submodules https://github.com/OpenEmu/OpenEmu.git   # sibling checkout
cd UME-Core
make dylib     # MAME as deps/mame/mamearcade_headless.dylib (slow)
make sdk       # OpenEmuBase.framework into build/Release
make core      # build/Release/MAME.oecoreplugin
make install   # into ~/Library/Application Support/OpenEmu/Cores (quit OpenEmu first)
```

Or open `MAME.xcodeproj` in Xcode after `make dylib sdk`. Build settings live in `Config/Shared.xcconfig`; per-machine overrides such as `OPENEMU_DIR` or a signing team go in `Config/Local.xcconfig`, which is ignored by git. No developer account is needed.

On an Apple Silicon host the Makefile passes `PLATFORM=x86` to MAME's build, which otherwise follows `uname -m`. MAME's objects go to `deps/mame/build/osx_clang` whatever the architecture, so delete that folder when switching.

## Project layout

```
MAMEGameCore.m        The OpenEmu core: input mapping, options, ROM audit, frames, audio, save states.
Info.plist            Bundle metadata, OpenEmu keys and the appcast URL (SUFeedURL).
Config/               Build settings (Shared.xcconfig); Local.xcconfig and Local.mk are yours.
Makefile              dylib, sdk, core, install, dist, appcast, release, romaudit.
tools/                romaudit.m (ROM set audit) and make-appcast.sh.
appcast.xml           The feed OpenEmu polls for updates; rewritten by `make release`.
deps/mame             Fork of MAME (slioce/mame, branch mame0289-headless).
```

The fork adds a "headless" OSD layer (`src/osd/headless/`, originally written by Stuart Carnie for OpenEmu) that exposes MAME to Objective-C as `OSD`, `InputDevice`, `AuditResult` and friends, runs one frame per call instead of MAME's own loop, serializes save states to memory, and builds MAME as a dynamic library. `CLAUDE.md` has the details of the build and the debugging notes.

## Releasing

Releases are built on a Mac, not in CI: compiling MAME takes hours on a GitHub runner.

1. Bump `CURRENT_PROJECT_VERSION` in `Config/Shared.xcconfig` (`<MAME version>.0.<plugin revision>`, for example `0.289.0.3`), commit.
2. `make release`. It zips the plugin, pushes the commit, creates the GitHub Release `v<version>` with the zip attached, then regenerates `appcast.xml`, commits and pushes it. OpenEmu compares `sparkle:version` with the installed `CFBundleVersion`, so the appcast only goes live once the download exists.

## Debugging

The core logs through `os_log` under the subsystem `org.openemu.MAME` (category `audit` for ROM audit details). It runs inside `OpenEmuHelperApp`:

```sh
/usr/bin/log show --last 1h --style compact --info --debug \
  --predicate 'subsystem == "org.openemu.MAME" OR subsystem BEGINSWITH "org.openemu"'
```

A "Load ROM at path …" line with no "Using GameAudio2 driver" after it means loading stopped before emulation started, almost always because the audit rejected the set.

## Acknowledgements

The core and the headless OSD were written by the [OpenEmu Team](https://github.com/OpenEmu/UME-Core), Stuart Carnie in particular; this repository carries them to MAME 0.289 and adds the mouse lightgun, the audit errors and the release tooling. The work on this fork was done with the help of AI coding agents; design, review and testing are the author's.

MAME is developed by [MAMEdev and contributors](https://www.mamedev.org). MAME is a registered trademark of Gregory Ember. This project is not affiliated with MAMEdev or with OpenEmu.

## License

Copyright © 2013-2026 OpenEmu Team and Alessandro Lioce. The code in this repository is released under the [BSD 3-Clause License](LICENSE), as the original OpenEmu core.

The release zips embed a build of MAME, licensed under the [GNU General Public License version 2 or later](https://github.com/slioce/mame/blob/mame0289-headless/COPYING). Each plugin carries the license texts in `Contents/Resources/legal/`, and the corresponding source is the `deps/mame` submodule commit of the release tag.
