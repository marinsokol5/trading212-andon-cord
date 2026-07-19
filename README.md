<h1>
  <img src="Resources/AndonIcon.svg" width="32" alt="" align="center">
  Trading212 Andon Cord
</h1>

Trading212 Andon Cord is an open-source, native macOS companion for a Trading
212 Invest or ISA account. It shows the account in a normal SwiftUI app and the
menu bar, and ships a safety-focused `t212` command for snapshots and emergency
sell/buy-back workflows.

It is an independent project. It is not affiliated with, endorsed by, or
supported by Trading 212.

## Read this before enabling trading

`t212 sell-all` and `t212 buy-all` can submit **real market orders for real
money**. Market orders have price, spread, FX, tax, market-hours, and execution
risk. The software is provided without warranty. Inspect the plan it prints,
rehearse with a Demo-wired development build first, keep an independent broker
login available, and never treat the
snapshot as a guarantee that an order filled.

The safety rules are deliberately strict:

- The app binary links only `Trading212Core`; it contains no market-order client
  and has no path for retrieving a trading credential.
- In production, viewing and trading credentials are separate Keychain entries
  with separate access groups. The app receives only the viewing group; the
  bundled CLI receives both. Profile-free Demo development uses isolated local
  Keychain services instead.
- A real `sell-all` writes a `0600` pre-sale snapshot before the first order.
- Every mutating command prints the complete plan and the build's environment.
- Real execution requires typing the exact phrase `SELL ALL` or `BUY ALL` on a
  controlling terminal — in Demo exactly as in Live, so a rehearsal exercises
  the same workflow. Piped input is refused; there is no `--yes` or other
  non-interactive bypass.
- Orders are sequential. A timeout, lost connection, or 5xx response is
  ambiguous: Trading212 Andon Cord never retries it and sends no later order. Verify broker
  state manually before doing anything else. A pre-execution 429 is the one
  safe retry case.
- Pie-locked shares are reported and excluded. Trading212 Andon Cord trades only quantities the
  API marks available for trading.
- Secrets and Authorization headers are redacted from diagnostics. There is no
  telemetry, backend, analytics, credential sync, or browser scraping.

## Requirements

- macOS 14 Sonoma or later
- A Trading 212 Invest or ISA account with API (Beta) access
- A viewing API key with the Account data and Portfolio permissions
- For trading commands only, a separate key that also has the order permission

CFD accounts, pie trading, limit/stop orders, multiple accounts, live quotes for
unheld instruments, and other brokers are outside v1.

## Install

The release cask installs the app and exposes the CLI bundled inside its signed
app:

```sh
brew install --cask marinsokol5/tap/trading212-andon-cord
open -a "Trading212 Andon Cord"
t212 --help
```

Release archives are signed with Developer ID, hardened, notarized, and stapled.
The repository and tap names in this initial scaffold are
`marinsokol5/trading212-andon-cord` and `marinsokol5/homebrew-tap`; change the centralized
release values before publishing under another owner.

## Set up the app

1. In Trading 212, open Settings → API (Beta) → **Generate API key**, enable
   the **Account data** and **Portfolio** permissions, and generate the key.
   Trading 212 shows an API key ID and a secret key.
2. On the app's **Account** screen (the first sidebar route, and where a fresh
   install opens), paste the API key ID and secret key, then select
   **Validate & Save**. The environment is fixed by the build — a release
   install always uses Live, a development build always uses Demo — so create
   the key on the matching side of Trading 212. Trading212 Andon Cord exercises the read
   endpoints before it replaces a working Keychain value.
3. On the **Settings** screen, choose refresh cadence and menu-bar
   layout/formatting, and optionally enable Launch at Login.

The window is organized as sidebar routes: **Account** (the build's fixed environment and keys),
**Portfolio** (value and key metrics), **Positions** (sortable table with the
sellable/pie split), **Snapshots** (read-only browser of CLI snapshot files),
and **Settings**.

The value appears from the last good cache immediately at future launches, then
refreshes in the background. A transient failure leaves that last value on
screen and shows a freshness warning. HTTP 429 responses use bounded
exponential backoff and the broker's retry/reset headers.

Privacy mode hides financial values in every route, the Settings preview,
positions, snapshots, the status-item menu, and menu-bar item. Toggle it from any surface or with the global
shortcut, which defaults to **Command–Option–P** and is configurable. The
shortcut uses the macOS Carbon hot-key API and does not require Accessibility
permission. Privacy does not alter explicit terminal output or exported files.

### Optional trading credential

The app's Account screen is the simplest setup path. For a caller that can safely
produce one JSON object on an anonymous pipe, the equivalent CLI is:

```sh
t212 credentials set-trading
```

Write one JSON object to stdin when automating that prompt shape:

```json
{"key":"…","secret":"…"}
```

Do not put either value in command arguments, environment variables, or a disk
file. The Account screen offers the same setup: it executes the signed bundled
CLI directly (never a shell), first verifies its code signature and signer,
sends exactly that JSON over an anonymous stdin pipe, closes the pipe, and
retains no trading credential. Production refuses an unsigned sibling
executable. Trading 212 does not
provide safe scope introspection, so setup can validate account/environment
identity but cannot prove order scope without placing an order; setup never
places one.

## CLI

There are no environment flags: the environment is fixed at compile time.
Production builds always use Live; development builds are compile-time
restricted to Demo and cannot construct a Live client at all. Every real
execution — Demo included — requires the exact typed phrase on a controlling
terminal; there is no `--yes` bypass.

```text
t212 account
t212 portfolio
t212 portfolio --json
t212 portfolio --output FILE
t212 snapshot view --input FILE

t212 credentials status [--json]
t212 credentials set-trading
t212 credentials delete

t212 sell-all [--output FILE] [--dry-run]
t212 buy-all --input FILE [--cash-fraction 0.99]
              [--min-order 1] [--precision 6] [--dry-run]
```

Read commands use only the viewing credential. `portfolio --json` emits the
stable snapshot schema on stdout; `--output` writes it atomically with mode
`0600`. Keep machine-readable stdout clean by sending diagnostics to stderr.

`--dry-run` reads and plans but places zero orders and writes no snapshot or
receipt. A real `sell-all` snapshots first, retrieves the trading credential
once with user presence, and writes an incremental non-secret receipt after
every definite broker response. A broker `REJECTED` or `CANCELLED` result is a
failure, never silent success.

### Snapshot contract

New files use the namespaced schema
`com.marinsokol.trading212andoncord.portfolio-snapshot`,
version 1. Decimal values are JSON strings, not binary floating-point numbers.
The file records environment, account identity/currency, whole-account value,
free cash, sellable total, and each position's sellable/pie quantities,
account-currency stale price, value, and sellable-only weight.

`buy-all` rejects unknown versions, malformed decimals, duplicate tickers,
wrong account/environment, and non-positive prices or weights. Because Trading
212 exposes no live quote endpoint for an unheld instrument, buy-back quantities
use saved prices, normalize the remaining weights, reserve the requested cash
fraction, and round down to the requested precision. Deleting a holding from a
copy of a snapshot intentionally excludes it and renormalizes the rest.

A one-way decoder can read validated legacy `portfolio.json` v1 snapshots from
the original portfolio tool. Since those files contain no account ID, a real
buy-back requires a second exact `USE UNVERIFIED LEGACY SNAPSHOT`
acknowledgement. Text view is available, but `snapshot view --json` refuses to
misrepresent a legacy file as verified canonical JSON. New output always uses
the richer namespaced schema and never rewrites a legacy source silently.

## How it works

The package has four targets and two explicit trust domains:

```text
Trading212Core       read API, Decimal models, cache/settings, read Keychain
Trading212Trading    snapshot codec, plans, trading vault, orders, receipts
AndonApp             SwiftUI/AppKit GUI; depends Trading212Core only
t212                 terminal surface; depends Core + Trading
```

The read client uses the current Trading 212 v0 endpoints:

- `GET /api/v0/equity/account/summary`
- `GET /api/v0/equity/positions`

The CLI's trading library alone contains:

- `POST /api/v0/equity/orders/market`

Authentication is HTTP Basic over TLS. Money and quantities use Swift
`Decimal` end to end. The menu-bar item is one baked `NSImage` containing the
mark/label and value, allowing macOS template tinting and menu-open inversion to
apply to the entire item consistently.

## Local data

Non-secret state is variant-separated under:

```text
~/Library/Application Support/Trading212AndonCord/
~/Library/Application Support/Trading212AndonCord-dev/
```

The workspace contains settings/account metadata, last-good cache, snapshots,
receipts, and a redacted audit log. Files with portfolio/order data are written
with owner-only modes, file synchronization, atomic rename, and directory
synchronization; directories are mode `0700`. Secrets never live there. Live
and Demo credentials occupy distinct Keychain accounts.

The development and production variants also have different bundle IDs,
preference domains, Keychain services, process names, status-item autosave
names, bundle paths, and workspace directories. Production additionally uses
profile-authorized access groups. The variants can remain installed and
running together.

## Build and release

The safe local default is the Demo-only development variant:

```sh
swift build                # also Demo-only; production is never the fallback
make build                 # .build/Trading212AndonCord-dev.app
make run
make test                  # offline unit tests only
make print-identity
```

Builds use Swift 6 language mode with complete strict concurrency checking and
have no third-party package dependencies. `make build` assembles a real app
bundle and nests `t212` at
`Contents/Helpers/T212CLI.app/Contents/MacOS/t212`. Development is Demo-only
and uses the local login Keychain without restricted access groups, so no
provisioning profile is needed. Dev builds sign with the maintainer's stable
identity so login-keychain items survive rebuilds without re-prompting; a
contributor without that certificate can build ad-hoc with
`make build CODESIGN_ID=-` (each ad-hoc rebuild then re-prompts for Keychain
access, since ad-hoc signatures have no stable identity).

Production keeps the stronger binary-level Keychain boundary: the GUI claims
only the read group, while the CLI helper claims read and trading groups. Put
the two Developer ID direct-distribution profiles at:

```text
.signing/app.provisionprofile
.signing/cli.provisionprofile
```

The build validates their bundle IDs, Team ID, platform, distribution type,
and Keychain allowance before embedding and signing them. `.signing/` is
ignored and is needed only by the release maintainer.

Store notarization credentials once:

```sh
xcrun notarytool store-credentials trading212-andon-cord \
  --apple-id you@example.com --team-id H33MHC4C79
```

Then:

```sh
make release               # tests, hardened prod build, notarize, staple, zip
make verify VARIANT=prod CONFIG=release
make publish               # release + GitHub + Homebrew tap cask update
```

`make publish V=0.1.1` first updates the Info.plist version. `REPO`, `TAP_DIR`,
`NOTES`, `YES`, and `ALLOW_DIRTY` customize the publishing script. The cask
installs `Trading212 Andon Cord.app` and links
`Trading212 Andon Cord.app/Contents/Helpers/T212CLI.app/Contents/MacOS/t212`
onto `PATH`—there is only one signed CLI binary to audit and ship.

## License

[MIT](LICENSE) © 2026 Marin Sokol
