# Contributing

Trading212 Andon Cord is a Swift 6 package targeting macOS 14 or newer. Keep the two security
domains intact: app changes may depend on `Trading212Core`; only CLI and test
targets may depend on `Trading212Trading`.

## Development rules

1. Use development builds for all broker exercises: they are hard-wired to the
   Demo environment and reject Live by design; do not weaken that guard. The
   environment is fixed per build — there is no runtime switch to add flags or
   UI for.
2. Keep money and quantities as `Decimal`, never `Double`.
3. Inject network, credential, clock, sleep, prompt, and filesystem behavior.
   Unit tests must be offline and deterministic.
4. Never log credentials, authorization headers, snapshot contents, or account
   identifiers.
5. Never add an automatic retry for a submitted market order after timeout,
   connection loss, HTTP 408, or 5xx.
6. Keep `AndonApp` free of any dependency on `Trading212Trading`.

`make build` assembles a profile-free, isolated dev app signed with the
maintainer's identity (use `CODESIGN_ID=-` for an ad-hoc build), and
`make run` opens it. `swift test` runs offline unit tests. Developer ID
provisioning profiles are maintainer-only release inputs under `.signing/`;
contributors do not need them. `make release` is reserved for a reviewed
production release with the configured signing and notarization identity.
