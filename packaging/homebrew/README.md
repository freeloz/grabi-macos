# Homebrew packaging (prepared, not published)

`grabi.rb` is a ready-to-ship Homebrew cask. **Do not publish it yet**: the
interim "Grabi Dev" signature is not notarized, so `brew install --cask grabi`
would end in Gatekeeper friction for every user.

## When to publish

After the Apple Developer account lands and releases are signed with
Developer ID **and notarized** (see the TODO in `make-interim-release.sh`).

## How to publish

1. Update `version` and `sha256` in `grabi.rb` for the notarized release
   (`scripts/publish-release.sh` prints the SHA-256; it also lives next to
   each DMG at `dl.grabi.net/macos/v<version>/Grabi-<version>.dmg.sha256`).
2. **Recommended path — own tap first**: create the public repo
   `freeloz/homebrew-tap`, copy `grabi.rb` into `Casks/grabi.rb`, and users
   install with:

   ```bash
   brew tap freeloz/tap
   brew install --cask grabi
   ```

   A tap ships today, needs no approval, and you control release timing.
3. **Later — official homebrew-cask**: once there is real traction
   (the unofficial bar reviewers apply: a notable GitHub star count, stable
   release cadence, notarized builds), submit the cask to
   [homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask) with
   `brew audit --new --cask grabi` passing. Keep the tap as the early channel
   until then; delete it from the tap once the official cask is merged.

## Notes

- `auto_updates true` tells brew that Sparkle handles updates, so
  `brew upgrade` won't fight the in-app updater.
- `livecheck` reads `dl.grabi.net/macos/latest.json` (kept in sync by
  `scripts/publish-release.sh`).
- The `zap` stanza removes preferences/caches only — never `~/Movies/Grabi`
  (the user's recordings).
