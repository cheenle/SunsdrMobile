# Archived — 2026-09-12

This project has been merged into **SunMRRC** as its native iOS client.

It was never a standalone product. The app opens the same four WebSocket connections the
browser does — `ctrl`, RX audio, TX audio and spectrum — against the SunMRRC server
(default `radio.vlsc.net:8889`), and in its own README's words it is *"a complete mobile
replacement for the web frontend"*.

- Successor repository: <https://github.com/cheenle/sunsdr> — the app now lives at
  [`SunsdrMobile/`](https://github.com/cheenle/sunsdr/tree/main/SunsdrMobile)
- Successor site: <https://www.vlsc.net/sunmrrc/ios/>
  (`https://www.vlsc.net/sunsdrmobile/` 301-redirects here)

## Why archive rather than keep the two repos in sync

`cheenle/sunsdr` tracked this directory as a **gitlink** (mode `160000`) with **no
`.gitmodules`** — an unconfigured nested-repo reference. The consequence was that
`sunsdr`'s `git status` reported ` M SunsdrMobile` permanently, and a clone of `sunsdr`
received no app code at all.

The merge replaced that gitlink with a real directory. The app's **full 9-commit history
was imported with `git subtree`**, so nothing is lost by archiving this repository.

## Status

The app has **not** been submitted to the App Store. App Store submission and every
audio-path judgement on a real handset stay with a human; simulator output is never
presented as on-air evidence.

Deployment from this repository is disabled — `website/deploy.sh` exits immediately.
