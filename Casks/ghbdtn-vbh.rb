# Version and sha256 are bumped by .github/workflows/cask.yml on every published release.
cask "ghbdtn-vbh" do
  version "2.0.2"
  sha256 "602b39d26146ed88b403fee66b22897c2091805d7d5b2cb9ff6d933ca20968d1"

  url "https://github.com/mikakostoev/ghbdtn-vbh/releases/download/v#{version}/ghbdtn-vbh-#{version}.zip"
  name "ghbdtn vbh"
  desc "Keyboard layout auto-switcher: ghbdtn vbh → привет мир. No networking code at all"
  homepage "https://github.com/mikakostoev/ghbdtn-vbh"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "ghbdtn vbh.app"

  zap trash: [
    "~/Library/Application Support/ghbdtn vbh",
    "~/Library/Application Support/LayoutSwitcher",
    "~/Library/Preferences/app.ghbdtnvbh.plist",
    "~/Library/Preferences/local.layoutswitcher.plist",
  ]
end
