#!/bin/zsh
# Firma un Grabi.app para distribución. Única fuente de verdad: la usan
# make-app.sh (build de trabajo) y make-interim-release.sh (el DMG que se
# publica).
#
# Existe porque los dos scripts tenían su propia copia de la firma y
# divergieron: todo lo aprendido el 28-31 ago (perfil embebido, binarios
# anidados de Sparkle, timestamp) vivía solo en make-app.sh, así que el DMG
# que descargaban los usuarios seguía saliendo con la identidad interina.
#
# Uso: scripts/sign-app.sh <ruta/Grabi.app> <bundle-id>
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: sign-app.sh <Grabi.app> <bundle-id>}"
BUNDLE_ID="${2:?usage: sign-app.sh <Grabi.app> <bundle-id>}"
TEAM_ID="F6X8HM2S7A"
ENTITLEMENTS=Support/Grabi.entitlements

# --- Provisioning profile → Universal Links ---------------------------------
# associated-domains es una "capability": Apple solo la respeta si la app
# lleva dentro un perfil que la autorice. Y si el entitlement va SIN perfil,
# launchd se niega a arrancar la app (error 163) aunque la firma sea
# impecable. Por eso el entitlement se inyecta aquí y solo cuando hay perfil.
PROFILE=""
find_profile() {
  local want="$TEAM_ID.$BUNDLE_ID" f appid
  # Todos los sitios por donde puede llegar un perfil, sin obligar a moverlo:
  # el archivo del repo, ~/.grabi/secrets, la descarga manual del portal, y
  # las dos carpetas donde Xcode deja los de "Download Manual Profiles".
  # (N): en zsh, un glob sin coincidencias se borra en vez de ser un error.
  for f in Support/profiles/*.provisionprofile(N) \
           ~/.grabi/secrets/*.provisionprofile(N) \
           ~/Downloads/*.provisionprofile(N) \
           ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.provisionprofile(N) \
           ~/Library/MobileDevice/Provisioning\ Profiles/*.provisionprofile(N); do
    [[ -f "$f" ]] || continue
    # Los perfiles de macOS guardan el App ID en com.apple.application-identifier;
    # los de iOS en application-identifier a secas. Se prueban los dos, con los
    # puntos escapados porque plutil los trata como separador de ruta.
    appid=$(security cms -D -i "$f" 2>/dev/null | plutil \
      -extract 'Entitlements.com\.apple\.application-identifier' raw -o - - 2>/dev/null) \
      || appid=$(security cms -D -i "$f" 2>/dev/null | plutil \
      -extract 'Entitlements.application-identifier' raw -o - - 2>/dev/null) \
      || continue
    if [[ "$appid" == "$want" ]]; then
      if [[ "$f" != Support/profiles/* ]]; then
        mkdir -p Support/profiles
        cp "$f" "Support/profiles/$BUNDLE_ID.provisionprofile"
        f="Support/profiles/$BUNDLE_ID.provisionprofile"
      fi
      PROFILE="$f"
      return 0
    fi
  done
  return 1
}

DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o "Developer ID Application: [^\"]*($TEAM_ID)" | head -1) || true

# El perfil solo vale firmado con el certificado que lo respalda: si vamos a
# caer a "Grabi Dev", ni perfil ni entitlement (volveríamos al error 163).
if [[ -n "$DEV_ID" ]] && find_profile; then
  cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
  ENTITLEMENTS=$(mktemp -t grabi-entitlements).plist
  cp Support/Grabi.entitlements "$ENTITLEMENTS"
  /usr/libexec/PlistBuddy \
    -c "Add :com.apple.developer.associated-domains array" \
    -c "Add :com.apple.developer.associated-domains:0 string applinks:app.grabi.net" \
    "$ENTITLEMENTS" >/dev/null
  echo "Universal Links activos (perfil: $PROFILE)"
elif [[ -n "$DEV_ID" ]]; then
  echo "Sin provisioning profile para $BUNDLE_ID → build sin universal links."
  echo "   Bájalo de developer.apple.com → Profiles y vuelve a compilar."
fi

# Sparkle no es un framework plano: trae ejecutables anidados (Autoupdate y
# Updater.app) que la notarización revisa POR SEPARADO. Firmar solo el
# framework los deja sin Developer ID ni timestamp y Apple devuelve "Invalid".
# Se va de adentro hacia afuera: cada firma sella lo que contiene, así que
# firmar el contenedor antes invalidaría al hijo.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign_sparkle() {
  local nested
  for nested in "$SPARKLE/Versions/B/Updater.app" \
                "$SPARKLE/Versions/B/Autoupdate" \
                "$SPARKLE"; do
    [[ -e "$nested" ]] || continue
    codesign --force "$@" --sign "$SIGN_WITH" "$nested"
  done
}

if [[ -n "$DEV_ID" ]]; then
  SIGN_WITH="$DEV_ID"
  sign_sparkle --options runtime --timestamp
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" --sign "$DEV_ID" "$APP"
  echo "Firmado para distribución: $DEV_ID"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "Grabi Dev"; then
  SIGN_WITH="Grabi Dev"
  sign_sparkle
  codesign --force --sign "Grabi Dev" "$APP"
  echo "Firmado con la identidad interina: Grabi Dev (sin notarizar)"
else
  SIGN_WITH="-"
  sign_sparkle
  codesign --force --sign - "$APP"
  echo "⚠️  Firma ad-hoc: macOS volverá a pedir el permiso de pantalla en cada build"
fi

codesign --verify --strict "$APP" && echo "Firma verificada: OK"
