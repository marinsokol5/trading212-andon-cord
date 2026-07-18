# Local development identity. Keep in lockstep with Trading212Core.AppVariant.
# Dev builds sign with the maintainer's stable identity so rebuilds keep the
# same code-signature identity and login-keychain items stop prompting on every
# rebuild (ad-hoc signatures change per build). No restricted Keychain groups
# are claimed, so no provisioning profile is needed. A contributor without this
# certificate can still build ad-hoc with `make build CODESIGN_ID=-`.
APP_NAME := Trading212 Andon Cord (Dev)
APP_BASENAME := Trading212AndonCord-dev
EXEC_NAME := Trading212AndonCord-dev
BUNDLE_ID := com.marinsokol.trading212andoncord.dev
CLI_BUNDLE_ID := com.marinsokol.trading212andoncord.dev.cli
WORKSPACE_NAME := Trading212AndonCord-dev
READ_KEYCHAIN_GROUP := H33MHC4C79.com.marinsokol.trading212andoncord.dev.read
TRADE_KEYCHAIN_GROUP := H33MHC4C79.com.marinsokol.trading212andoncord.dev.trade
STATUS_AUTOSAVE_NAME := com.marinsokol.trading212andoncord.dev.status
SWIFT_VARIANT_FLAGS :=
DEFAULT_CODESIGN_ID := Developer ID Application: Marin Sokol (H33MHC4C79)
USES_PROFILES := 0
