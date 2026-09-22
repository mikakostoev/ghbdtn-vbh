# Version and sha256 are bumped by .github/workflows/cask.yml on every published release.
cask "ghbdtn-vbh" do
  version "1.1.0"
  sha256 "827b444da7fdd4fc26cc54d8cc15861db1f66de3f62aa86719f74f3d18099daa"

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
