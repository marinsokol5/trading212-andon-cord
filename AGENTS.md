# AGENTS.md

Guidance for AI coding agents and human contributors working in this repository.
The deep material lives in [DESIGN.md](DESIGN.md), [SECURITY.md](SECURITY.md),
and [CONTRIBUTING.md](CONTRIBUTING.md); this file captures the working
agreements and the commands.

## What this is

Trading212 Andon Cord: a local-first macOS app + menu bar for **read-only**
monitoring of a Trading 212 portfolio, with a deliberately separate bundled
`t212` CLI that is the only surface able to place orders (sell-all / buy-back,
exact Live confirmation phrases). Swift 6 package, macOS 14+, no dependencies.

## Layout and the one hard boundary

```
Sources/
  Trading212Core/     Read-only API client, models, settings, workspace files.
  Trading212Trading/  Snapshots, planners, market orders, trading credentials.
  AndonApp/           SwiftUI/AppKit app — sidebar routes over AppModel.
  andon/              The `t212` CLI (links Core + Trading).
```

`AndonApp` must **never** link `Trading212Trading`. The GUI has no
order-placement code and cannot read the trading credential; anything that
would need trading types in the app (e.g. the Snapshots screen) re-decodes
display fields locally instead. Keep it that way.

## Build and verify

```sh
swift build                                    # dev variant (Demo-only, fail-closed)
swift build --build-tests                      # compile tests too
swift build --build-tests -Xswiftc -DANDON_PROD  # production variant
make build / make run / make test              # bundled .app workflows
```

Plain builds are development builds: Live is compile-time rejected. Do not
"fix" that. Never place orders, never call the Live API, and never run `t212`
trading commands as part of verification.

## Screenshot harness — how agents see the UI

The app binary doubles as its own screenshot tool. After **any** UI change,
regenerate and actually look at the PNGs (they are readable images) instead of
reasoning blind about layout:

```sh
make screenshots                # fixture data → screenshots/fixture/{light,dark}/*.png
.build/debug/AndonApp --screenshots --output <dir>            # same, direct
.build/debug/AndonApp --screenshots --size 940x620 --output <dir>  # min-window check
make screenshots-real           # --real: the user's saved key + one live fetch
```

- Every sidebar route is captured in light and dark, plus the status-item
  menu's header view and a privacy-mode portfolio shot. Implementation:
  `ScreenshotHarness.swift`
  (offscreen `NSHostingView` render; no window ever appears).
- Fixture mode is deterministic and safe: in-memory stores, stub credentials,
  no Keychain/network/workspace access. Run it freely.
- `--real` uses the user's actual viewing key (Demo-only in dev builds) and can
  trigger a Keychain prompt — leave it to the user unless they ask.
- 940×620 is the window minimum; capture at that size when touching the
  Positions table or anything width-sensitive. The table clips overflowing
  columns rather than compressing, so keep `TableColumn` ideal widths equal to
  their minimums.
- `screenshots/` is gitignored (real shots contain real account values).

## Conventions

- `Decimal` for all money/quantities; no `Double` in financial paths.
- Fail closed: schema drift, ambiguous order results, and missing fields are
  errors, not defaults.
- New GUI state flows through `AppModel` (`@Observable`, MainActor); routes are
  `AppRoute` cases rendered by `RootView` + `SidebarView`.
- Design tokens live in `Sources/AndonApp/Theme.swift` — no inline hex/point
  literals in views; red is reserved for LIVE/destructive meaning.
