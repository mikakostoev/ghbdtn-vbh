# Security

The app sees every key you press, so a security bug here matters more than in most apps. What it promises is
listed below; anything that breaks one of those promises is a vulnerability, for example:

- the app sending anything over the network;
- typed text reaching the disk, a log or the clipboard (beyond the three files and the clipboard case below);
- keys being read while a password field is focused.

Please don't open a public issue for it. Report it privately with
[Report a vulnerability](https://github.com/mikakostoev/ghbdtn-vbh/security/advisories/new) on the Security tab.
English or Russian is fine.

Only the latest release is supported: a fix ships as the next version, and the advisory is published once it is
out.

## Why it can be trusted with your keyboard

The app cannot work otherwise. Here is why that is safe:

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
