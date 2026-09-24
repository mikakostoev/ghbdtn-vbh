# Security

The app sees every key you press, so a security bug here matters more than in most apps. What it promises is
listed in the README under [Why it can be trusted with your keyboard](README.md#why-it-can-be-trusted-with-your-keyboard);
anything that breaks one of those promises is a vulnerability, for example:

- the app sending anything over the network;
- typed text reaching the disk, a log or the clipboard (beyond the three files and the clipboard case the README
  describes);
- keys being read while a password field is focused.

Please don't open a public issue for it. Report it privately with
[Report a vulnerability](https://github.com/mikakostoev/ghbdtn-vbh/security/advisories/new) on the Security tab.
English or Russian is fine.

Only the latest release is supported: a fix ships as the next version, and the advisory is published once it is
out.
