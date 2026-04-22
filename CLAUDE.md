# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Shutter — Flutter daily-planner app. Android-first; iOS/desktop/web scaffolding exists but is not actively targeted. Features: multi-list tasks, scheduled reminders with "Mark Complete" action, archive, custom themes.

## Commands

- `flutter pub get` — install deps
- `flutter run` — run on connected device/emulator
- `flutter build apk` / `flutter build appbundle` — Android release artifacts
- `flutter test` — run tests in `test/`
- `flutter test test/foo_test.dart` — single test file
- `flutter analyze` — lints per `analysis_options.yaml` (flutter_lints)

No CI, Makefile, or custom scripts. Android Gradle lives under `android/`.

## Architecture

**State: single `SettingsNotifier`** (`lib/providers/settings_notifier.dart`) — a Provider `ChangeNotifier` that owns themes, archive settings, saved colors, AND TaskList CRUD. No Bloc/Riverpod. Swapping state solutions would require rewriting persistence; don't.

**Persistence: `SharedPreferences` only** — no DB. Key scheme:
- `todos_{listId}` — JSON `Task[]` (use `todos_root` for the root container)
- `archivedTodos_{listId}` — JSON `ArchivedTask[]`
- `taskLists` — list metadata (a `TaskList` may carry a nested `themeOverride` JSON)
- `customThemes`, `currentThemeId`, `themeMode`, `archiveClearDuration`, `savedColors`
- `textScale`, `hapticsEnabled`, `defaultReminderHour`, `defaultReminderMinute`
- `migrationVersion` — currently `2` (additive-only migrations; v2 seeds new scalar keys)

Any new persisted field must be read/written in `SettingsNotifier` to survive restarts. New migrations go in `_runMigrations` gated by `migrationVersion`; keep them additive.

**Models**: `lib/models/` — `Task`, `TaskList` (in `list.dart`), `ArchivedTask`, `CustomTheme`.
**Screens**: `lib/screens/` — `TodoScreen`, `ListDetailScreen`, `ArchiveScreen`, `SettingsScreen`, `ThemeEditorScreen`.

## Notification subsystem (load-bearing; rewritten in commit `80df326`)

`lib/services/notification_service.dart` — singleton using `flutter_local_notifications` v19.x with `timezone` zoned scheduling.

- Android channel: `shutter_reminders_v2`, high importance, custom sound `assets/sounds/ding.mp3`.
- **"Mark Complete" action runs in a separate isolate** when the app is killed/backgrounded (`notificationTapBackground()`).
- Background → foreground bridge: `IsolateNameServer` + `ReceivePort`. Background handler writes SharedPreferences directly, then posts an event to the named port if the foreground is alive.
- Foreground listens via `taskCompletedStream`; `SettingsNotifier` subscribes and refreshes UI.
- Timezone resolved once at startup via `MethodChannel('com.example.shutter/timezone')` → `android/app/src/main/kotlin/com/example/shutter/MainActivity.kt`.
- Init is wrapped in try/catch in `main.dart`; failures degrade gracefully.

**When editing notifications, test BOTH code paths**: foreground tap (app open) and background tap (app killed). They diverge.

## Theme system

`CustomTheme` has 7 color properties + `isDeletable` + `version` + `presetId`. Default theme non-deletable. Editor works on a copy and auto-persists in `dispose`.

- **Global themes** live in `customThemes`. Active one = `currentThemeId`.
- **Per-list overrides**: a `TaskList` may carry a full `CustomTheme? themeOverride`. Use `SettingsNotifier.effectiveThemeFor(list)` — always prefer this over `currentTheme` inside list-scoped UI. Root/home/settings stay on the global theme (`effectiveThemeFor(null)`).
- **Presets**: `lib/utils/theme_presets.dart` holds 8 templates. The preset picker sheet (`lib/widgets/preset_picker_sheet.dart`) drives new-theme creation — clones return fresh `CustomTheme` instances with a stable `presetId`.
- **Theme editor modes**: pass `listId` to `ThemeEditorScreen` to persist as a list override instead of a global theme.

## Haptics

All haptic calls go through `lib/utils/haptics.dart` (`Haptics.selection()` / `.light()` / `.medium()` / `.heavy()`). The wrapper short-circuits when `Haptics.enabled == false`. `SettingsNotifier` mirrors its `hapticsEnabled` state to the static flag — **never call `HapticFeedback.*` directly** or the user's toggle won't cover that call site.

## Text scale

`SettingsNotifier.textScale` (0.75–1.40) is injected at the `MaterialApp.builder` level via a `MediaQuery` wrapper with `TextScaler.linear`. It scales every widget that reads from Flutter text themes — no per-widget plumbing needed.

## Data export / import / wipe

`SettingsNotifier.exportAllDataJson()` emits `{schema: 2, prefs: {...}}` covering `_scalarKeys` + every dynamic `todos_*` / `archivedTodos_*`. `importAllDataJson(raw)` rejects non-schema-2 blobs, wipes known keys, writes by type, reloads. `wipeAllData()` is the nuclear reset. Export is copied to clipboard (no `share_plus` dep).

## Gotchas

- `.worktrees/` is gitignored — don't commit inside it.
- `assets/sounds/ding.mp3` is declared in `pubspec.yaml`; renaming/removing breaks notification sound.
- Android notification channel ID changes require a new ID (channels are immutable once created on-device); the `_v2` suffix exists for this reason.
