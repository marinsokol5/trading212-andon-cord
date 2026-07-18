# `dev` is the safe default. It is Demo-only, profile-free, signed with the
# maintainer's stable identity (override with CODESIGN_ID=- for ad-hoc), and
# isolated from the Homebrew production app's preferences, workspace, and Keychain.
VARIANT ?= dev
ifneq ($(filter $(VARIANT),dev prod),$(VARIANT))
$(error VARIANT must be dev or prod)
endif
include Support/Identity.$(VARIANT).mk

CLI_EXEC_NAME := t212
CLI_HELPER_BASENAME := T212CLI
GUI_EXEC_NAME_CASEFOLDED := $(shell /bin/echo "$(EXEC_NAME)" | /usr/bin/tr '[:upper:]' '[:lower:]')
ifeq ($(GUI_EXEC_NAME_CASEFOLDED),$(CLI_EXEC_NAME))
$(error EXEC_NAME must not case-insensitively collide with the bundled $(CLI_EXEC_NAME) CLI)
endif

CONFIG ?= debug
BIN_DIR := .build/$(CONFIG)
APP_BUNDLE := .build/$(APP_BASENAME).app
CONTENTS := $(APP_BUNDLE)/Contents
CLI_APP_BUNDLE := $(CONTENTS)/Helpers/$(CLI_HELPER_BASENAME).app
CLI_CONTENTS := $(CLI_APP_BUNDLE)/Contents
CLI_EXECUTABLE := $(CLI_CONTENTS)/MacOS/$(CLI_EXEC_NAME)

CODESIGN_ID ?= $(DEFAULT_CODESIGN_ID)
CODESIGN_FLAGS ?=
NOTARY_PROFILE ?= trading212-andon-cord
APP_PROFILE ?= .signing/app.provisionprofile
CLI_PROFILE ?= .signing/cli.provisionprofile

VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist.in)
RELEASE_ZIP := .build/Trading212-Andon-Cord-$(VERSION).zip
PROD_APP_BUNDLE := .build/Trading212 Andon Cord.app
APP_ENTITLEMENTS := .build/Trading212AndonCord-$(VARIANT).entitlements
CLI_ENTITLEMENTS := .build/t212-$(VARIANT).entitlements
CLI_INFO_PLIST := .build/T212CLI-$(VARIANT)-Info.plist

.PHONY: build run package test release publish verify icon clean print-identity check-profiles screenshots screenshots-real

ifeq ($(USES_PROFILES),1)
build: check-profiles
endif

build: Support/Andon.icns
	swift build -c $(CONFIG) $(SWIFT_VARIANT_FLAGS)
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources" "$(CLI_CONTENTS)/MacOS"
	sed -e 's/__BUNDLE_ID__/$(BUNDLE_ID)/g' -e 's/__APP_NAME__/$(APP_NAME)/g' \
		-e 's/__EXEC_NAME__/$(EXEC_NAME)/g' \
		-e 's/__READ_KEYCHAIN_GROUP__/$(READ_KEYCHAIN_GROUP)/g' \
		-e 's/__TRADE_KEYCHAIN_GROUP__/$(TRADE_KEYCHAIN_GROUP)/g' \
		Support/Info.plist.in > "$(CONTENTS)/Info.plist"
	sed -e 's/__BUNDLE_ID__/$(CLI_BUNDLE_ID)/g' -e 's/__APP_NAME__/t212/g' \
		-e 's/__EXEC_NAME__/$(CLI_EXEC_NAME)/g' \
		Support/CLI-Info.plist.in > "$(CLI_INFO_PLIST)"
	cp "$(CLI_INFO_PLIST)" "$(CLI_CONTENTS)/Info.plist"
	cp Support/Andon.icns "$(CONTENTS)/Resources/Andon.icns"
	cp "$(BIN_DIR)/AndonApp" "$(CONTENTS)/MacOS/$(EXEC_NAME)"
	cp "$(BIN_DIR)/$(CLI_EXEC_NAME)" "$(CLI_EXECUTABLE)"
ifeq ($(USES_PROFILES),1)
	sed -e 's/__TEAM_ID__/H33MHC4C79/g' -e 's/__BUNDLE_ID__/$(BUNDLE_ID)/g' \
		-e 's/__READ_KEYCHAIN_GROUP__/$(READ_KEYCHAIN_GROUP)/g' \
		Support/AndonApp.entitlements.in > "$(APP_ENTITLEMENTS)"
	sed -e 's/__TEAM_ID__/H33MHC4C79/g' -e 's/__BUNDLE_ID__/$(CLI_BUNDLE_ID)/g' \
		-e 's/__READ_KEYCHAIN_GROUP__/$(READ_KEYCHAIN_GROUP)/g' \
		-e 's/__TRADE_KEYCHAIN_GROUP__/$(TRADE_KEYCHAIN_GROUP)/g' \
		Support/andon.entitlements.in > "$(CLI_ENTITLEMENTS)"
	cp -X "$(APP_PROFILE)" "$(CONTENTS)/embedded.provisionprofile"
	cp -X "$(CLI_PROFILE)" "$(CLI_CONTENTS)/embedded.provisionprofile"
	xattr -c "$(CONTENTS)/embedded.provisionprofile"
	xattr -c "$(CLI_CONTENTS)/embedded.provisionprofile"
	codesign --force $(CODESIGN_FLAGS) --entitlements "$(CLI_ENTITLEMENTS)" \
		--sign "$(CODESIGN_ID)" "$(CLI_APP_BUNDLE)"
	codesign --force $(CODESIGN_FLAGS) --entitlements "$(APP_ENTITLEMENTS)" \
		--sign "$(CODESIGN_ID)" "$(APP_BUNDLE)"
else
	codesign --force --sign "$(CODESIGN_ID)" "$(CLI_APP_BUNDLE)"
	codesign --force --sign "$(CODESIGN_ID)" "$(APP_BUNDLE)"
endif
	@echo "==> built $(APP_BUNDLE) ($(VARIANT))"

run: build
	pkill -f "$(APP_BUNDLE)/Contents/MacOS/$(EXEC_NAME)" 2>/dev/null || true
	@# Wait for the old instance to fully exit; `open` while it is still dying
	@# makes LaunchServices target the terminating process and fail with -600.
	@while pgrep -f "$(APP_BUNDLE)/Contents/MacOS/$(EXEC_NAME)" >/dev/null; do sleep 0.1; done
	open "$(APP_BUNDLE)"

test:
	swift test $(SWIFT_VARIANT_FLAGS)

# Offscreen PNGs of every route in light and dark, written to screenshots/.
# `screenshots` renders deterministic fixture data; `screenshots-real` uses
# your saved viewing key and one live portfolio fetch (read-only).
screenshots:
	swift build -c $(CONFIG) $(SWIFT_VARIANT_FLAGS)
	"$(BIN_DIR)/AndonApp" --screenshots --output screenshots

screenshots-real:
	swift build -c $(CONFIG) $(SWIFT_VARIANT_FLAGS)
	"$(BIN_DIR)/AndonApp" --screenshots --real --output screenshots

check-profiles:
	/bin/bash Scripts/verify-provisioning-profile.sh "$(APP_PROFILE)" "$(BUNDLE_ID)" H33MHC4C79
	/bin/bash Scripts/verify-provisioning-profile.sh "$(CLI_PROFILE)" "$(CLI_BUNDLE_ID)" H33MHC4C79

# A production-signed bundle without notarization, useful for local inspection.
package:
	$(MAKE) build VARIANT=prod CONFIG=release CODESIGN_FLAGS="--options runtime --timestamp"

release:
	mkdir -p .build
	swift test -Xswiftc -DANDON_PROD
	$(MAKE) build VARIANT=prod CONFIG=release CODESIGN_FLAGS="--options runtime --timestamp"
	rm -f "$(RELEASE_ZIP)"
	ditto -c -k --keepParent "$(PROD_APP_BUNDLE)" "$(RELEASE_ZIP)"
	xcrun notarytool submit "$(RELEASE_ZIP)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(PROD_APP_BUNDLE)"
	xcrun stapler validate "$(PROD_APP_BUNDLE)"
	rm -f "$(RELEASE_ZIP)"
	ditto -c -k --keepParent "$(PROD_APP_BUNDLE)" "$(RELEASE_ZIP)"
	@echo "==> notarized and stapled: $(RELEASE_ZIP)"

publish:
	Scripts/publish.sh $(V)

verify:
	codesign --verify --deep --strict --verbose=2 "$(APP_BUNDLE)"
ifeq ($(USES_PROFILES),1)
	spctl --assess --type execute --verbose=2 "$(APP_BUNDLE)"
endif
	"$(CLI_EXECUTABLE)" --version

Support/Andon.icns: Scripts/render-icon.swift
	mkdir -p .build
	swiftc -O -parse-as-library Scripts/render-icon.swift -o .build/render-andon-icon
	.build/render-andon-icon "$@"

icon: Support/Andon.icns

print-identity:
	@echo "variant: $(VARIANT)"
	@echo "app:     $(APP_NAME)"
	@echo "bundle:  $(BUNDLE_ID)"
	@echo "cli:     $(CLI_BUNDLE_ID)"
	@echo "state:   $(WORKSPACE_NAME)"

clean:
	swift package clean
	rm -rf ".build/Trading212 Andon Cord.app" .build/Trading212AndonCord-dev.app
