# Discipline – Personal Habit Tracker

A Flutter web application for tracking daily habits, maintaining consistency, and reviewing progress over time. The app is designed as a local-first productivity tool for Vietnamese users, with a polished Material 3 interface and browser-local persistence.

## Features

- Habit management with create, edit, and delete flows
- Daily completion tracking with per-date persistence
- Habit frequency logic for daily, weekdays, and custom schedules
- Progress overview for today and recent activity
- Statistics for day, week, and month views
- Settings screen with reminder toggle and browser limitation note
- Vietnamese-friendly UI labels and date formatting
- Local data storage using SharedPreferences

## Tech stack

- Flutter 3.x
- Dart 3.x
- Provider for app state
- SharedPreferences for local persistence
- fl_chart for chart-based statistics
- intl for Vietnamese date/number formatting

## Getting started

1. Install Flutter 3.47.5 or newer and ensure the Flutter SDK is on your PATH.
2. Run the dependency install command:
   ```bash
   flutter pub get
   ```
3. Start the app in development mode:
   ```bash
   flutter run -d chrome
   ```
4. To build the production web bundle:
   ```bash
   flutter build web --release
   ```

## Validation

This project includes a smoke test and can be verified with:

```bash
flutter test
```

The app has also been validated with:

```bash
flutter analyze
flutter build web --release
```

## Notes

- Data persists only in the browser using local storage, so it is not backed by a remote server.
- Reminder notifications are intentionally conservative on web because browser notification support is limited compared to native platforms.
- The app is designed as a self-contained demo and personal productivity tool rather than a backend-driven service.
