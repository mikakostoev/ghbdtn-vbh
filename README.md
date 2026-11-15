<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://ghbdtnvbh.app/icon-dark.png">
  <img src="https://ghbdtnvbh.app/icon-light.png" width="128" height="128" alt="">
</picture>

# ghbdtn vbh → привет мир

[![test](https://github.com/mikakostoev/ghbdtn-vbh/actions/workflows/test.yml/badge.svg)](https://github.com/mikakostoev/ghbdtn-vbh/actions/workflows/test.yml)
[![release](https://img.shields.io/github/v/release/mikakostoev/ghbdtn-vbh?label=release)](https://github.com/mikakostoev/ghbdtn-vbh/releases/latest)
[![downloads](https://img.shields.io/github/downloads/mikakostoev/ghbdtn-vbh/total?label=downloads)](https://github.com/mikakostoev/ghbdtn-vbh/releases)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)](#install)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](Package.swift)
[![license MIT](https://img.shields.io/github/license/mikakostoev/ghbdtn-vbh?label=license)](LICENSE)

**[ghbdtnvbh.app](https://ghbdtnvbh.app)**

</div>

Keyboard layout auto-switcher for macOS. You type `ghbdtn vbh`, you get «привет мир». Free, open source, and
nothing phones home: the app contains no networking code at all.

You start typing in one language while the keyboard is still in another layout — the app fixes the word on the
spot. `ghbdtn rfr ltkf hello` becomes «привет как дела hello». Double Option converts the last word or a
selection (the shortcut is configurable). It works with any keyboard layout macOS knows, not only Russian
and English ([languages](#languages)).

![Typed ghbdtn rfr ltkf hello — the screen shows привет как дела hello](https://ghbdtnvbh.app/demo.gif)

## Install

```bash
brew tap mikakostoev/ghbdtn-vbh https://github.com/mikakostoev/ghbdtn-vbh && brew trust --cask mikakostoev/ghbdtn-vbh/ghbdtn-vbh && brew install --cask ghbdtn-vbh
```

Or download the archive from [Releases](https://github.com/mikakostoev/ghbdtn-vbh/releases) and drag
`ghbdtn vbh.app` into Applications.

Allow the app under Accessibility (System Settings → Privacy & Security). Without that it cannot see
keystrokes.

Open any text editor, type `ghbdtn` and press space.

**Upgrading from LayoutSwitcher:** remove the old app first, or you'll end up with two switchers fighting over
the same keystrokes — `brew uninstall --cask layoutswitcher --zap` if you installed it with Homebrew, or drag
`LayoutSwitcher.app` from Applications to the Trash otherwise. Switch "Open at login" back on in the new app:
that setting is tied to the old app's identity and doesn't carry over.

The app sees everything you type; [why that is safe](SECURITY.md#why-it-can-be-trusted-with-your-keyboard).
How to help, and how to build from source, is in [CONTRIBUTING.md](CONTRIBUTING.md). After every update the
Accessibility grant has to be given again — the build's signature changes.

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
Swedish, Czech, Hungarian, Romanian, Bulgarian, Greek, Turkish, Arabic. Only Russian, English, Ukrainian and
German are checked on texts; the others use the same mechanism.

**Works poorly:**

- *Languages without a system dictionary* — Finnish, Icelandic, Norwegian, Polish, Lithuanian, Hebrew,
  Croatian, Slovak, Estonian, Macedonian, Albanian, Serbian, Farsi, Georgian. Letter statistics decide alone:
  common words are held without a single error, rare words and names see 2–14 false switches per three thousand
  (see `Tests/stress-*.txt`). Which dictionaries macOS ships differs between versions, so the list is what this
  Mac reports: `ghbdtnvbh --selftest` prints the spellers it found, and a language missing from that line lands
  in this group.
- *Layouts whose letters match the English ones* — Croatian, Slovak, Estonian, Czech, Polish, Hungarian. Typed
  on the English layout, only č, š, ő and the like come out wrong, and such words are not fixed. The other way
  works: an English word typed on such a layout switches the layout back.
- *Phonetic layouts* — Macedonian, Bulgarian-Phonetic, Russian-Phonetic. «убаво» typed on the English layout
  reads «ubavo», and the statistics can't tell the difference; only words with letters like ш, ж, ч get fixed.
- *Languages without a layout of their own* — Indonesian, Catalan, Basque, Esperanto. They are typed on the
  English or Spanish layout, so the app takes them for English or Spanish: hardly any false switches, but no
  dictionary protects their words either.
- *Words the system dictionary has learned from you* — the names of installed apps, contacts and anything
  taught with «Learn Spelling» pass as words in every language, so typed in the wrong layout they stay put: the
  app trusts the dictionary. The one exception it makes is its own name — `ghbdtn` and `vbh` switch regardless.

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

## Licence

All code is [MIT](LICENSE). The letter frequency tables and the stress tests are derived from the open
[FrequencyWords](https://github.com/hermitdave/FrequencyWords) dataset, distributed under CC BY-SA 4.0
([NOTICE.md](NOTICE.md)).
