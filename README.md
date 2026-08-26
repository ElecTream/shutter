# Shutter

A daily planner: lists, reminders, archive, and custom themes.

| | |
| --- | --- |
| **Brand** | ElecTream |
| **Listing** | Shutter |
| **Package** | `com.electream.shutter` |
| **Version** | 2.2.13 (add `+build` before Play) |
| **Platforms** | Android first; iOS/desktop/web folders exist but are not the ship target |

## What it does

- Multi-list tasks with per-list theme overrides
- Scheduled reminders with a **Mark Complete** action (works if the app is killed)
- Archive, custom themes, haptics, text scale
- Export / import / wipe from settings (JSON on the clipboard)
- Google Sign-In and Firebase are in the tree; list data itself lives in `SharedPreferences` on device

## Run

```sh
flutter pub get
flutter run
```

Android release (today still debug-signed — do not upload that AAB):

```sh
flutter build appbundle --release
```

## Docs

| File | What it is |
| --- | --- |
| [PRIVACY.md](PRIVACY.md) | Privacy policy (host a public copy for Play) |
| [STORE.md](STORE.md) | Play listing copy, Data safety, upload checklist |
