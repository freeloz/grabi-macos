#!/bin/zsh
# Creates Grabi's stable local signing identity ("Grabi Dev") in this
# machine's keychain. Done ONCE per build machine.
#
# Why? Always signing with the SAME identity (not ad-hoc) makes the TCC
# permissions (screen/camera/mic) persist across versions: macOS ties the
# permission to the certificate, not to the binary's hash.
#
# When the Apple Developer account arrives, this identity is replaced by
# "Developer ID Application: …" by changing SIGN_IDENTITY in
# make-interim-release.sh — nothing else.
set -euo pipefail

IDENTITY="${1:-Grabi Dev}"

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "✅ The identity \"$IDENTITY\" already exists in the keychain."
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:false
EOF

openssl req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -days 3650 -nodes -config "$WORK/cert.cnf"

# -legacy: the macOS keychain does not accept OpenSSL 3's modern encryption.
openssl pkcs12 -export -legacy -out "$WORK/identity.p12" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -passout pass:grabi-temp -name "$IDENTITY" 2>/dev/null \
|| openssl pkcs12 -export -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
  -out "$WORK/identity.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -passout pass:grabi-temp -name "$IDENTITY"

security import "$WORK/identity.p12" -k ~/Library/Keychains/login.keychain-db \
  -P grabi-temp -T /usr/bin/codesign

# Trust the certificate for code signing (may ask for your password).
security add-trusted-cert -p codeSign -r trustRoot \
  -k ~/Library/Keychains/login.keychain-db "$WORK/cert.pem"

echo "✅ Identity \"$IDENTITY\" created and trusted."
echo "   The first signing will show a key-access dialog → \"Always Allow\"."
