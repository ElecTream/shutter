# Play listing — Shutter

ElecTream. Package `com.electream.shutter`. Version **2.2.13**. Android first.

## Title (30)

Shutter

## Short description (80)

Lists, reminders, and themes. A daily planner that stays out of the way.

## Full description

Shutter is a daily planner for people who live in lists.

Make as many lists as you want. Each can have its own theme. Reminders fire with a Mark Complete action even if the app is closed. Archive old tasks, export your data, or wipe the device copy from settings.

Android first. No ads. Published by ElecTream.

## Data safety (draft)

- Collected: on-device tasks; optional Google account if signed in; optional photos you pick
- Shared: no ads; Google/Firebase are processors if you sign in
- Encrypted in transit: yes (HTTPS when signed in)
- Users can delete: in-app wipe; listing contact for account deletion until that UI ships
- Children: no

## Before upload

- [ ] Release signing (not debug keys) + `version: 2.2.13+N` in pubspec
- [ ] `flutter build appbundle --release`
- [ ] Play App Signing SHAs in Firebase / OAuth for `com.electream.shutter`
- [ ] Public HTTPS URL for [PRIVACY.md](PRIVACY.md)
- [ ] Phone screenshots + 1024×500 feature graphic (`assets/icon`)
- [ ] Data safety form; declare exact-alarm as reminders; justify full-screen intent / FGS if Console asks
- [ ] In-app account deletion if Google Sign-In stays in the shipped build
