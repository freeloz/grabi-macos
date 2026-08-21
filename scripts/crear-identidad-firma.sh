#!/bin/zsh
# Crea la identidad de firma local estable de Grabi ("Grabi Dev") en el
# llavero de esta máquina. Se hace UNA VEZ por máquina de build.
#
# ¿Por qué? Firmar siempre con la MISMA identidad (no ad-hoc) hace que los
# permisos de TCC (pantalla/cámara/mic) persistan entre versiones: macOS
# ata el permiso al certificado, no al hash del binario.
#
# Cuando llegue la cuenta de Apple Developer, esta identidad se reemplaza
# por "Developer ID Application: …" cambiando SIGN_IDENTITY en
# make-interim-release.sh — nada más.
set -euo pipefail

IDENTITY="${1:-Grabi Dev}"

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "✅ La identidad \"$IDENTITY\" ya existe en el llavero."
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

# -legacy: el llavero de macOS no acepta el cifrado moderno de OpenSSL 3.
openssl pkcs12 -export -legacy -out "$WORK/identidad.p12" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -passout pass:grabi-temp -name "$IDENTITY" 2>/dev/null \
|| openssl pkcs12 -export -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
  -out "$WORK/identidad.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -passout pass:grabi-temp -name "$IDENTITY"

security import "$WORK/identidad.p12" -k ~/Library/Keychains/login.keychain-db \
  -P grabi-temp -T /usr/bin/codesign

# Confiar en el certificado para firma de código (puede pedir tu contraseña).
security add-trusted-cert -p codeSign -r trustRoot \
  -k ~/Library/Keychains/login.keychain-db "$WORK/cert.pem"

echo "✅ Identidad \"$IDENTITY\" creada y confiada."
echo "   La primera firma mostrará un diálogo de acceso a la llave → «Permitir siempre»."
