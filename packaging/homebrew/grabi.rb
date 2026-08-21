# Homebrew cask for Grabi — PREPARED, NOT PUBLISHED YET.
#
# TODO(publish-after-notarization): without Apple notarization, `brew` users
# hit Gatekeeper friction ("cannot be opened…"), which reads as broken.
# Publish this cask only after releases are signed with Developer ID and
# notarized. Until then it lives here as ready-to-ship packaging.
#
# See packaging/homebrew/README.md for how and where to publish.
cask "grabi" do
  version "0.1.4"
  sha256 "ce9829a141b71ac7d20517bea1ce8af702636751a9022904034a74162b878ff7" # printed by scripts/publish-release.sh

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
