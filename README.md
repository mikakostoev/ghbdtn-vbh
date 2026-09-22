# ghbdtn vbh → привет мир

[![test](https://github.com/mikakostoev/ghbdtn-vbh/actions/workflows/test.yml/badge.svg)](https://github.com/mikakostoev/ghbdtn-vbh/actions/workflows/test.yml)
[![release](https://img.shields.io/github/v/release/mikakostoev/ghbdtn-vbh?label=release)](https://github.com/mikakostoev/ghbdtn-vbh/releases/latest)
[![downloads](https://img.shields.io/github/downloads/mikakostoev/ghbdtn-vbh/total?label=downloads)](https://github.com/mikakostoev/ghbdtn-vbh/releases)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)](#installation-in-detail)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](Package.swift)
[![license MIT](https://img.shields.io/github/license/mikakostoev/ghbdtn-vbh?label=license)](LICENSE)

Keyboard layout auto-switcher for macOS. You type `ghbdtn vbh`, you get «привет мир». Free, open source, and
nothing phones home: the app contains no networking code at all. Site:
[mikakostoev.github.io/ghbdtn-vbh](https://mikakostoev.github.io/ghbdtn-vbh/).

## How it works

You start typing in one language while the keyboard is still in another layout — the app fixes the word on the
spot. `ghbdtn rfr ltkf hello` becomes «привет как дела hello». It works with any keyboard layout macOS knows,
not only Russian and English ([details below](#languages)).

![Typed ghbdtn rfr ltkf hello — the screen shows привет как дела hello](docs/demo.gif)

To fix only the last word, or the text you have selected, press Option twice (the shortcut is configurable).

## Quick start

1. **Install.** The easiest way is Homebrew:
   ```bash
   brew tap mikakostoev/ghbdtn-vbh https://github.com/mikakostoev/ghbdtn-vbh && brew install --cask --no-quarantine ghbdtn-vbh
   ```
   Or download the archive from [Releases](https://github.com/mikakostoev/ghbdtn-vbh/releases) and drag
   `ghbdtn vbh.app` into Applications.
   **Upgrading from LayoutSwitcher:** remove the old app first, or you'll end up with two switchers fighting
   over the same keystrokes — `brew uninstall --cask layoutswitcher --zap` if you installed it with Homebrew, or
   drag `LayoutSwitcher.app` from Applications to the Trash otherwise. Switch "Open at login" back on in the new
   app: that setting is tied to the old app's identity and doesn't carry over.
2. **Grant access.** On first launch macOS blocks the app. Go to System Settings → Privacy & Security, click
   "Open Anyway", then allow the app under Accessibility. Without that it cannot see keystrokes.
3. **Try it.** Open any text editor, type `ghbdtn` and press space.

Installation and building are covered [below](#installation-in-detail); how to help is in
[CONTRIBUTING.md](CONTRIBUTING.md).

## Why it can be trusted with your keyboard

The app sees everything you type; it cannot work otherwise. Here is why that is safe:

- **No network, none.** No updates, usage statistics, licence checks or crash reports. Easy to verify with a
  command that looks for any networking library in the code — the output is empty:
  ```bash
  grep -rnE "URLSession|URLRequest|NWConnection|CFSocket|WebKit" Sources/
  ```
- **The code is short and open.** About a thousand lines of Swift in `Sources/` (not counting `Trigrams.swift`,
  a generated table of numbers). It can be read in an evening.
- **Nothing you type is kept.** Memory holds only the word you are typing right now (and at most three short
  words before it). A mouse click, an arrow key or a window switch clears the buffer. It is never written to disk;
  there is no typing log.
- **Passwords are off limits.** While the system reports a secure field (a password manager, a browser's
  password box), the app does not look at the keys at all.
- **Minimal footprint.** The app creates three plain text files in `~/Library/Application Support/ghbdtn vbh/`:
  your exceptions (`exceptions.txt`), your manual corrections (`words.txt`) and excluded sites (`sites.txt`).
  All of them are visible in the settings.
- **The clipboard is barely touched.** Only in one case: you asked to convert the selected text, and the
  application (Electron, some browsers) does not hand it over directly. Then the app presses Cmd+C, reads the
  text and immediately puts back whatever the clipboard held before.
- **Local statistics.** Unknown words are judged by a built-in table of letter-combination frequencies. It holds
  dry probabilities only; none of your words are in it.

## What it does

- Switches whole words: `ghbdtn` → «привет», `руддщ` → «hello».
- Understands slang and names the system dictionary doesn't know, from the statistics of the language:
  `ltdjgcjd` becomes «девопсов».
- Fixes short words retroactively at the start of a phrase: `ye ns ghbdtn` → «ну ты привет».
- Copes with Caps Lock, abbreviations (`cif` → «сша»), identifiers (`getUserName`), numbers (`10ю5` → `10.5`)
  and stretched words («привееет»).
- Double Option converts the last word or your selection by hand.
- Knows exceptions: switching can be turned off for particular apps or sites, and you can add your own words.
- The interface follows the system language (English or Russian), and the menu bar icon dims when switching
  is off.

**What it doesn't have (unlike the commercial alternatives):** a Windows version, support inside RDP and
virtual machines, typo correction, and years of user base.

## Languages

Any keyboard layout macOS has will do: the language comes from the layout itself, words are checked against
the system dictionary and the built-in letter statistics (available for 35 languages). Honestly, here is where
it works and where it doesn't.

**Works like Russian and English do:** Ukrainian, German, French, Spanish, Italian, Portuguese, Dutch, Danish,
Norwegian, Swedish, Finnish, Icelandic, Czech, Polish, Hungarian, Romanian, Bulgarian, Greek, Turkish,
Lithuanian, Hebrew, Arabic. Only Russian, English, Ukrainian and German are checked on texts; the others use the
same mechanism.

**Works poorly:**

- *Languages without a system dictionary* — Croatian, Slovak, Estonian, Macedonian, Albanian, Serbian, Farsi,
  Georgian. Letter statistics decide alone: common words are held without a single error, rare words and names
  see 2–9 false switches per three thousand (see `Tests/stress-*.txt`).
- *Layouts whose letters match the English ones* — Croatian, Slovak, Estonian, Czech, Polish, Hungarian. Typed
  on the English layout, only č, š, ő and the like come out wrong, and such words are not fixed. The other way
  works: an English word typed on such a layout switches the layout back.
- *Phonetic layouts* — Macedonian, Bulgarian-Phonetic, Russian-Phonetic. «убаво» typed on the English layout
  reads «ubavo», and the statistics can't tell the difference; only words with letters like ш, ж, ч get fixed.
- *Languages without a layout of their own* — Indonesian, Catalan, Basque, Esperanto. They are typed on the
  English or Spanish layout, so the app takes them for English or Spanish: hardly any false switches, but no
  dictionary protects their words either.

**Doesn't work:**

- *Chinese, Japanese, Korean* — these are input methods, not keyboard layouts.
- *Thai, Lao, Khmer, Burmese, Tibetan* — with no spaces between words the app can't see where a word ends.
- *Latvian, Vietnamese* and other layouts with dead keys: accented letters take two keystrokes, and a word with
  ā or ệ never comes together.
- *Hindi, Bengali, Tamil* and the other Indic scripts — untested; don't expect much.
- *Belarusian, Armenian, Kazakh, Kyrgyz, Tajik, Uzbek, Azerbaijani, Urdu* and any other language with neither
  a macOS dictionary nor a statistics table in the app: their words are left alone entirely.

## Accuracy and speed

Instead of promises, tests anyone can run (`./test.sh`):

- On everyday texts (chat, work talk, a bit of code): **zero false switches**. The only words left unfixed are
  tiny two- and three-letter ones that read as words in both layouts — the next word usually fixes them.
- On 5,700 rare words and names from subtitles: 3 mistakes in total.
- Eight languages without a system dictionary (from Croatian to Farsi and Georgian) are checked separately:
  zero false switches on common words, 2–9 per three thousand rare ones, mostly English words that sit inside
  the foreign lists.
- A decision is made locally, in memory, in under a millisecond. Even in a hard test of 11,000 substitutions
  only a handful took longer than 10 ms (the macOS dictionary itself thinking things over).

## Installation in detail

- **Prebuilt:** download the `.zip` from [Releases](https://github.com/mikakostoev/ghbdtn-vbh/releases),
  unpack and move the `.app` into Applications. The build is universal (Apple Silicon and Intel) and needs
  macOS 13 Ventura or newer. The file is built automatically on GitHub's servers from the very code in the
  repository.
- **First launch:** the app has no paid Apple developer certificate ($99 a year), so macOS stops it. Click
  "Open Anyway" in the notification, or right-click the icon → Open. After every update the Accessibility grant
  has to be given again — the build's signature changes.
- **Homebrew:** the command above. Installed without `--no-quarantine`, the first launch needs the same "Open
  Anyway" step.

## Building from source (if you don't trust the prebuilt file)

Xcode or the Command Line Tools are required.

```bash
git clone https://github.com/mikakostoev/ghbdtn-vbh.git && cd ghbdtn-vbh
```

```bash
./build.sh
```

```bash
open "ghbdtn vbh.app"
```

To stop macOS from asking for Accessibility after every rebuild, create a free self-signed code-signing
certificate in Keychain Access named `LayoutSwitcher Local Signing` (Certificate Assistant). The scripts build
and sign the app with it.

A release is built with `./release.sh 2.0.0`, which produces the universal archive. A version tag on GitHub does
exactly the same and attaches the file to the release.

## Making sure it works

- `./test.sh` — builds, runs the self-test and the checks on texts.
- `Tests/live.sh` — opens a test window and emulates live typing for a few seconds, taking over the keyboard.

## Licence

All code is [MIT](LICENSE). The letter frequency tables and the stress tests are derived from the open
[FrequencyWords](https://github.com/hermitdave/FrequencyWords) dataset, distributed under CC BY-SA 4.0
([NOTICE.md](NOTICE.md)).
