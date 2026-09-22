# ghbdtn vbh Product Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Превратить LayoutSwitcher в продукт «ghbdtn vbh»: новое имя везде, окно первого запуска, сайт на GitHub Pages и пайплайн подписи, который включится, когда появится Developer ID.

**Architecture:** Четыре независимых PR поверх существующего однопакетного SwiftPM-приложения (меню-бар, event tap, SwiftUI-настройки). Переименование — механическая замена по таблице из спека плюс перенос папки Application Support. Онбординг — один новый SwiftUI-файл и окно из `main.swift`. Сайт — два статичных HTML в `docs/`, без сборки. Подпись — условные шаги в `release.yml`, проверяемые через `env`.

**Tech Stack:** Swift 5.9 / SwiftPM, AppKit + SwiftUI, sh, GitHub Actions (macos-latest), Homebrew cask, статичный HTML/CSS/JS без библиотек.

**Spec:** `docs/superpowers/specs/2026-09-23-ghbdtn-vbh-product-design.md`

## Global Constraints

- В приложении **нет сетевого кода**: `grep -rnE "URLSession|URLRequest|NWConnection|CFSocket|WebKit" Sources/` должен оставаться пустым. Открыть ссылку через `NSWorkspace.shared.open` — можно.
- Никаких новых зависимостей: `Package.swift` остаётся одним таргетом без пакетов.
- Единственный бинарник в репозитории — `demo.gif` (переезжает из `.github/` в `docs/`). Новых картинок не добавлять: иконка на сайте — inline SVG.
- Имя продукта пишется ровно так: `ghbdtn vbh` (строчные, один пробел). Идентификаторы без пробела: таргет/бинарник `ghbdtnvbh`, bundle ID `app.ghbdtnvbh`, cask/репо `ghbdtn-vbh`, архив `ghbdtn-vbh-<version>.zip`.
- macOS 13+, универсальная сборка (arm64 + x86_64) в релизе — как сейчас.
- `./test.sh` зелёный после каждой задачи. Baseline: 0 false switches на `Tests/chat-*.txt` и `Tests/common-*.txt`.
- Локальный сертификат разработчика `LayoutSwitcher Local Signing` **не переименовывается**: он живёт в keychain у людей, и смена имени сломала бы их сборки. Это единственное место, где старое имя остаётся.
- Коммиты — на английском, как вся история репо. Каждая задача заканчивается коммитом; каждый PR — `gh pr create`, ожидание зелёного `test.yml`, `gh pr merge --merge --delete-branch`.
- Ветка для PR N создаётся от свежего `main`: `git checkout main && git pull && git checkout -b <name>`.

---

## PR 1 — Переименование

### Task 1: Переименовать SwiftPM-таргет и папку исходников

**Files:**
- Modify: `Package.swift`
- Rename: `Sources/LayoutSwitcher/` → `Sources/ghbdtnvbh/`
- Modify: `test.sh:7`
- Modify: `.github/workflows/test.yml:17-26`

**Interfaces:**
- Produces: бинарник `.build/{debug,release}/ghbdtnvbh`; все дальнейшие задачи используют этот путь.

- [ ] **Step 1: Ветка**

```bash
git checkout main && git pull && git checkout -b rename
```

- [ ] **Step 2: Переименовать таргет**

```bash
git mv Sources/LayoutSwitcher Sources/ghbdtnvbh
cat > Package.swift <<'EOF'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ghbdtnvbh",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "ghbdtnvbh")]
)
EOF
sed -i '' 's#\.build/release/LayoutSwitcher#.build/release/ghbdtnvbh#' test.sh
sed -i '' 's#\.build/debug/LayoutSwitcher#.build/debug/ghbdtnvbh#; s#\.build/release/LayoutSwitcher#.build/release/ghbdtnvbh#g' .github/workflows/test.yml
```

- [ ] **Step 3: Проверить сборку и self-test**

Run: `swift build 2>&1 | tail -1 && .build/debug/ghbdtnvbh --selftest | tail -3`
Expected: `Build complete!`, self-test заканчивается без `Fatal error`/`precondition failed`.

- [ ] **Step 4: Полный тест**

Run: `./test.sh 2>&1 | grep -E "FALSE SWITCH|Build"`
Expected: все `FALSE SWITCH 0` для `chat-*` и `common-*`; ненулевые допустимы только у `stress-*`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Rename the SwiftPM target to ghbdtnvbh

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 2: Бандл, Info.plist, скрипты сборки и живого теста

**Files:**
- Modify: `build.sh`
- Modify: `release.sh`
- Modify: `.gitignore:2`
- Modify: `Tests/live.sh:8-10`
- Modify: `Tests/pad.swift:4,17`

**Interfaces:**
- Produces: `./build.sh` → `./ghbdtn vbh.app`; `./release.sh X` → `dist/ghbdtn-vbh-X.zip`. Окружение `OUT`, `UNIVERSAL`, `IDENTITY`, `VERSION` — как раньше.

- [ ] **Step 1: build.sh**

Заменить целиком:

```sh
#!/bin/sh
# Builds "ghbdtn vbh.app" next to this script, for this Mac and signed with the local identity.
# release.sh overrides: OUT (where to put the app), UNIVERSAL=1 (Apple silicon + Intel), IDENTITY, VERSION.
set -e
cd "$(dirname "$0")"
# Xcode license not accepted -> fall back to Command Line Tools
xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1 || export DEVELOPER_DIR=/Library/Developer/CommandLineTools
BUNDLE="${OUT:-.}/ghbdtn vbh.app"
APP="$BUNDLE/Contents"
rm -rf "$BUNDLE" && mkdir -p "$APP/MacOS"
if [ -n "$UNIVERSAL" ]; then
    # Both architectures land in the same products folder, so each is copied out before the next build.
    for arch in arm64 x86_64; do
        swift build -c release --triple "$arch-apple-macosx"
        cp "$(swift build -c release --triple "$arch-apple-macosx" --show-bin-path)/ghbdtnvbh" "$APP/MacOS/$arch"
    done
    lipo -create "$APP/MacOS/arm64" "$APP/MacOS/x86_64" -output "$APP/MacOS/ghbdtnvbh"
    rm "$APP/MacOS/arm64" "$APP/MacOS/x86_64"
else
    swift build -c release
    cp "$(swift build -c release --show-bin-path)/ghbdtnvbh" "$APP/MacOS/"
fi
# App icon: drawn by Tools/icon.swift so the repository keeps no binary, and redrawn when that file changes.
ICON=.build/icon
if [ ! -f "$ICON.icns" ] || [ Tools/icon.swift -nt "$ICON.icns" ]; then
    mkdir -p .build
    swiftc -O -sdk "$(xcrun --sdk macosx --show-sdk-path)" Tools/icon.swift -o "$ICON-tool"
    "$ICON-tool" "$ICON.iconset" >/dev/null
    iconutil -c icns "$ICON.iconset" -o "$ICON.icns"
fi
mkdir -p "$APP/Resources"
cp "$ICON.icns" "$APP/Resources/ghbdtnvbh.icns"
cp -R Resources/*.lproj "$APP/Resources/"
cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.ghbdtnvbh</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleName</key><string>ghbdtn vbh</string>
<key>CFBundleDisplayName</key><string>ghbdtn vbh</string>
<key>CFBundleExecutable</key><string>ghbdtnvbh</string>
<key>CFBundleIconFile</key><string>ghbdtnvbh</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${VERSION:-1.0}</string>
<key>CFBundleVersion</key><string>${VERSION:-1.0}</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
# A stable identity keeps the Accessibility grant across rebuilds; ad-hoc (-) changes the code hash every
# build, so macOS forgets the app. Create the identity once in Keychain Access > Certificate Assistant >
# Create a Certificate (self-signed root, type Code Signing), named as below. The name predates the rename
# and stays: it lives in developers' keychains.
IDENTITY="${IDENTITY:-LayoutSwitcher Local Signing}"
[ "$IDENTITY" = - ] || security find-identity -p codesigning | grep -q "\"$IDENTITY\"" || { echo "No '$IDENTITY' certificate, signing ad-hoc"; IDENTITY=-; }
codesign --force -s "$IDENTITY" "$BUNDLE"
echo "Built $BUNDLE"
```

- [ ] **Step 2: release.sh, .gitignore, live.sh, pad.swift**

```bash
cat > release.sh <<'EOF'
#!/bin/sh
# ./release.sh 2.0.0 — universal ad-hoc-signed build zipped into dist/, ready to attach to a GitHub release.
# Ad-hoc because a self-signed local identity means nothing on another Mac, and there is no Apple Developer ID:
# Gatekeeper will ask for right click > Open on first launch either way.
set -e
cd "$(dirname "$0")"
VERSION="${1:?usage: ./release.sh <version>}"
OUT=dist UNIVERSAL=1 IDENTITY=- VERSION="$VERSION" ./build.sh
"dist/ghbdtn vbh.app/Contents/MacOS/ghbdtnvbh" --selftest
ditto -c -k --keepParent "dist/ghbdtn vbh.app" "dist/ghbdtn-vbh-$VERSION.zip"
echo "dist/ghbdtn-vbh-$VERSION.zip"
EOF
sed -i '' 's#^LayoutSwitcher\.app/$#ghbdtn vbh.app/#' .gitignore
sed -i '' 's#layoutswitcher-pad#ghbdtnvbh-pad#; s#pgrep -f "LayoutSwitcher.app/Contents/MacOS/LayoutSwitcher"#pgrep -f "ghbdtn vbh.app/Contents/MacOS/ghbdtnvbh"#; s#echo "LayoutSwitcher is not running"#echo "ghbdtn vbh is not running"#' Tests/live.sh
sed -i '' 's#the running LayoutSwitcher sees#the running ghbdtn vbh sees#; s#window.title = "LayoutSwitcher test pad"#window.title = "ghbdtn vbh test pad"#' Tests/pad.swift
rm -rf LayoutSwitcher.app
```

- [ ] **Step 3: Собрать и проверить бандл**

Run:
```bash
./build.sh && defaults read "$PWD/ghbdtn vbh.app/Contents/Info.plist" CFBundleIdentifier && codesign -dv "ghbdtn vbh.app" 2>&1 | grep Identifier && ls "ghbdtn vbh.app/Contents/Resources/"
```
Expected: `app.ghbdtnvbh`, `Identifier=app.ghbdtnvbh`, в Resources лежат `ghbdtnvbh.icns`, `en.lproj`, `ru.lproj`.

- [ ] **Step 4: Проверить release.sh**

Run: `./release.sh 0.0.0 && ls dist/ && rm -rf dist`
Expected: `ghbdtn vbh.app` и `ghbdtn-vbh-0.0.0.zip` в `dist/`, self-test прошёл.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Build the bundle as \"ghbdtn vbh.app\" with bundle ID app.ghbdtnvbh

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 3: Имя в коде и строках, перенос Application Support

**Files:**
- Modify: `Sources/ghbdtnvbh/main.swift:37,80-81,87`
- Modify: `Sources/ghbdtnvbh/Settings.swift:5-12`
- Modify: `Resources/en.lproj/Localizable.strings:8-9`
- Modify: `Resources/ru.lproj/Localizable.strings:7-8`

**Interfaces:**
- Produces: `appFile(_:)` создаёт `~/Library/Application Support/ghbdtn vbh/` и один раз переносит туда старую папку `LayoutSwitcher`. Ключи строк `"ghbdtn vbh: no Accessibility access"`, `"ghbdtn vbh: auto-switching is off"`.

- [ ] **Step 1: main.swift**

```bash
sed -i '' 's#accessibilityDescription: "LayoutSwitcher"#accessibilityDescription: "ghbdtn vbh"#; s#NSLocalizedString("LayoutSwitcher: no Accessibility access"#NSLocalizedString("ghbdtn vbh: no Accessibility access"#; s#: enabled ? "LayoutSwitcher" : NSLocalizedString("LayoutSwitcher: auto-switching is off"#: enabled ? "ghbdtn vbh" : NSLocalizedString("ghbdtn vbh: auto-switching is off"#; s#window.title = "LayoutSwitcher"#window.title = "ghbdtn vbh"#' Sources/ghbdtnvbh/main.swift
grep -n "LayoutSwitcher" Sources/ghbdtnvbh/main.swift
```
Expected: grep пуст.

- [ ] **Step 2: Settings.swift — папка и перенос**

Заменить функцию `appFile` (строки 5–12) на:

```swift
private func appFile(_ name: String) -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = support.appendingPathComponent("ghbdtn vbh"), old = support.appendingPathComponent("LayoutSwitcher")
    // The app was called LayoutSwitcher up to 1.1: the three files move over once, the first time 2.0 runs.
    if !FileManager.default.fileExists(atPath: dir.path), FileManager.default.fileExists(atPath: old.path) {
        try? FileManager.default.moveItem(at: old, to: dir)
    }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent(name)
    if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
    return file
}
```

- [ ] **Step 3: Строки**

```bash
sed -i '' 's#"LayoutSwitcher: no Accessibility access" = "LayoutSwitcher: no Accessibility access"#"ghbdtn vbh: no Accessibility access" = "ghbdtn vbh: no Accessibility access"#; s#"LayoutSwitcher: auto-switching is off" = "LayoutSwitcher: auto-switching is off"#"ghbdtn vbh: auto-switching is off" = "ghbdtn vbh: auto-switching is off"#' Resources/en.lproj/Localizable.strings
sed -i '' 's#"LayoutSwitcher: no Accessibility access" = "LayoutSwitcher: нет доступа#"ghbdtn vbh: no Accessibility access" = "ghbdtn vbh: нет доступа#; s#"LayoutSwitcher: auto-switching is off" = "LayoutSwitcher: автопереключение#"ghbdtn vbh: auto-switching is off" = "ghbdtn vbh: автопереключение#' Resources/ru.lproj/Localizable.strings
grep -c "ghbdtn vbh" Resources/*/Localizable.strings
```
Expected: по 2 совпадения в каждом файле (в ключе и в значении по два вхождения на строку → grep -c считает строки: 2).

- [ ] **Step 4: Проверить перенос папки живьём**

```bash
./build.sh
AS="$HOME/Library/Application Support"
pkill -x ghbdtnvbh; pkill -x LayoutSwitcher; true
[ -d "$AS/ghbdtn vbh" ] && mv "$AS/ghbdtn vbh" "$AS/ghbdtn vbh.bak"
[ -d "$AS/LayoutSwitcher" ] || { mkdir "$AS/LayoutSwitcher"; echo probe > "$AS/LayoutSwitcher/words.txt"; }
open "ghbdtn vbh.app"; sleep 3
ls "$AS/ghbdtn vbh/" && [ ! -d "$AS/LayoutSwitcher" ] && echo MOVED
pkill -x ghbdtnvbh
```
Expected: `exceptions.txt sites.txt words.txt` и `MOVED`. Если до теста была настоящая папка `ghbdtn vbh.bak` — вернуть: `rm -rf "$AS/ghbdtn vbh" && mv "$AS/ghbdtn vbh.bak" "$AS/ghbdtn vbh"`. Если настоящей была `LayoutSwitcher` с твоими словами — она теперь и есть `ghbdtn vbh`, всё правильно.

- [ ] **Step 5: test.sh и commit**

Run: `./test.sh 2>&1 | grep -c "FALSE SWITCH 0"` — Expected: не меньше 10.

```bash
git add -A && git commit -m "Call the app ghbdtn vbh in the menu bar and move Application Support over

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 4: Cask, workflows, README, CONTRIBUTING, NOTICE, LICENSE

**Files:**
- Rename: `Casks/layoutswitcher.rb` → `Casks/ghbdtn-vbh.rb`
- Modify: `.github/workflows/cask.yml:1,29,31`
- Modify: `.github/workflows/release.yml:20-21`
- Modify: `README.md`, `CONTRIBUTING.md`, `NOTICE.md`, `LICENSE:3`

- [ ] **Step 1: Cask**

```bash
git mv Casks/layoutswitcher.rb Casks/ghbdtn-vbh.rb
cat > Casks/ghbdtn-vbh.rb <<'EOF'
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
EOF
ruby -c Casks/ghbdtn-vbh.rb
```
Expected: `Syntax OK`. Версия и sha пока от 1.1.0 — URL этого архива не существует; cask начнёт работать после тега v2.0.0 (Task 14), когда `cask.yml` перепишет обе строки. До этого в README установка через brew помечена как «после 2.0.0» — см. Step 3.

- [ ] **Step 2: Workflows**

```bash
sed -i '' 's#Casks/layoutswitcher.rb#Casks/ghbdtn-vbh.rb#g; s#LayoutSwitcher-\$V.zip#ghbdtn-vbh-$V.zip#' .github/workflows/cask.yml
perl -pi -e 's/dist\/LayoutSwitcher-\*\.zip/dist\/ghbdtn-vbh-*.zip/g; s/--title "LayoutSwitcher /--title "ghbdtn vbh /' .github/workflows/release.yml
grep -n "LayoutSwitcher\|layoutswitcher" .github/workflows/*.yml
```
Expected: grep пуст.

- [ ] **Step 3: README**

Механические замены, потом руками заголовок:

```bash
perl -pi -e 's#https://github.com/mikakostoev/layout-switcher#https://github.com/mikakostoev/ghbdtn-vbh#g; s#brew tap mikakostoev/layout-switcher#brew tap mikakostoev/ghbdtn-vbh#; s#--no-quarantine layoutswitcher#--no-quarantine ghbdtn-vbh#; s#cd layout-switcher#cd ghbdtn-vbh#; s#`LayoutSwitcher\.app`#`ghbdtn vbh.app`#g; s#open LayoutSwitcher\.app#open "ghbdtn vbh.app"#; s#Application Support/LayoutSwitcher/#Application Support/ghbdtn vbh/#' README.md CONTRIBUTING.md
```

Первые строки README (заголовок, строку с одним бейджем `test` и абзац «You type `ghbdtn`, you get «привет». Free, open source…») заменить на:

```markdown
# ghbdtn vbh → привет мир

[![test](https://github.com/mikakostoev/ghbdtn-vbh/actions/workflows/test.yml/badge.svg)](https://github.com/mikakostoev/ghbdtn-vbh/actions/workflows/test.yml)
[![release](https://img.shields.io/github/v/release/mikakostoev/ghbdtn-vbh?label=release)](https://github.com/mikakostoev/ghbdtn-vbh/releases/latest)
[![downloads](https://img.shields.io/github/downloads/mikakostoev/ghbdtn-vbh/total?label=downloads)](https://github.com/mikakostoev/ghbdtn-vbh/releases)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)](#installation-in-detail)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](Package.swift)
[![license MIT](https://img.shields.io/github/license/mikakostoev/ghbdtn-vbh?label=license)](LICENSE)

Keyboard layout auto-switcher for macOS. You type `ghbdtn vbh`, you get «привет мир». Free, open source, and
nothing phones home: the app contains no networking code at all.
```

Бейджи — картинки с shields.io в README на GitHub, приложение их не трогает; обещание «нет сети в приложении» это не задевает. Бейджи `release` и `downloads` покажут данные после переименования репо (Task 5); до этого shields.io отдаёт «not found» — это ожидаемо.

В разделе Quick start пункт 1 дополнить предложением после команды brew: `The cask points at the first release under the new name, 2.0.0.` В разделе «Building from source» строка про `LayoutSwitcher Local Signing` остаётся как есть.

```bash
grep -n "LayoutSwitcher\|layout-switcher\|layoutswitcher" README.md CONTRIBUTING.md
```
Expected: единственная строка — про `LayoutSwitcher Local Signing`.

- [ ] **Step 4: NOTICE, LICENSE**

```bash
sed -i '' 's#Sources/LayoutSwitcher/Trigrams.swift#Sources/ghbdtnvbh/Trigrams.swift#' NOTICE.md
sed -i '' 's#Copyright (c) 2026 LayoutSwitcher authors#Copyright (c) 2026 ghbdtn vbh authors#' LICENSE
```

- [ ] **Step 5: Итоговый grep по репо**

```bash
grep -rn "LayoutSwitcher\|layoutswitcher\|layout-switcher" -I . | grep -v "^./.git/\|^./.build/\|_50k.txt\|^./dist\|superpowers\|Local Signing\|layoutswitcher-selftest\|Settings.swift.*LayoutSwitcher\|Casks/ghbdtn-vbh.rb\|CONTRIBUTING.md.*Local Signing"
```
Expected: пусто. Разрешённые остатки: имя локального сертификата (build.sh, README), временный файл self-test в `Layouts.swift:264` (внутреннее имя, никто не видит), строка миграции в `Settings.swift`, старые пути в `zap` cask-а.

- [ ] **Step 6: Commit, PR, merge**

```bash
./test.sh 2>&1 | grep -c "FALSE SWITCH 0"
git add -A && git commit -m "Rename the cask, the docs and the workflows to ghbdtn vbh

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -u origin rename
gh pr create --title "Rename LayoutSwitcher to ghbdtn vbh" --body "$(cat <<'EOF'
The app, bundle ID, target, cask, archive and docs take the product name from the spec in docs/superpowers/specs/2026-09-23-ghbdtn-vbh-product-design.md. Application Support moves over on first launch; UserDefaults and the Accessibility grant reset with the bundle ID (two releases, nobody to migrate).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
gh pr checks --watch
gh pr merge --merge --delete-branch
```
Expected: `test.yml` зелёный, PR влит.

### Task 5: Переименовать репозиторий на GitHub

**Files:** нет (GitHub и локальный `origin`).

- [ ] **Step 1: Переименовать и обновить описание**

```bash
gh repo rename ghbdtn-vbh --yes
gh repo edit --description "Keyboard layout auto-switcher for macOS: ghbdtn vbh → привет мир. Free, open source, zero telemetry: no networking code at all."
git remote set-url origin https://github.com/mikakostoev/ghbdtn-vbh.git
git checkout main && git pull
```

- [ ] **Step 2: Проверить**

Run: `gh repo view --json name,url -q '.url' && curl -sI https://github.com/mikakostoev/layout-switcher | head -1`
Expected: `https://github.com/mikakostoev/ghbdtn-vbh` и `HTTP/2 301` со старого адреса.

---

## PR 2 — Окно первого запуска и меню

### Task 6: Onboarding.swift и показ окна

**Files:**
- Create: `Sources/ghbdtnvbh/Onboarding.swift`
- Modify: `Sources/ghbdtnvbh/main.swift` (свойства ~18, `applicationDidFinishLaunching` ~35-53, `menuNeedsUpdate` ~63, `startTap` ~104-114, новый метод рядом с `openSettings`)
- Modify: `Resources/en.lproj/Localizable.strings`, `Resources/ru.lproj/Localizable.strings`

**Interfaces:**
- Produces: `struct OnboardingView: View { init(afterUpdate: Bool, openAccessibility: @escaping () -> Void, close: @escaping () -> Void) }`; в `Switcher` — `@objc func openOnboarding()`; ключ UserDefaults `"onboarded"` (Bool), ставится в `startTap()` при успехе.

- [ ] **Step 1: Ветка**

```bash
git checkout main && git pull && git checkout -b onboarding
```

- [ ] **Step 2: Создать Onboarding.swift**

```swift
import AppKit
import SwiftUI

/// Shown while there is no Accessibility grant: at launch, and from the menu item. `afterUpdate` picks the text
/// for a Mac that had the grant before — the build's signature changed with the update and macOS forgot it.
/// Polls the grant itself while open; the tap is raised by Switcher's own timer, independently.
struct OnboardingView: View {
    let afterUpdate: Bool
    let openAccessibility: () -> Void
    let close: () -> Void
    @State private var granted = AXIsProcessTrusted()
    @State private var sample = ""
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("ghbdtn vbh").font(.title.bold())
            Text(NSLocalizedString(afterUpdate
                ? "The update changed the app's signature and macOS forgot the permission. Untick ghbdtn vbh in the list and tick it again."
                : "To fix the layout, the app has to see what you type. Allow it under Accessibility.", comment: ""))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if granted {
                Label("Access granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Try it: type ghbdtn vbh and press space").foregroundStyle(.secondary)
                TextField("", text: $sample).textFieldStyle(.roundedBorder).frame(width: 260)
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            } else {
                Button("Open Accessibility settings", action: openAccessibility).keyboardShortcut(.defaultAction)
                Label("Waiting for permission…", systemImage: "hourglass").foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 420)
        .onReceive(tick) { _ in granted = AXIsProcessTrusted() }
    }
}
```

- [ ] **Step 3: main.swift — окно, флаг, пункт меню**

Рядом с `private var settingsWindow: NSWindow?` добавить:

```swift
    private var onboardingWindow: NSWindow?
```

В `applicationDidFinishLaunching` заменить блок таймера на:

```swift
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            if self?.startTap() == true { timer.invalidate(); self?.showState() }
        }.fire()
        if tap == nil { openOnboarding() }
```

В `menuNeedsUpdate` строку `if tap == nil { add("No access: Accessibility…", #selector(openAccessibility)) }` заменить на:

```swift
        if tap == nil { add("No access: Accessibility…", #selector(openOnboarding)) }
```

В `startTap()` перед `self.tap = tap` добавить:

```swift
        defaults.set(true, forKey: "onboarded")  // the "after an update" text is for Macs that got this far once
```

После `openSettings()` добавить:

```swift
    @objc private func openOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(afterUpdate: defaults.bool(forKey: "onboarded"),
                                      openAccessibility: { [weak self] in self?.openAccessibility() },
                                      close: { [weak self] in self?.onboardingWindow?.close() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "ghbdtn vbh"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            onboardingWindow = window
        }
        onboardingWindow?.center()
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
```

- [ ] **Step 4: Строки**

Добавить в конец `Resources/en.lproj/Localizable.strings`:

```
"To fix the layout, the app has to see what you type. Allow it under Accessibility." = "To fix the layout, the app has to see what you type. Allow it under Accessibility.";
"The update changed the app's signature and macOS forgot the permission. Untick ghbdtn vbh in the list and tick it again." = "The update changed the app's signature and macOS forgot the permission. Untick ghbdtn vbh in the list and tick it again.";
"Open Accessibility settings" = "Open Accessibility settings";
"Waiting for permission…" = "Waiting for permission…";
"Access granted" = "Access granted";
"Try it: type ghbdtn vbh and press space" = "Try it: type ghbdtn vbh and press space";
"Done" = "Done";
```

В конец `Resources/ru.lproj/Localizable.strings`:

```
"To fix the layout, the app has to see what you type. Allow it under Accessibility." = "Чтобы исправлять раскладку, приложению нужно видеть, что вы печатаете. Разрешите это в Универсальном доступе.";
"The update changed the app's signature and macOS forgot the permission. Untick ghbdtn vbh in the list and tick it again." = "Обновление сменило подпись приложения, и macOS забыла разрешение. Снимите галочку у ghbdtn vbh в списке и поставьте снова.";
"Open Accessibility settings" = "Открыть Универсальный доступ";
"Waiting for permission…" = "Ждём разрешения…";
"Access granted" = "Доступ есть";
"Try it: type ghbdtn vbh and press space" = "Попробуйте: наберите ghbdtn vbh и нажмите пробел";
"Done" = "Готово";
```

- [ ] **Step 5: Сборка и проверка, что сети нет**

Run: `swift build 2>&1 | tail -1 && grep -rnE "URLSession|URLRequest|NWConnection|CFSocket|WebKit" Sources/ ; echo "net grep exit $?"`
Expected: `Build complete!`, `net grep exit 1` (ничего не найдено).

- [ ] **Step 6: Живой тест — первый запуск**

```bash
./build.sh
pkill -x ghbdtnvbh; true
defaults delete app.ghbdtnvbh onboarded 2>/dev/null; true
tccutil reset Accessibility app.ghbdtnvbh
open "ghbdtn vbh.app"
```
Проверить глазами: окно с иконкой, текст «To fix the layout…» (или русский при русской системе), кнопка открывает панель Универсального доступа. Поставить галочку приложению. В течение секунды строка меняется на «Access granted», появляется поле. Набрать в поле `ghbdtn vbh` и пробел — в поле должно стать «привет мир». Нажать Done.

- [ ] **Step 7: Живой тест — «после обновления»**

```bash
pkill -x ghbdtnvbh; true
tccutil reset Accessibility app.ghbdtnvbh
defaults write app.ghbdtnvbh onboarded -bool true
open "ghbdtn vbh.app"
```
Expected: окно с текстом «The update changed the app's signature…». Выдать доступ, убедиться, что галочка появилась. Пункт меню «No access: Accessibility…» при отсутствии доступа открывает это же окно.

- [ ] **Step 8: Commit**

```bash
./test.sh 2>&1 | grep -c "FALSE SWITCH 0"
git add -A && git commit -m "Walk the user through the Accessibility grant on first launch

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 7: Пункты меню «About» и «Check for updates…»

**Files:**
- Modify: `Sources/ghbdtnvbh/main.swift` (`menuNeedsUpdate`, новые методы)
- Modify: `Resources/en.lproj/Localizable.strings`, `Resources/ru.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `CFBundleVersion` из `build.sh` (добавлен в Task 2).

- [ ] **Step 1: Меню**

В `menuNeedsUpdate` заменить хвост после `menu.addItem(.separator())`:

```swift
        menu.addItem(.separator())
        add("Settings…", #selector(openSettings))
        add("Check for updates…", #selector(openReleases))
        add("About ghbdtn vbh", #selector(showAbout))
        add("Quit", #selector(NSApplication.terminate))
        menu.items.last?.target = NSApp
```

После `openAccessibility()` добавить:

```swift
    /// A link in the browser, not a network call: the app itself never goes online (see README).
    @objc private func openReleases() {
        NSWorkspace.shared.open(URL(string: "https://github.com/mikakostoev/ghbdtn-vbh/releases")!)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
```

- [ ] **Step 2: Строки**

en:
```
"Check for updates…" = "Check for updates…";
"About ghbdtn vbh" = "About ghbdtn vbh";
```
ru:
```
"Check for updates…" = "Проверить обновления…";
"About ghbdtn vbh" = "О программе ghbdtn vbh";
```

- [ ] **Step 3: Проверить**

```bash
VERSION=2.0.0-test ./build.sh && pkill -x ghbdtnvbh; open "ghbdtn vbh.app"
grep -rnE "URLSession|URLRequest|NWConnection|CFSocket|WebKit" Sources/; echo "net grep exit $?"
```
Глазами: в меню в строке меню есть оба пункта; «About ghbdtn vbh» показывает панель с иконкой и `Version 2.0.0-test (2.0.0-test)`; «Check for updates…» открывает страницу Releases в браузере. `net grep exit 1`.

Потом `Tests/live.sh` при запущенном приложении: ожидаемые строки из комментария в скрипте (ну ты привет, press the привет, …) совпадают — `main.swift` тронут, живой ввод обязан работать как раньше.

- [ ] **Step 4: Commit, PR, merge**

```bash
./test.sh 2>&1 | grep -c "FALSE SWITCH 0"
git add -A && git commit -m "Add About and Check for updates to the menu

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -u origin onboarding
gh pr create --title "First-launch window and About / Check for updates menu items" --body "$(cat <<'EOF'
Without an Accessibility grant the app now opens a window that leads through the grant, shows a live check mark and a field to try the switch in. A Mac that had the grant before gets the "after an update" wording instead. Check for updates opens the Releases page in the browser; the app still has no networking code.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
gh pr checks --watch
gh pr merge --merge --delete-branch
```

---

## PR 3 — Сайт

### Task 8: Переезд demo.gif и .nojekyll

**Files:**
- Rename: `.github/demo.gif` → `docs/demo.gif`
- Create: `docs/.nojekyll`
- Modify: `README.md` (строка с `![Typed ghbdtn…](.github/demo.gif)`), `Tools/demo.sh:2,10,12`, `CONTRIBUTING.md` (строка про `.github/demo.gif`)

- [ ] **Step 1: Ветка и перенос**

```bash
git checkout main && git pull && git checkout -b site
git mv .github/demo.gif docs/demo.gif
touch docs/.nojekyll
sed -i '' 's#\.github/demo\.gif#docs/demo.gif#g' README.md Tools/demo.sh CONTRIBUTING.md
grep -rn "\.github/demo" . --include='*.md' --include='*.sh'; echo "exit $?"
```
Expected: `exit 1`.

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "Move demo.gif to docs/ so the site can show it

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 9: docs/index.html (English)

**Files:**
- Create: `docs/index.html`

**Interfaces:**
- Produces: страница ссылается на `demo.gif` рядом и на `ru/` для русской версии.

- [ ] **Step 1: Написать страницу**

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ghbdtn vbh — keyboard layout auto-switcher for macOS</title>
<meta name="description" content="You type ghbdtn vbh, you get привет мир. Free, open source, no networking code at all.">
<style>
:root { --bg: #f5f5f7; --ink: #1b1d21; --muted: #5c6068; --accent: #2869e5; --card: #ffffff; --line: #d9dbe0; }
@media (prefers-color-scheme: dark) { :root { --bg: #1b1d21; --ink: #f5f5f7; --muted: #a0a4ad; --card: #25282e; --line: #3a3e46; } }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink); font: 17px/1.55 -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif; }
main { max-width: 720px; margin: 0 auto; padding: 48px 20px 80px; }
header { text-align: center; padding-bottom: 32px; }
.logo { width: 96px; height: 96px; display: block; margin: 0 auto 16px; }
h1 { font-size: 40px; margin: 0; letter-spacing: -0.02em; }
.type { font: 700 32px/1.2 ui-monospace, "SF Mono", Menlo, monospace; color: var(--accent); min-height: 1.2em; margin: 8px 0 12px; }
.type::after { content: "▍"; animation: blink 1s steps(1) infinite; color: var(--muted); }
.type.fixed { color: var(--ink); }
@keyframes blink { 50% { opacity: 0; } }
.lead { color: var(--muted); margin: 0; }
.lang { position: absolute; top: 16px; right: 20px; font-size: 15px; }
a { color: var(--accent); }
img { max-width: 100%; border-radius: 10px; border: 1px solid var(--line); display: block; margin: 0 auto; }
h2 { font-size: 24px; margin: 48px 0 12px; }
pre { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: 12px 14px; overflow-x: auto; font: 14px/1.5 ui-monospace, "SF Mono", Menlo, monospace; }
ul { padding-left: 22px; } li { margin: 6px 0; }
.note { color: var(--muted); font-size: 15px; }
footer { margin-top: 64px; color: var(--muted); font-size: 15px; text-align: center; }
</style>
</head>
<body>
<a class="lang" href="ru/">Русский</a>
<main>
<header>
  <svg class="logo" viewBox="0 0 100 100" role="img" aria-label="ghbdtn vbh icon">
    <defs><clipPath id="key"><rect x="0" y="0" width="100" height="100" rx="22.4"/></clipPath></defs>
    <rect width="100" height="100" rx="22.4" fill="#f5f5f7"/>
    <polygon points="0,100 100,100 100,0" fill="#2869e5" clip-path="url(#key)"/>
    <text x="31" y="32" font-size="42" font-weight="700" fill="#1b1d21" text-anchor="middle" dominant-baseline="central" font-family="-apple-system, Helvetica, Arial, sans-serif">A</text>
    <text x="69" y="68" font-size="42" font-weight="700" fill="#ffffff" text-anchor="middle" dominant-baseline="central" font-family="-apple-system, Helvetica, Arial, sans-serif">Я</text>
    <rect width="100" height="100" rx="22.4" fill="none" stroke="rgba(0,0,0,.12)" stroke-width="1"/>
  </svg>
  <h1>ghbdtn vbh</h1>
  <p class="type" id="type">привет мир</p>
  <p class="lead">Keyboard layout auto-switcher for macOS. Free, open source, and nothing phones home.</p>
</header>

<img src="demo.gif" alt="Typed ghbdtn rfr ltkf hello — the screen shows привет как дела hello" width="800">

<h2>Install</h2>
<pre>brew tap mikakostoev/ghbdtn-vbh https://github.com/mikakostoev/ghbdtn-vbh &amp;&amp; brew install --cask --no-quarantine ghbdtn-vbh</pre>
<p>Or <a href="https://github.com/mikakostoev/ghbdtn-vbh/releases/latest">download the zip</a> and drag <code>ghbdtn vbh.app</code> into Applications. macOS 13 or newer, Apple silicon and Intel.</p>
<p class="note">On first launch macOS blocks the app: click “Open Anyway” in System Settings → Privacy &amp; Security, then allow it under Accessibility. The app opens a window that walks you through it. There is no paid Apple certificate behind the build, so the same permission is asked again after an update.</p>

<h2>What it does</h2>
<ul>
  <li>Fixes the word on the spot: <code>ghbdtn</code> → «привет», <code>руддщ</code> → «hello». Any layout macOS knows, not only Russian and English.</li>
  <li>Knows slang and names the system dictionary doesn't, from letter statistics: <code>ltdjgcjd</code> → «девопсов».</li>
  <li>Copes with Caps Lock, abbreviations, identifiers like <code>getUserName</code>, numbers and stretched words.</li>
  <li>Double Option converts the last word or your selection by hand.</li>
  <li>Exceptions per word, per app and per site.</li>
</ul>

<h2>Why it can be trusted with your keyboard</h2>
<ul>
  <li><strong>No network, none.</strong> No updates, statistics, licence checks or crash reports. One <code>grep</code> over the source finds no networking library.</li>
  <li><strong>The code is short and open.</strong> About a thousand lines of Swift, readable in an evening.</li>
  <li><strong>Nothing you type is kept.</strong> Memory holds the word you are typing and at most three short words before it. Never written to disk.</li>
  <li><strong>Passwords are off limits.</strong> In a secure field the app does not look at the keys at all.</li>
  <li><strong>Three plain text files</strong> in Application Support: your exceptions, learned words and excluded sites. All visible in Settings.</li>
</ul>

<h2>Languages</h2>
<p>Works like Russian and English do: Ukrainian, German, French, Spanish, Italian, Portuguese, Dutch, Danish, Norwegian, Swedish, Finnish, Icelandic, Czech, Polish, Slovak, Hungarian, Romanian, Bulgarian, Greek, Turkish, Lithuanian, Hebrew, Arabic.</p>
<p class="note">Weaker without a system dictionary (Croatian, Estonian, Macedonian, Albanian, Serbian, Farsi, Georgian) and for layouts that share letters with English. Doesn't work for input methods (Chinese, Japanese, Korean), scripts without spaces, and dead-key layouts. The honest list is in the <a href="https://github.com/mikakostoev/ghbdtn-vbh#languages">README</a>.</p>

<footer>
  <a href="https://github.com/mikakostoev/ghbdtn-vbh">GitHub</a> ·
  <a href="https://github.com/mikakostoev/ghbdtn-vbh/releases">Releases</a> ·
  <a href="https://github.com/mikakostoev/ghbdtn-vbh/blob/main/LICENSE">MIT</a> ·
  <a href="https://github.com/mikakostoev/ghbdtn-vbh/blob/main/NOTICE.md">Notice</a>
</footer>
</main>
<script>
(function () {
  var el = document.getElementById('type'), typed = 'ghbdtn vbh', fixed = 'привет мир', i = 0;
  function step() {
    if (i <= typed.length) { el.textContent = typed.slice(0, i++); setTimeout(step, 110); return; }
    setTimeout(function () {
      el.textContent = fixed; el.classList.add('fixed');
      setTimeout(function () { i = 0; el.classList.remove('fixed'); step(); }, 2600);
    }, 400);
  }
  step();
})();
</script>
</body>
</html>
```

- [ ] **Step 2: Проверить, что страница ни к чему внешнему не обращается**

Run: `grep -nE '<script[^>]+src|<link|@import|url\(' docs/index.html; echo "exit $?"`
Expected: `exit 1`.

- [ ] **Step 3: Посмотреть в браузере**

Открыть `file://$PWD/docs/index.html` (через preview_start в браузерной панели или `open docs/index.html`). Проверить: печатается `ghbdtn vbh`, превращается в «привет мир» и повторяется; gif виден; в узком окне (400 px) нет горизонтальной прокрутки; в тёмной теме читается. Отключить JS (или закомментировать `<script>`) — строка «привет мир» стоит статично.

- [ ] **Step 4: Commit**

```bash
git add docs/index.html && git commit -m "Add the site: one static page, no build step

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 10: docs/ru/index.html

**Files:**
- Create: `docs/ru/index.html`

- [ ] **Step 1: Написать русскую страницу**

Скопировать `docs/index.html` в `docs/ru/index.html` и заменить: `lang="en"` → `lang="ru"`; `href="ru/"` → `href="../"` с текстом `English`; `src="demo.gif"` → `src="../demo.gif"`; все английские тексты — на русские ниже. `<style>` и `<script>` не меняются.

```html
<title>ghbdtn vbh — автопереключение раскладки для macOS</title>
<meta name="description" content="Набираешь ghbdtn vbh — получаешь «привет мир». Бесплатно, открытый код, в приложении нет сетевого кода.">
```

```html
<a class="lang" href="../">English</a>
```

```html
  <h1>ghbdtn vbh</h1>
  <p class="type" id="type">привет мир</p>
  <p class="lead">Автопереключение раскладки для macOS. Бесплатно, открытый код, и ничего никуда не отправляется.</p>
</header>

<img src="../demo.gif" alt="Набрано ghbdtn rfr ltkf hello — на экране привет как дела hello" width="800">

<h2>Установка</h2>
<pre>brew tap mikakostoev/ghbdtn-vbh https://github.com/mikakostoev/ghbdtn-vbh &amp;&amp; brew install --cask --no-quarantine ghbdtn-vbh</pre>
<p>Или <a href="https://github.com/mikakostoev/ghbdtn-vbh/releases/latest">скачать zip</a> и перетащить <code>ghbdtn vbh.app</code> в Программы. macOS 13 и новее, Apple silicon и Intel.</p>
<p class="note">При первом запуске macOS блокирует приложение: нажмите «Открыть всё равно» в Системных настройках → Конфиденциальность и безопасность, затем разрешите его в Универсальном доступе. Приложение откроет окно и проведёт по шагам. За сборкой нет платного сертификата Apple, поэтому после обновления разрешение спрашивается снова.</p>

<h2>Что умеет</h2>
<ul>
  <li>Исправляет слово на месте: <code>ghbdtn</code> → «привет», <code>руддщ</code> → «hello». Любая раскладка, которую знает macOS, не только русская и английская.</li>
  <li>Понимает сленг и имена, которых нет в системном словаре, по статистике букв: <code>ltdjgcjd</code> → «девопсов».</li>
  <li>Справляется с Caps Lock, аббревиатурами, идентификаторами вроде <code>getUserName</code>, числами и растянутыми словами.</li>
  <li>Двойной Option конвертирует последнее слово или выделение вручную.</li>
  <li>Исключения по словам, приложениям и сайтам.</li>
</ul>

<h2>Почему ему можно доверить клавиатуру</h2>
<ul>
  <li><strong>Сети нет совсем.</strong> Ни обновлений, ни статистики, ни проверки лицензий, ни отчётов о сбоях. Один <code>grep</code> по исходникам не находит ни одной сетевой библиотеки.</li>
  <li><strong>Код короткий и открытый.</strong> Около тысячи строк Swift, читается за вечер.</li>
  <li><strong>Набранное не хранится.</strong> В памяти — слово, которое вы печатаете, и не больше трёх коротких слов перед ним. На диск не пишется.</li>
  <li><strong>Пароли не читаются.</strong> В защищённом поле приложение не смотрит на клавиши вообще.</li>
  <li><strong>Три текстовых файла</strong> в Application Support: исключения, выученные слова и исключённые сайты. Все видны в настройках.</li>
</ul>

<h2>Языки</h2>
<p>Работают как русский и английский: украинский, немецкий, французский, испанский, итальянский, португальский, нидерландский, датский, норвежский, шведский, финский, исландский, чешский, польский, словацкий, венгерский, румынский, болгарский, греческий, турецкий, литовский, иврит, арабский.</p>
<p class="note">Слабее без системного словаря (хорватский, эстонский, македонский, албанский, сербский, фарси, грузинский) и для раскладок, чьи буквы совпадают с английскими. Не работает для методов ввода (китайский, японский, корейский), письменностей без пробелов и раскладок с мёртвыми клавишами. Честный список — в <a href="https://github.com/mikakostoev/ghbdtn-vbh#languages">README</a>.</p>

<footer>
  <a href="https://github.com/mikakostoev/ghbdtn-vbh">GitHub</a> ·
  <a href="https://github.com/mikakostoev/ghbdtn-vbh/releases">Релизы</a> ·
  <a href="https://github.com/mikakostoev/ghbdtn-vbh/blob/main/LICENSE">MIT</a> ·
  <a href="https://github.com/mikakostoev/ghbdtn-vbh/blob/main/NOTICE.md">Notice</a>
</footer>
```

- [ ] **Step 2: Проверить**

Run: `grep -nE '<script[^>]+src|<link|@import|url\(' docs/ru/index.html; echo "exit $?"; grep -c 'href="../"' docs/ru/index.html; grep -c 'src="../demo.gif"' docs/ru/index.html`
Expected: `exit 1`, `1`, `1`. Открыть в браузере, переключатель языков ведёт туда и обратно, gif виден.

- [ ] **Step 3: Commit, PR, merge**

```bash
git add docs/ru/index.html && git commit -m "Add the Russian page of the site

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -u origin site
gh pr create --title "Site on GitHub Pages" --body "$(cat <<'EOF'
Two static pages in docs/ (English and Russian), no build step, no external scripts or fonts. demo.gif moves from .github/ to docs/ so Pages can serve it; the repository still holds one binary.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
gh pr checks --watch
gh pr merge --merge --delete-branch
```

### Task 11: Включить Pages и прописать адрес сайта

**Files:**
- Modify: `README.md` (первый абзац)

- [ ] **Step 1: Включить Pages из docs/ на main**

```bash
gh api -X POST repos/mikakostoev/ghbdtn-vbh/pages -f 'source[branch]=main' -f 'source[path]=/docs'
gh repo edit --homepage https://mikakostoev.github.io/ghbdtn-vbh/
```
Если API отвечает 409 (Pages уже включён) — `gh api -X PUT repos/mikakostoev/ghbdtn-vbh/pages -f 'source[branch]=main' -f 'source[path]=/docs'`.

- [ ] **Step 2: Дождаться деплоя**

Run (повторять раз в минуту до 200): `curl -sI https://mikakostoev.github.io/ghbdtn-vbh/ | head -1 && curl -sI https://mikakostoev.github.io/ghbdtn-vbh/ru/ | head -1 && curl -sI https://mikakostoev.github.io/ghbdtn-vbh/demo.gif | head -1`
Expected: три `HTTP/2 200`.

- [ ] **Step 3: Ссылка в README**

```bash
git checkout main && git pull && git checkout -b readme-site
```
Во втором абзаце README (после заголовка) добавить в конец: ` Site: [mikakostoev.github.io/ghbdtn-vbh](https://mikakostoev.github.io/ghbdtn-vbh/).`

```bash
git add README.md && git commit -m "Link the site from the README

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -u origin readme-site && gh pr create --fill --body "🤖 Generated with [Claude Code](https://claude.com/claude-code)" && gh pr checks --watch && gh pr merge --merge --delete-branch
```

---

## PR 4 — Пайплайн подписи

### Task 12: Скрипты принимают Developer ID

**Files:**
- Modify: `release.sh:8`
- Modify: `build.sh` (блок `codesign` в конце)

**Interfaces:**
- Produces: `IDENTITY="Developer ID Application: …" ./release.sh X` подписывает с hardened runtime и timestamp; без `IDENTITY` — ad-hoc, как раньше.

- [ ] **Step 1: Ветка**

```bash
git checkout main && git pull && git checkout -b notarize
```

- [ ] **Step 2: release.sh**

Строку `OUT=dist UNIVERSAL=1 IDENTITY=- VERSION="$VERSION" ./build.sh` заменить на:

```sh
# IDENTITY from the environment wins: the release workflow passes a Developer ID when the secrets are there.
OUT=dist UNIVERSAL=1 IDENTITY="${IDENTITY:--}" VERSION="$VERSION" ./build.sh
```

Комментарий в шапке release.sh заменить на:

```sh
# ./release.sh 2.0.0 — universal build zipped into dist/, ready to attach to a GitHub release.
# Ad-hoc-signed by default (a self-signed local identity means nothing on another Mac); with IDENTITY set to a
# "Developer ID Application" certificate the build is ready for notarization — see .github/workflows/release.yml.
```

- [ ] **Step 3: build.sh — hardened runtime для Developer ID**

Последние строки build.sh (`codesign --force -s "$IDENTITY" "$BUNDLE"` и `echo`) заменить на:

```sh
# Notarization wants the hardened runtime and a secure timestamp; an event tap and Accessibility need no
# entitlements under it. Only for a real Developer ID: the timestamp server is a network call, and a local
# self-signed build should work offline.
case "$IDENTITY" in "Developer ID"*) SIGN_FLAGS="--options runtime --timestamp";; *) SIGN_FLAGS="";; esac
codesign --force $SIGN_FLAGS -s "$IDENTITY" "$BUNDLE"
echo "Built $BUNDLE"
```

- [ ] **Step 4: Проверить, что дефолтный путь не изменился**

```bash
./release.sh 0.0.0 && codesign -dv "dist/ghbdtn vbh.app" 2>&1 | grep -E "Signature|flags" ; rm -rf dist
```
Expected: `Signature=adhoc`, флаги без `runtime`. Сборка через `./build.sh` с локальным сертификатом тоже проходит без сети (нет `--timestamp`).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Let release.sh sign with a Developer ID when one is given

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 13: release.yml — условная подпись и нотаризация

**Files:**
- Modify: `.github/workflows/release.yml` (целиком)
- Modify: `CONTRIBUTING.md` (новый раздел перед «How the code is laid out»)

**Interfaces:**
- Consumes: секреты репозитория `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD`. Пока их нет — все условные шаги пропускаются.

- [ ] **Step 1: release.yml**

```yaml
# A tag v2.0.0 builds the universal zip on a clean runner with the same release.sh anyone can run at home,
# and attaches it to the GitHub release of that tag (creating the release if the tag was pushed bare).
# So the file on the Releases page is the code in the repository, built by nobody's Mac in particular.
#
# Signing. Without secrets the build is ad-hoc and Gatekeeper asks for "Open Anyway". Add these repository
# secrets and the same tag comes out signed, notarized and stapled:
#   DEVELOPER_ID_P12          base64 of the "Developer ID Application" certificate with its key (.p12)
#   DEVELOPER_ID_P12_PASSWORD password of that .p12
#   NOTARY_APPLE_ID           the Apple ID of the developer account
#   NOTARY_TEAM_ID            its 10-character Team ID
#   NOTARY_PASSWORD           an app-specific password from appleid.apple.com
name: release

on:
  push:
    tags: ["v*"]

permissions:
  contents: write

jobs:
  release:
    runs-on: macos-latest
    env:
      # `secrets` can't be read in an `if`; an env var can.
      P12: ${{ secrets.DEVELOPER_ID_P12 }}
    steps:
      - uses: actions/checkout@v5
      - name: Import the Developer ID certificate
        if: env.P12 != ''
        env:
          P12_PASSWORD: ${{ secrets.DEVELOPER_ID_P12_PASSWORD }}
        run: |
          echo "$P12" | base64 --decode > cert.p12
          security create-keychain -p "" build.keychain
          security list-keychains -d user -s build.keychain login.keychain
          security unlock-keychain -p "" build.keychain
          security import cert.p12 -k build.keychain -P "$P12_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -s -k "" build.keychain
          rm cert.p12
          ID=$(security find-identity -v -p codesigning build.keychain | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
          [ -n "$ID" ] || { echo "no Developer ID Application identity in the .p12"; exit 1; }
          echo "IDENTITY=$ID" >> "$GITHUB_ENV"
      - run: ./release.sh "${GITHUB_REF_NAME#v}"
      - name: Notarize and staple
        if: env.P12 != ''
        env:
          APPLE_ID: ${{ secrets.NOTARY_APPLE_ID }}
          TEAM_ID: ${{ secrets.NOTARY_TEAM_ID }}
          PASSWORD: ${{ secrets.NOTARY_PASSWORD }}
        run: |
          V="${GITHUB_REF_NAME#v}"
          xcrun notarytool submit "dist/ghbdtn-vbh-$V.zip" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$PASSWORD" --wait
          xcrun stapler staple "dist/ghbdtn vbh.app"
          rm "dist/ghbdtn-vbh-$V.zip"
          ditto -c -k --keepParent "dist/ghbdtn vbh.app" "dist/ghbdtn-vbh-$V.zip"
      - run: |
          gh release upload "$GITHUB_REF_NAME" dist/ghbdtn-vbh-*.zip --clobber ||
          gh release create "$GITHUB_REF_NAME" dist/ghbdtn-vbh-*.zip --title "ghbdtn vbh ${GITHUB_REF_NAME#v}" --generate-notes
        env:
          GH_TOKEN: ${{ github.token }}
```

- [ ] **Step 2: Проверить YAML**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('yaml ok')" 2>/dev/null || ruby -ryaml -e "YAML.load_file('.github/workflows/release.yml'); puts 'yaml ok'"`
Expected: `yaml ok`.

- [ ] **Step 3: CONTRIBUTING — раздел «Releasing»**

Вставить перед `## How the code is laid out`:

```markdown
## Releasing

`git tag v2.1.0 && git push origin v2.1.0`. The release workflow builds the universal zip with `release.sh`,
attaches it to the GitHub release, and the cask workflow points `Casks/ghbdtn-vbh.rb` at it. The build is
ad-hoc-signed until the five signing secrets listed at the top of `.github/workflows/release.yml` exist in the
repository; with them the same tag comes out signed with a Developer ID, notarized and stapled, and macOS
opens it without "Open Anyway". Nothing in the app changes either way.
```

- [ ] **Step 4: Commit, PR, merge**

```bash
git add -A && git commit -m "Sign and notarize the release when the Developer ID secrets exist

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -u origin notarize
gh pr create --title "Notarization pipeline, off until the secrets exist" --body "$(cat <<'EOF'
release.yml imports a Developer ID from repository secrets, signs with the hardened runtime, notarizes and staples — only when DEVELOPER_ID_P12 is set. Without it the tag builds ad-hoc exactly as before. The app's code is untouched.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
gh pr checks --watch
gh pr merge --merge --delete-branch
```

---

## Релиз

### Task 14: Тег v2.0.0

**Files:** нет.

Публичное действие: появляется релиз на GitHub, cask переключается на него. Выполнять после того, как все четыре PR влиты и `main` зелёный.

- [ ] **Step 1: Убедиться, что main чист и зелёный**

```bash
git checkout main && git pull && git status --short && gh run list --workflow test --limit 1
```
Expected: `git status` пуст, последний прогон `completed success`.

- [ ] **Step 2: Тег**

```bash
git tag v2.0.0 && git push origin v2.0.0
gh run watch "$(gh run list --workflow release --limit 1 --json databaseId -q '.[0].databaseId')"
```
Expected: workflow `release` зелёный.

- [ ] **Step 3: Проверить релиз и cask**

```bash
gh release view v2.0.0 --json assets -q '.assets[].name'
sleep 90; git pull; head -4 Casks/ghbdtn-vbh.rb
```
Expected: `ghbdtn-vbh-2.0.0.zip`; в cask `version "2.0.0"` и новый sha256 (коммит «Point the cask at 2.0.0» от github-actions).

- [ ] **Step 4: Установка с нуля через brew**

```bash
brew untap mikakostoev/layout-switcher 2>/dev/null; true
brew tap mikakostoev/ghbdtn-vbh https://github.com/mikakostoev/ghbdtn-vbh && brew install --cask --no-quarantine ghbdtn-vbh
ls "/Applications/ghbdtn vbh.app" && open "/Applications/ghbdtn vbh.app"
```
Expected: приложение установлено и запускается; открывается окно первого запуска (грант к новому bundle ID ещё не выдан).
