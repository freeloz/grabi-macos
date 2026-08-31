#!/bin/zsh
# Builds and packages Grabi as a .app in dist/.
#
# Why a bundle? macOS attributes the TCC permissions (screen, camera,
# microphone) to the process's "responsible" app: a bare binary launched
# from Terminal inherits Terminal's permissions. With the bundle, the
# permissions belong to Grabi, like any normal app.
set -euo pipefail
cd "$(dirname "$0")"

# Dos ambientes, dos apps instalables a la vez:
#   ./make-app.sh                 → Grabi.app          · net.grabi.Grabi
#   ./make-app.sh release staging → Grabi Staging.app  · net.grabi.Grabi.staging
# Los permisos TCC y las preferencias se atribuyen al bundle ID, así que
# probar staging nunca toca la instalación de producción.
CONFIG="${1:-release}"
ENVIRONMENT="${2:-production}"

if [[ "$ENVIRONMENT" == "staging" ]]; then
  APP="dist/Grabi Staging.app"
  BUNDLE_ID="net.grabi.Grabi.staging"
  APP_NAME="Grabi Staging"
else
  APP=dist/Grabi.app
  BUNDLE_ID="net.grabi.Grabi"
  APP_NAME="Grabi"
fi

swift build -c "$CONFIG"

rm -rf "$APP" dist/RecordApp.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/RecordApp" "$APP/Contents/MacOS/Grabi"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Identidad por ambiente. La app de staging apunta sola al cloud de staging
# (GrabiCloudEnvironment en su Info.plist) — sin `defaults write` a mano.
if [[ "$ENVIRONMENT" == "staging" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :GrabiCloudEnvironment string staging" "$APP/Contents/Info.plist"
  # esquema propio para que el callback OAuth vuelva a ESTA app, no a la de producción
  /usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 grabi-staging" "$APP/Contents/Info.plist"
fi
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# SPM resource bundles (each target's Localizable.strings): Bundle.module
# looks for them in the .app's Contents/Resources.
BUILD_DIR=".build/$CONFIG"
for b in "$BUILD_DIR"/Record_*.bundle; do
  [[ -d "$b" ]] && cp -R "$b" "$APP/Contents/Resources/"
done
# Localized usage descriptions (TCC)
for l in Support/InfoPlist/*.lproj; do
  mkdir -p "$APP/Contents/Resources/$(basename "$l")"
  cp "$l/InfoPlist.strings" "$APP/Contents/Resources/$(basename "$l")/"
done

# Sparkle.framework (auto-updates) lives in Contents/Frameworks.
scripts/embed-sparkle.sh "$APP"

# Firma, en orden de preferencia:
#   1. Developer ID Application (Freeloz SAS, Team F6X8HM2S7A) — la de
#      distribución: hardened runtime + timestamp, lista para notarizar.
#   2. "Grabi Dev" (self-signed local) — interina: los permisos TCC
#      sobreviven a los rebuilds, pero macOS avisa que la app "está dañada".
#   3. Ad-hoc — último recurso: pide permisos de pantalla en cada build.
TEAM_ID="F6X8HM2S7A"
ENTITLEMENTS=Support/Grabi.entitlements

# --- Provisioning profile → Universal Links ---------------------------------
# associated-domains es una "capability": Apple solo la respeta si la app
# lleva dentro un provisioning profile que la autorice. Y si el entitlement
# va SIN perfil, launchd se niega a arrancar la app (error 163) aunque la
# firma sea impecable — comprobado el 28 ago 2026.
#
# Por eso el entitlement no vive en Grabi.entitlements: se añade aquí, y
# solo cuando hay perfil. Sin perfil el build sigue saliendo y funcionando,
# nada más que sin universal links (el esquema grabi:// no depende de esto).
#
# Los perfiles se bajan una vez de developer.apple.com → Profiles. El script
# los busca en Downloads y los archiva en Support/profiles/ para los
# siguientes builds.
PROFILE=""
find_profile() {
  local want="$TEAM_ID.$BUNDLE_ID" f appid
  # Se busca en los cuatro sitios por donde puede llegar un perfil, sin
  # obligar a nadie a moverlo de sitio: el archivo del repo, la descarga
  # manual del portal, y las dos carpetas donde Xcode deja los que baja con
  # "Download Manual Profiles" (la segunda es la ruta de Xcode antiguo).
  # (N): en zsh, un glob sin coincidencias se borra en vez de ser un error.
  for f in Support/profiles/*.provisionprofile(N) \
           ~/Downloads/*.provisionprofile(N) \
           ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.provisionprofile(N) \
           ~/Library/MobileDevice/Provisioning\ Profiles/*.provisionprofile(N); do
    [[ -f "$f" ]] || continue
    appid=$(security cms -D -i "$f" 2>/dev/null \
      | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null) || continue
    if [[ "$appid" == "$want" ]]; then
      # archivar el que llegó por Downloads, para no depender de esa carpeta
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
  # entitlements = los del repo + associated-domains, en un temporal
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

if [[ -n "$DEV_ID" ]]; then
  # Sparkle no es un framework plano: trae ejecutables anidados (Autoupdate y
  # Updater.app) que la notarización revisa POR SEPARADO. Firmar solo el
  # framework los deja sin Developer ID ni timestamp, y Apple devuelve
  # "Invalid" señalando cada uno — comprobado el 28 ago 2026.
  # Hay que ir de adentro hacia afuera: lo más profundo primero, porque cada
  # firma sella lo que contiene y firmar el contenedor antes invalida al hijo.
  SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
  for nested in \
      "$SPARKLE/Versions/B/Updater.app" \
      "$SPARKLE/Versions/B/Autoupdate" \
      "$SPARKLE"; do
    [[ -e "$nested" ]] || continue
    codesign --force --options runtime --timestamp \
      --sign "$DEV_ID" "$nested"
  done
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" --sign "$DEV_ID" "$APP"
  echo "Firmado para distribución: $DEV_ID"
  echo "   Siguiente paso: scripts/notarize.sh \"$APP\""
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "Grabi Dev"; then
  codesign --force --sign "Grabi Dev" "$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --sign "Grabi Dev" "$APP"
  echo "Firmado con la identidad interina: Grabi Dev (sin notarizar)"
else
  codesign --force --sign - "$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --sign - "$APP"
  echo "⚠️  Firma ad-hoc: macOS volverá a pedir el permiso de pantalla en cada build"
fi

echo "✅ Done: $APP  ($BUNDLE_ID)"
echo "Open it with: open \"$APP\""
