# UME-Core: MAME core plugin for OpenEmu.
# Everything is x86_64: OpenEmu.app is Intel-only and runs under Rosetta on Apple Silicon.
#
#   make dylib      builds MAME as mamearcade_headless.dylib (slow: ~20 min, ~5 GB)
#   make core       builds MAME.oecoreplugin (needs the dylib and an OpenEmu checkout, see OPENEMU_DIR)
#   make install    installs the plugin into OpenEmu's Cores folder
#   make release    zips the plugin, publishes a GitHub Release and updates appcast.xml
#
# Per-machine settings go in Config/Local.mk (not committed), for example:
#   OPENEMU_DIR = ../../openemu_ax/OpenEmu

ARCH  := x86_64
MINOS := 12.4
BUILD := build
MAME  := deps/mame
JOBS  := $(shell sysctl -n hw.ncpu)
OPENEMU_DIR ?= ../OpenEmu
ROMDIR      ?= $(HOME)/Library/Application Support/OpenEmu/Game Library/roms/Arcade
-include Config/Local.mk

# The plugin version is CFBundleVersion, which OpenEmu compares with the appcast. It lives in the xcconfig.
VERSION      := $(shell sed -n 's/^CURRENT_PROJECT_VERSION *= *//p' Config/Shared.xcconfig)
MAME_VERSION := $(shell sed -n 's/^MARKETING_VERSION *= *//p' Config/Shared.xcconfig)
REPO         := slioce/UME-Core

DYLIB    := $(MAME)/mamearcade_headless.dylib
SDK      := $(BUILD)/Release/OpenEmuBase.framework
PLUGIN   := $(BUILD)/Release/MAME.oecoreplugin
ZIP      := $(BUILD)/MAME_$(VERSION).zip
OE_CORES := $(HOME)/Library/Application Support/OpenEmu/Cores
TODAY    := $(shell date +%Y%m%d)

.PHONY: all dylib sdk core install dist appcast release romaudit clean

all: core

# MAME itself, with the headless OSD, as a dynamic library. PLATFORM=x86 forces an x86_64 build on an
# Apple Silicon host; without it the makefile follows `uname -m`. Delete build/osx_clang when switching arch.
dylib: $(DYLIB)

$(DYLIB):
	$(MAKE) -C $(MAME) macosx_x64_clang PLATFORM=x86 OSD=headless TARGETOS=macosx CONFIG=release \
	  TARGET=mame SUBTARGET=arcade MACOSX_DEPLOYMENT_TARGET=$(MINOS) -j$(JOBS)
	install_name_tool -id mamearcade_headless.dylib $@
	@test "$$(lipo -archs $@)" = "$(ARCH)" || { echo "$@ is not $(ARCH)"; exit 1; }

# OpenEmuBase.framework from the OpenEmu SDK, built next to the plugin so Xcode finds it in BUILT_PRODUCTS_DIR.
sdk: $(SDK)

$(SDK):
	xcodebuild -project $(OPENEMU_DIR)/OpenEmu-SDK/OpenEmu-SDK.xcodeproj -scheme OpenEmuBase -configuration Release \
	  ARCHS=$(ARCH) ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=$(MINOS) \
	  SYMROOT=$(CURDIR)/$(BUILD) CODE_SIGNING_ALLOWED=NO GCC_TREAT_WARNINGS_AS_ERRORS=NO build

# The plugin: MAMEGameCore linked against OpenEmuBase, with the dylib embedded in Contents/Frameworks and the
# license texts in Contents/Resources/legal (a build phase of the Xcode target).
# xcodebuild is incremental itself, so this always runs it rather than guessing from the bundle's mtime.
core: $(DYLIB) $(SDK)
	xcodebuild -project MAME.xcodeproj -target MAME -configuration Release \
	  SYMROOT=$(CURDIR)/$(BUILD) OPENEMU_DIR=$(abspath $(OPENEMU_DIR)) build -quiet
	@echo "Built $(PLUGIN) ($(VERSION))"

# Installing replaces a bundle OpenEmu has loaded, so refuse while it runs. The previous plugin is kept
# next to the new one as MAME.oecoreplugin.bak-YYYYMMDD (OpenEmu ignores that extension).
install: core
	@if pgrep -x OpenEmu >/dev/null; then echo "Quit OpenEmu before installing."; exit 1; fi
	@mkdir -p "$(OE_CORES)"
	@dest="$(OE_CORES)/MAME.oecoreplugin"; if [ -d "$$dest" ]; then rm -rf "$$dest.bak-$(TODAY)"; mv "$$dest" "$$dest.bak-$(TODAY)"; fi
	ditto "$(PLUGIN)" "$(OE_CORES)/MAME.oecoreplugin"
	@echo "Installed $(OE_CORES)/MAME.oecoreplugin ($(VERSION))"

# The release archive. OpenEmu's core updater treats the first entry of the zip as the plugin, so the
# bundle must sit at the root of the archive (--keepParent).
dist: $(ZIP)

$(ZIP): core
	rm -f $@
	ditto -c -k --keepParent "$(PLUGIN)" $@
	@echo "Built $@ ($$(du -h $@ | cut -f1))"

# appcast.xml is what OpenEmu polls (SUFeedURL in Info.plist) to offer the next version automatically.
appcast: $(ZIP)
	sh tools/make-appcast.sh "$(VERSION)" "$(REPO)" "$(ZIP)" "$(MINOS)" > appcast.xml
	xmllint --noout appcast.xml
	@echo "Wrote appcast.xml for $(VERSION)"

# Publish: push the current commit, create the GitHub Release v<VERSION> with the zip attached, then
# commit and push the appcast so that OpenEmu only sees the new version once the download exists.
release: $(ZIP)
	@git diff --quiet && git diff --cached --quiet || { echo "Commit your changes before releasing."; exit 1; }
	@git -C $(MAME) fetch -q origin && git -C $(MAME) merge-base --is-ancestor HEAD origin/mame0289-headless \
	  || { echo "Push the $(MAME) submodule first."; exit 1; }
	@! gh release view v$(VERSION) -R $(REPO) >/dev/null 2>&1 || { echo "v$(VERSION) is already released. Bump CURRENT_PROJECT_VERSION in Config/Shared.xcconfig."; exit 1; }
	git push origin HEAD
	printf '%s\n' \
	  "MAME $(MAME_VERSION) core for OpenEmu, plugin version $(VERSION)." "" \
	  "**Install:** download and unzip \`MAME_$(VERSION).zip\`, double-click \`MAME.oecoreplugin\`, let OpenEmu restart. Later versions install themselves through OpenEmu's core updater." "" \
	  "**Requirements:** OpenEmu 2.4.1, macOS $(MINOS) or later (Intel, or Apple Silicon through Rosetta)." "" \
	  "The plugin embeds MAME, licensed under the GPL-2.0-or-later. Corresponding source: https://github.com/slioce/mame/tree/$$(git -C $(MAME) rev-parse HEAD)" \
	  > $(BUILD)/notes.md
	gh release create v$(VERSION) -R $(REPO) --title "MAME $(VERSION)" --notes-file $(BUILD)/notes.md $(ZIP)
	$(MAKE) appcast
	git add appcast.xml
	git commit -m "Update appcast for $(VERSION)"
	git push origin HEAD
	@echo "Released https://github.com/$(REPO)/releases/tag/v$(VERSION)"

# Audits a folder of ROM sets with the same checks the core applies when loading a game.
romaudit: $(BUILD)/romaudit
	$(BUILD)/romaudit "$(ROMDIR)"

$(BUILD)/romaudit: tools/romaudit.m $(DYLIB)
	@mkdir -p $(BUILD)
	clang -arch $(ARCH) -fobjc-arc -framework Foundation -I $(MAME)/src/osd/headless/public \
	  $(DYLIB) -Wl,-rpath,$(CURDIR)/$(MAME) -o $@ $<
	install_name_tool -change mamearcade_headless.dylib @rpath/mamearcade_headless.dylib $@

clean:
	rm -rf $(BUILD)
