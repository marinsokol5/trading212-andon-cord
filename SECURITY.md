# Security policy

Trading212 Andon Cord can submit real-money market orders. Treat the CLI, the
`Trading212Trading` module, and every release artifact as security-sensitive.

## Reporting a vulnerability

Do not open a public issue for a credential leak, an order-safety defect, or a
way for the GUI to reach trading code. Contact the maintainer privately through
the security-reporting address configured on the repository. Include the
affected version, build variant, reproduction steps that use the Trading 212
Demo environment, and the smallest useful log with all account data removed.

Never include an API key, API secret, authorization header, portfolio snapshot,
receipt, or live account identifier in a report.

## Trust model

- `AndonApp` must not depend on or link `Trading212Trading`.
- Production read and trading credentials use distinct Keychain access groups;
  Demo-only development builds use distinct services in the login Keychain.
- A trading credential requires local user presence when read.
- Before sending credential JSON, the GUI verifies the nested CLI helper's code
  signature and same-signer identity (the shipping Team ID in production).
- The environment is fixed at compile time: development builds always target
  Demo and reject Live before credential or network access; production builds
  always target Live and must be selected explicitly at compile time. There is
  no runtime environment switch.
- Trade confirmation (Demo and Live alike) requires the exact typed phrase on
  a controlling terminal and cannot be piped.
- Order POSTs are non-idempotent and are never retried after an ambiguous
  result.
- The app has no telemetry and contacts only the build's official Trading 212
  API origin.

Before changing an order path, add or update an offline test that proves the
safety property. Exercise trading flows only against Demo. Review release
diffs and verify the signed app dependency graph before publishing.

## Local sensitive files

Snapshots, receipts, and audit records do not contain credentials, but they do
reveal financial information. Trading212 Andon Cord writes them with owner-only permissions
and crash-durable file/directory synchronization, and keeps them out of source
control. Do not attach them to bug reports without sanitizing them first.
