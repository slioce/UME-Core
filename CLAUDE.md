# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An OpenEmu core plugin (`MAME.oecoreplugin`) for arcade games, wrapping MAME 0.289. The repo itself only contains the thin OpenEmu glue (`MAMEGameCore.m`); almost everything else lives in the `deps/mame` submodule, a fork of MAME (`slioce/mame`, branch `mame0289-headless`) that adds a "headless" OSD layer and builds MAME as a dynamic library, `mamearcade_headless.dylib`.

The Amiga system and core for the same OpenEmu install (PUAE, plus an `Amiga.oesystemplugin` copied into OpenEmu.app) live in the separate repo `slioce/PUAE-Core`. MAME's own Amiga drivers are all `MACHINE_NOT_WORKING` in 0.289.

There are no tests or linters. To verify a change, build it, install the plugin and load ROMs in OpenEmu.

The repo is public (`slioce/UME-Core`, BSD-3-Clause; the release zips embed MAME, GPL-2.0-or-later). Releases are prebuilt plugins on GitHub Releases plus `appcast.xml`, which OpenEmu polls through the plugin's `SUFeedURL`. Keep the README, the Makefile and this file in English.

## Build

The `Makefile` is the entry point; the README has the user-facing version. Per-machine settings (where the OpenEmu checkout is) go in `Config/Local.mk`, ignored by git:

```sh
make dylib     # MAME as deps/mame/mamearcade_headless.dylib
make sdk       # OpenEmuBase.framework into build/Release
make core      # build/Release/MAME.oecoreplugin
make install   # into ~/Library/Application Support/OpenEmu/Cores; refuses while OpenEmu runs
make dist      # build/MAME_<version>.zip
make release   # GitHub Release + appcast.xml (see "Releasing" in the README)
```

There are two stages. The MAME dylib must exist before the Xcode project will link.

**1. MAME dylib** (`make dylib`; slow: about 20 min on Apple Silicon with `-j` = all cores, plus about 5 GB of disk). What it runs:

```sh
cd deps/mame
make macosx_x64_clang PLATFORM=x86 OSD="headless" TARGETOS="macosx" CONFIG="release" \
     TARGET=mame SUBTARGET=arcade MACOSX_DEPLOYMENT_TARGET=12.4 -j$(sysctl -n hw.ncpu)
install_name_tool -id mamearcade_headless.dylib mamearcade_headless.dylib
lipo -archs mamearcade_headless.dylib
```

- **Use `PLATFORM=x86` on an Apple Silicon host.** Without it, the makefile detects arm64 from `uname -m` and compiles arm64 even with the `macosx_x64_clang` target. Check with `grep -o "\-arch [a-z0-9_]*" build.log | sort -u`.
- Objects go to `build/osx_clang/obj/x64/Release` whatever the arch, so delete `build/osx_clang` and `build/projects` when switching arch. Otherwise make reuses stale objects.
- Compiler flags include `-Werror`. C99-only constructs (for example designated array initializers) in `.mm` files fail the build.
- The installed OpenEmu.app is x86_64-only. `ARCHS = x86_64` in the Xcode project must match the dylib.

**2. OpenEmu SDK + core** (`make sdk core`). The project needs OpenEmu sources at `$(OPENEMU_DIR)` (default `../OpenEmu`; a shallow clone plus the `OpenEmu-SDK` submodule is enough) for `OEArcadeSystemResponderClient.h`, and `OpenEmuBase.framework` in `BUILT_PRODUCTS_DIR`, so both build into the same `SYMROOT=build`.

- All build settings are in `Config/Shared.xcconfig` (version, `ARCHS = x86_64`, deployment target 12.4, header paths, ad-hoc signing). The target's pbxproj settings are empty. `Config/Local.xcconfig` overrides them per machine and is ignored.
- `CURRENT_PROJECT_VERSION` (CFBundleVersion, `<MAME version>.0.<plugin revision>`) is what OpenEmu compares with `appcast.xml` to offer updates. Bump it for every release.
- A build phase of the `MAME` target runs `install_name_tool -change mamearcade_headless.dylib @rpath/...` and copies the license texts (LICENSE, MAME's COPYING, GPL-2.0, BSD-3-Clause) into `Contents/Resources/legal/`; the dylib is embedded in `Contents/Frameworks`.
- `MAME.xcscheme` is shared. The `Build & Install MAME` aggregate target also copies the plugin into `~/Library/Application Support/OpenEmu/Cores/` and **replaces** the installed core; `make install` does the same but keeps a `.bak-YYYYMMDD` copy.

## Architecture

The code has three layers:

1. **`MAMEGameCore` (`MAMEGameCore.m`)**, an `OEGameCore` subclass and `OEArcadeSystemResponderClient`. It:
   - maps OpenEmu arcade buttons to 8 virtual joysticks plus a keyboard device;
   - maps the mouse to lightgun 0 (left/right click = buttons 1/2). The OSD enables the lightgun class only for games with crosshair inputs, which covers mounted guns emulated as `AD_STICK` such as `term2`. OpenEmu's `OEArcadeSystemResponder` ignores mouse events, so `add_arcade_mouse_forwarding()` adds the overrides at runtime;
   - sets MAME options (ROM path = the ROM's directory, base path = OpenEmu support dir);
   - runs the ROM audit and turns failures into user-facing `NSError`s;
   - forwards `executeFrame`, save states, rewind and video/audio buffers.

   The ROM's filename (without extension) is the MAME driver short name, for example `sf2ceua.zip` maps to driver `sf2ceua`.
2. **Headless OSD (`deps/mame/src/osd/headless/`)**, the Objective-C++ API between OpenEmu and MAME. `public/headless.h` is the contract that `MAMEGameCore` sees:
   - `OSD` is a singleton with `setDriver:withAuditResult:error:`, `initializeWithError:`, `execute`, and state serialization;
   - `OSDDelegate` receives callbacks for init, display bounds/fps, audio and log;
   - `InputClass`/`InputDevice` and `AuditResult`/`AuditRecord` cover input and auditing.

   `headless.mm` implements it on top of MAME's `osd_interface`. Build wiring is in `scripts/src/osd/headless*.lua`. Only `OE_EXPORTED_CLASS` symbols are visible from the dylib.
3. **Fork patches to MAME's core**, mainly to allow frame-at-a-time execution and in-memory save states:
   - `src/emu/machine.{h,cpp}`: `running_machine::headless_run()` runs one frame per `OSD.execute` call instead of MAME's own run loop;
   - plus `save.cpp`, `config.cpp`, `emuopts`, `frontend/mame/mame.cpp`, and the makefile/genie changes for the dylib target.

   When upgrading MAME, diff the previous `mameXXXX-headless` branch against upstream to carry these forward.

### Arcade subtarget and driver filtering

`SUBTARGET=arcade` has no `.lua` file. Its source list is generated from `src/mame/arcade.flt` by `scripts/build/makedep.py`, which follows `#include`s and `_a/_v/_m` siblings of headers. Lines starting with `//` exclude drivers, with a reason comment. Source files nothing includes by name, such as `cave/cv1k_v_blit0..8.cpp`, must be listed explicitly or the link fails with undefined symbols. To check the generated list:

```sh
python3 scripts/build/makedep.py -r . filterproject -t arcade -f src/mame/arcade.flt src/mame/mame.lst | grep <file>
```

## Debugging in OpenEmu

The core logs via `os_log` with subsystem `org.openemu.MAME` (category `audit` for ROM audit details, at debug level). The core runs inside `OpenEmuHelperApp`:

```sh
/usr/bin/log show --last 1h --style compact --info --debug \
  --predicate 'subsystem == "org.openemu.MAME" OR subsystem BEGINSWITH "org.openemu"'
```

A missing "Using GameAudio2 driver" line after "Load ROM at path …" means loading failed before emulation started. That is usually the audit rejecting the set (`AuditSummaryIncorrect` or `AuditSummaryNotFound`). Compare the zip's CRCs (`unzip -v`) with the `ROM_START( <driver> )` block in `deps/mame/src/mame/<maker>/*.cpp`. ROM sets must match MAME 0.289. Older sets often lack newly added PLD dumps.

ROMs live in `~/Library/Application Support/OpenEmu/Game Library/roms/Arcade/`. `make romaudit [ROMDIR=dir]` builds `tools/romaudit.m` against `mamearcade_headless.dylib` and audits a whole folder. It applies the same checks as `loadFileAtPath:` (driver name, unsupported machines, ROM audit).

If a gun game tracks the pointer (MAME's crosshair follows the mouse) but every shot lands in one corner, the game's own gun calibration is stale. It is stored in the game's NVRAM (`~/Library/Application Support/OpenEmu/MAME/nvram/<driver>/`), typically created by a core build without pointer input. Recalibrate from the game's test menu (Service button), or reset the NVRAM while no game is running. This happened with `term2`.
