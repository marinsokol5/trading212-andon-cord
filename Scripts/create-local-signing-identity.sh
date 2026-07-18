#!/usr/bin/env bash
set -euo pipefail

IDENTITY="${1:-Trading212 Andon Cord Local Code Signing}"
DAYS="${T212_SIGNING_DAYS:-${ANDON_SIGNING_DAYS:-3650}}"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/t212-signing.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
PASSWORD="$(openssl rand -hex 16)"

if security find-identity -p codesigning | grep -Fq "$IDENTITY"; then
  echo "==> code-signing identity already exists: $IDENTITY"
  exit 0
fi

cat > "$TEMP/codesign.cnf" <<EOF
[ req ]
default_bits = 2048
distinguished_name = subject
x509_extensions = extensions
prompt = no
[ subject ]
CN = $IDENTITY
[ extensions ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

openssl req -new -newkey rsa:2048 -nodes -x509 -days "$DAYS" \
  -keyout "$TEMP/key.pem" -out "$TEMP/cert.pem" \
  -config "$TEMP/codesign.cnf" >/dev/null 2>&1
openssl pkcs12 -export -legacy -inkey "$TEMP/key.pem" -in "$TEMP/cert.pem" \
  -name "$IDENTITY" -out "$TEMP/identity.p12" \
  -passout "pass:$PASSWORD" >/dev/null 2>&1
security import "$TEMP/identity.p12" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" >/dev/null 2>&1 || true
security add-trusted-cert -r trustRoot -p codeSign "$TEMP/cert.pem" >/dev/null
security find-identity -v -p codesigning | grep -F "$IDENTITY"
