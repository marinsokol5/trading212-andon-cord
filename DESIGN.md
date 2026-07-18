# Trading212 Andon Cord system design

Trading212 Andon Cord is an independent, local-only Trading 212 companion for macOS. One
Swift package produces a normal Mac app with a status item and a bundled
`t212` command-line tool. The app is permanently read-only; only the CLI can
link the order-placement library.

```text
AndonApp ───────────────> Trading212Core

t212 ─────────────────> Trading212Core
   └───────────────────> Trading212Trading
```

## Product boundary

Version 1 supports one Invest or Stocks ISA account in each Trading 212
environment. A read credential is required. A separately scoped trading
credential is optional and is retrieved only for an explicit CLI trading
command. There is no backend, telemetry, browser automation, IBKR support,
GUI trading, pie trading, live quote provider, or scheduled trading.

Each build targets exactly one environment; there is no runtime environment
picker in the GUI or CLI. Production builds always use Live and production
behavior is opt-in: only a build compiled with `ANDON_PROD` selects it.
Unmarked builds are the Demo-only development variant, which rejects Live
before any credential or network access. Development has a distinct bundle
identifier, workspace, defaults domain, and Keychain namespace. Apart from the
endpoint and the environment badge, the two variants present the same UI and
the same CLI workflow — including the exact typed `SELL ALL`/`BUY ALL`
confirmation, which Demo requires too. Supporting Demo and Live side by side
is deferred to a future multi-account design.

## Modules

- `Trading212Core` is the non-UI read domain. It owns public API read models
  and transport, Decimal-safe portfolio calculation, settings, cache,
  workspace, durable atomic files, formatting, and read credentials.
- `Trading212Trading` owns the market-order request and response types,
  canonical export/legacy snapshot codec, CLI-only trading credentials, pure
  sell/buy planners, confirmations, rate-limit pacing, sequential execution,
  receipts, and the redacted audit trail.
- `AndonApp` is a SwiftUI app with an AppKit-owned status item. It links Core
  only. It can configure a trading credential only by executing the bundled,
  signed CLI, verifying its signature/same-signer identity first, and writing
  a JSON request through an anonymous stdin pipe.
- `t212` is a thin parser and renderer over Core and Trading. JSON commands
  reserve stdout for schema output; diagnostics and prompts use stderr.

All money, quantities, weights, and prices use `Decimal`. Interfaces for HTTP,
files, clocks, sleeping, prompts, and credential storage are injectable so
tests never call the broker or place an order.

## Credential boundary

Production read and trading credentials use different Keychain services and
access groups, additionally namespaced by environment. The app and CLI share
the read group. Only the CLI helper is provisioned with the trading group. A
trading item is created with user-presence access control, so a trading command
requires Touch ID or the login password when retrieving it. Profile-free
development builds use distinct services in the user's login Keychain instead;
their Demo-only GUI and CLI can still share credentials without restricted
entitlements.

Credentials are never placed in command arguments, environment variables,
workspace files, receipts, audit records, or error descriptions. Read API
calls always use the read credential; they never fall back to the more
privileged credential.

## Broker contract

The current Trading 212 Public API v0 read path is:

- `GET /api/v0/equity/account/summary`
- `GET /api/v0/equity/positions`

Market orders use `POST /api/v0/equity/orders/market` with a signed quantity:
positive buys and negative sells. The endpoint is non-idempotent. A timeout,
connection loss, HTTP 408, or 5xx response after submission is ambiguous and
is never retried; execution stops before sending another order. HTTP 429 is
the sole resubmission case because the broker rejected the request before
execution. Live `x-ratelimit-*` headers determine pacing.

`quantityAvailableForTrading` is the maximum sell quantity. Shares reported
in `quantityInPies` are shown but never included in a plan. Position values and
weights use `walletImpact.currentValue`, which is already in account currency.

## Snapshots and recovery

The canonical `PortfolioSnapshotV1` is UTF-8 JSON with a namespaced schema,
explicit account/environment identity, distinct whole-account and sellable
totals, and every Decimal encoded as a string. Encoding is deterministic.
The decoder also accepts the historical `investing-andon-cord`
`portfolio.json` v1 shape and normalizes it in memory; new writes never emit
the legacy shape.

Before a real `sell-all` submits its first order, it durably and atomically writes a
`preSale` snapshot with mode `0600`, backing up an existing destination. A dry
run writes no snapshot, receipt, or audit record. During execution an atomic,
redacted receipt is synced before submission and after every definite broker
response. An ambiguous submission is recorded as such and terminates the sequence.

`buy-all` verifies snapshot version, environment, account, currency, duplicate
tickers, positive prices, and positive weights. It renormalizes the remaining
weights, applies a default one-percent cash buffer, derives quantities from
the saved account-currency price, and rounds down. Saved prices are stale by
design because Trading 212 exposes no quote endpoint for an unheld symbol.

## Safety invariants

Every mutating command shows the build's environment and the complete plan.
Real execution — in Demo exactly as in Live — always requires the exact phrase
`SELL ALL` or `BUY ALL` from a controlling terminal; piped stdin is refused.
Legacy snapshots require a separate unverified-identity acknowledgement. There
is no non-interactive bypass. Dry runs place zero orders and write nothing.
Market orders are sequential. Definite rejections and cancellations are
failures. Ambiguous failures stop the run and are never retried. Secrets and
authorization headers are redacted from all output.

## Distribution

The Makefile assembles a signed app bundle containing both executables and
signs nested code before the outer bundle. Development builds sign with the
maintainer's stable identity (no provisioning profiles) so login-keychain
items keep working across rebuilds; `CODESIGN_ID=-` falls back to ad-hoc for
anyone without the certificate. Production builds embed
separate Developer ID provisioning profiles for the GUI and CLI helper, and
support hardened-runtime notarized release zips. The Homebrew cask installs
`Trading212 Andon Cord.app` and links
`Contents/Helpers/T212CLI.app/Contents/MacOS/t212` onto `PATH`. Dev and
production bundles can be installed simultaneously without sharing state or
credentials.
