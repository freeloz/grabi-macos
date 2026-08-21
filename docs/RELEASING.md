# Releasing Grabi (macOS)

One command publishes everything:

```bash
./scripts/publish-release.sh
```

It builds and signs the app ("Grabi Dev" + hardened runtime), creates the
DMG, signs the update with the **Sparkle EdDSA key**, uploads the versioned
DMG + checksums + `latest.json` + `appcast.xml` to R2 (`dl.grabi.net`),
verifies byte-for-byte what the CDN serves, and creates the GitHub Release.

## Before publishing a version

1. Bump `CFBundleShortVersionString` **and** `CFBundleVersion` in
   `Support/Info.plist` (`CFBundleVersion` must strictly increase — it is
   what Sparkle compares).
2. Write the release notes at `releases/v<version>/notes.en.html`
   (optional `notes.es.html`, `notes.pt.html`, `notes.fr.html`,
   `notes.de.html` — Sparkle shows the user's language when present).
3. Run the script. Done.

## The update feed

- **Canonical source: `https://dl.grabi.net/macos/appcast.xml`** (Sparkle).
  `latest.json` is *derived* from the same release data by the same script
  run — it exists for the website and Homebrew livecheck. Never edit either
  by hand; a release is the only thing that changes them.
- Enclosure URLs are the **immutable** versioned DMGs (`/macos/v<v>/…`),
  never `/latest/`.

## Critical material: the Sparkle EdDSA private key ⚠️

Updates are only installed if their EdDSA signature matches the
`SUPublicEDKey` baked into every shipped app. **If the private key is lost,
every installed copy of Grabi will refuse all future updates** and users
would have to re-download by hand. Treat it like a production TLS key.

- **Primary copy**: the login Keychain of the release machine, item
  "Private key for signing Sparkle updates" (created by Sparkle's
  `generate_keys`; `sign_update` reads it from there — the key never
  touches the repo or the shell).
- **Backup**: an encrypted export (passphrase known only to the owner)
  stored outside this repo. To restore on a new machine:
  `generate_keys -f <decrypted-export>` re-imports it into the keychain.
  Verify with `generate_keys -p` — it must print
  `KGNbtBiMipSNEc4SUJP+z0Qh6Gi7cQShCkJ539OgCAU=` (the public key in
  `Support/Info.plist`).
- The `SPARKLE_ED_PRIVATE_KEY` GitHub Actions secret (for future CI
  signing) is **not** a backup — secrets cannot be read back.

## Apple notarization (pending)

When the Apple Developer account lands: switch `SIGN_IDENTITY` to the
Developer ID certificate, add `notarytool submit` + `stapler` after the DMG
step in `make-interim-release.sh`, consider removing
`com.apple.security.cs.disable-library-validation` from
`Support/Grabi.entitlements` (a real Team ID makes library validation
work), and then publish the Homebrew cask (`packaging/homebrew/`).
