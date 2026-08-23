# Homebrew cask for Grabi — PREPARED, NOT PUBLISHED YET.
#
# TODO(publish-after-notarization): without Apple notarization, `brew` users
# hit Gatekeeper friction ("cannot be opened…"), which reads as broken.
# Publish this cask only after releases are signed with Developer ID and
# notarized. Until then it lives here as ready-to-ship packaging.
#
# See packaging/homebrew/README.md for how and where to publish.
cask "grabi" do
  version "0.2.1"
  sha256 "d1032ed2fd490ac0c9482ab46894a1c92ecd5b24c38c5e795676ceba5f3ba533" # printed by scripts/publish-release.sh

  url "https://dl.grabi.net/macos/v#{version}/Grabi-#{version}.dmg"
  name "Grabi"
  desc "Native menu-bar screen recorder — record your screen, no drama"
  homepage "https://grabi.net"

  livecheck do
    url "https://dl.grabi.net/macos/latest.json"
    strategy :json do |json|
      json["version"]
    end
  end

  auto_updates true # Sparkle
  depends_on macos: ">= :ventura"

  app "Grabi.app"

  zap trash: [
    "~/Library/Caches/com.ivan.recordapp",
    "~/Library/HTTPStorages/com.ivan.recordapp",
    "~/Library/Preferences/com.ivan.recordapp.plist",
    "~/Library/Saved Application State/com.ivan.recordapp.savedState",
  ]
  # Recordings in ~/Movies/Grabi are the user's work — never zapped.
end
