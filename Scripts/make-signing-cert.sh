#!/bin/bash
# One-time setup: creates a self-signed code-signing certificate in a dedicated keychain.
#
# Why a certificate: an ad-hoc signed app is identified by a hash of that exact build, so
# macOS forgets its Screen Recording permission after every rebuild. Signing every build
# with the same certificate gives Portion a stable identity, so the permission sticks.
#
# Why a dedicated keychain: signing from the login keychain makes macOS ask for the login
# keychain password, which on managed Macs often no longer matches the Mac password. This
# keychain has its own random password, saved next to it, so build.sh can unlock it
# without ever prompting. It only holds this local, self-signed certificate.
#
# Usage: Scripts/make-signing-cert.sh            (build.sh then picks it up automatically)
set -euo pipefail

NAME="Portion Signing"
KEYCHAIN="$HOME/Library/Keychains/portion-signing.keychain-db"
PASS_FILE="$HOME/Library/Application Support/Portion/signing-keychain-password"
# macOS's own LibreSSL writes .p12 files that `security import` understands
# (Homebrew's OpenSSL 3 uses ciphers it can't read).
OPENSSL=/usr/bin/openssl

if [ -f "$KEYCHAIN" ] && [ -f "$PASS_FILE" ] &&
   security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
  echo "Signing certificate \"$NAME\" already exists in $KEYCHAIN."
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

P12_PASS="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/identity.p12" -passout "pass:$P12_PASS"

echo "==> Creating keychain $KEYCHAIN"
mkdir -p "$(dirname "$PASS_FILE")"
rm -f "$KEYCHAIN"
KC_PASS="$("$OPENSSL" rand -hex 24)"
(umask 077 && printf '%s' "$KC_PASS" > "$PASS_FILE")
security create-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"   # never auto-lock

echo "==> Importing the certificate"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null
# Let codesign use the key without a "wants to access key" prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null

security find-identity -p codesigning "$KEYCHAIN" | grep "\"$NAME\""
echo "Done. ./build.sh will now sign with \"$NAME\"."
