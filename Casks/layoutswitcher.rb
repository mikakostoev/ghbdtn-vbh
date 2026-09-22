# Version and sha256 are bumped by .github/workflows/cask.yml on every published release.
cask "layoutswitcher" do
  version "1.1.0"
  sha256 "827b444da7fdd4fc26cc54d8cc15861db1f66de3f62aa86719f74f3d18099daa"

  url "https://github.com/mikakostoev/layout-switcher/releases/download/v#{version}/LayoutSwitcher-#{version}.zip"
  name "LayoutSwitcher"
  desc "Keyboard layout auto-switcher: ghbdtn → привет. No networking code at all"
  homepage "https://github.com/mikakostoev/layout-switcher"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "LayoutSwitcher.app"

  zap trash: [
    "~/Library/Application Support/LayoutSwitcher",
    "~/Library/Preferences/local.layoutswitcher.plist",
  ]
end
