#!/bin/bash
# One-time setup: creates a self-signed code-signing certificate in your login keychain.
#
# Why: an ad-hoc signed app is identified by a hash of that exact build, so macOS forgets
# its Screen Recording permission after every rebuild. Signing every build with the same
# certificate gives Portion a stable identity, so the permission sticks.
#
# Usage: Scripts/make-signing-cert.sh            (build.sh then picks it up automatically)
set -euo pipefail

NAME="${1:-Portion Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# macOS's own LibreSSL writes .p12 files that `security import` understands
# (Homebrew's OpenSSL 3 uses ciphers it can't read).
OPENSSL=/usr/bin/openssl

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "Signing certificate \"$NAME\" already exists."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "==> Creating certificate \"$NAME\""
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null

PASS="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/identity.p12" -passout "pass:$PASS"

echo "==> Importing into your login keychain"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "==> Trusting it for code signing (macOS may ask for your password)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

security find-identity -v -p codesigning | grep "\"$NAME\""
echo "Done. ./build.sh will now sign with \"$NAME\"."
