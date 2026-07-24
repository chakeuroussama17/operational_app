# HICOM Ops — Production Shift Log

A Flutter app for HICOM Diecastings that replaces the paper shift logbook.
Supervisors log hourly production for three areas — **Casting**, **Secondary**
and **Machining** — straight into Google Sheets, and view live analytics.

## Features

- **Incremental logging** — one row per machine/part/line per day, updated
  throughout the shift (partial saves merge onto the same row).
- **Three modules**
  - Casting — DCM machine → part → hourly output, auto LOR%.
  - Secondary — station → part → hourly actual, auto LOR%.
  - Machining — customer → part → line → hourly output + rejection, auto LOR%.
- **Manage on the fly** — add / rename / delete DCMs, stations, customers,
  parts and lines from the app (tap the "+" tile or long-press a card). Edits
  never touch historical logged data.
- **Dashboard** — live output / LOR% / rejection trend charts per module
  (7 / 14 / 30 day ranges), pulled straight from the sheet.
- **Light & dark mode** — follows the system theme or a manual toggle.

## Architecture

- **App**: Flutter (Material 3), talks to a single Google Apps Script Web App.
- **Backend**: `apps_script/Code.gs` — a stateless Apps Script deployment that
  reads/writes the Google Sheet (Casting / Secondary / Machining / Config tabs)
  and computes LOR% and daily analytics. Deploy it as a Web App and put the
  `/exec` URL in `lib/config/constants.dart` (`CASTING_WEBHOOK_URL`).

## Build

CI builds the Android APK automatically — see
[`.github/workflows/build.yml`](.github/workflows/build.yml). Push to `main`
(or run the workflow manually from the **Actions** tab), then download the
**hicom-ops-apk** artifact from the completed run.

Locally:

```bash
flutter pub get
flutter test
flutter build apk --release   # requires the Android SDK
```

## Note on the webhook secret

`lib/config/constants.dart` contains the Apps Script URL and a shared secret.
These ship inside any distributed APK anyway, so treat them as client-side
config, not a real secret — enforce access server-side if it matters.
