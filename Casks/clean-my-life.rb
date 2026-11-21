cask "clean-my-life" do
  version "0.1.0"
  # The release workflow replaces this with the published DMG's SHA-256.
  # :no_check lets the in-repo cask be tested before the first release exists.
  sha256 :no_check

  url "https://github.com/itchyparrot53/clean-my-life/releases/download/v#{version}/CleanMyLife-#{version}.dmg"
  name "Clean My Life"
  desc "Open-source Mac cleaner, optimizer, and malware scanner"
  homepage "https://itchyparrot53.github.io/clean-my-life/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Clean My Life.app"

  # Quit a running copy before upgrading or uninstalling so macOS can replace it.
  uninstall quit: "com.macclean.app"

  zap trash: [
    "~/Library/Application Support/MacClean",
    "~/Library/Caches/com.macclean.app",
    "~/Library/HTTPStorages/com.macclean.app",
    "~/Library/Logs/MacClean",
    "~/Library/Preferences/com.macclean.app.plist",
    "~/Library/Preferences/com.macclean.shared.plist",
    "~/Library/Saved Application State/com.macclean.app.savedState",
  ]

  caveats <<~EOS
    The 0.1.0 beta is ad-hoc signed, not notarized. If macOS blocks the first
    launch, run:
      xattr -dr com.apple.quarantine "/Applications/Clean My Life.app"
    or build from source: https://github.com/itchyparrot53/clean-my-life
  EOS
end
