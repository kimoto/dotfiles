# CleanShot X held at the last release the license covers: 5.x needs a paid
# renewal and refuses the 4.x key. Homebrew's own cask only ever carries the
# newest version, so this repo is tapped by Brewfile.macos to serve this one.
cask "cleanshot@4" do
  version "4.8.11"
  sha256 "298afb3d085ee6343dae954ba2a7429bd613e6ad9e942c8f79008688ceb11a81"

  url "https://updates.getcleanshot.com/v3/CleanShot-X-#{version}.dmg"
  name "CleanShot"
  desc "Screen capturing tool"
  homepage "https://cleanshot.com/"

  livecheck do
    skip "Pinned to the last version the license covers"
  end

  auto_updates true
  conflicts_with cask: "cleanshot"
  depends_on macos: :ventura

  app "CleanShot X.app"

  uninstall quit: "pl.maketheweb.cleanshotx"

  zap trash: [
    "~/Library/Application Scripts/pl.maketheweb.cleanshotx.*",
    "~/Library/Application Support/CleanShot",
    "~/Library/Caches/pl.maketheweb.cleanshotx",
    "~/Library/Caches/SentryCrash/CleanShot X",
    "~/Library/Containers/pl.maketheweb.cleanshotx.*",
    "~/Library/HTTPStorages/pl.maketheweb.cleanshotx",
    "~/Library/Preferences/com.getcleanshot.app.plist",
    "~/Library/Preferences/pl.maketheweb.cleanshotx.plist",
    "~/Library/WebKit/pl.maketheweb.cleanshotx",
  ]
end
