# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cashew is a cross-platform personal finance / expense tracking Flutter app (iOS, Android, Web PWA, Desktop). All app code lives in the `budget/` subdirectory.

## Flutter Version

This project requires **Flutter 3.24.5** (Dart 3.5.4). The system Flutter (3.41.x / Dart 3.7+) is incompatible because Dart 3.7 removed `UnmodifiableUint8ListView` from `dart:typed_data`, which the `win32` 5.x dependency requires.

Use [fvm](https://fvm.app/) to manage the Flutter version:

```bash
# Install fvm (one-time)
dart pub global activate fvm

# Install and use the correct Flutter version
fvm install 3.24.5
fvm use 3.24.5   # run from inside budget/

# All flutter/dart commands must be prefixed with fvm:
fvm flutter run
fvm flutter pub get
fvm dart run build_runner build
```

`budget/android/local.properties` must have `flutter.sdk` pointing to the fvm installation:
```
flutter.sdk=/Users/<you>/fvm/versions/3.24.5
```

## Common Commands

All commands should be run from `budget/` and prefixed with `fvm`:

```bash
# Run the app
fvm flutter run

# Install dependencies
fvm flutter pub get

# Lint/analyze
fvm flutter analyze

# Run tests
fvm flutter test

# Run a single test file
fvm flutter test test/widget_test.dart

# Regenerate database code after schema changes
fvm dart run build_runner build

# Export database schema (replace VERSION with next version number)
fvm dart run drift_dev schema dump lib/database/tables.dart drift_schemas/drift_schema_vVERSION.json

# Regenerate schema migration steps after adding a new schema version
fvm dart run drift_dev schema steps drift_schemas/ lib/database/schema_versions.dart

# Build for web (Firebase hosting)
fvm flutter build web --release --web-renderer canvaskit --no-tree-shake-icons

# Deploy to Firebase
firebase deploy

# Build Android APK
fvm flutter build apk --debug
```

## Architecture

### Directory Structure

```
budget/lib/
├── main.dart               # App entry point; initializes Firebase, database, settings
├── colors.dart             # Theme, color palette, and dark/light mode logic
├── functions.dart          # Large shared utility file (~48KB)
├── database/               # Drift/SQLite layer
│   ├── tables.dart         # Schema definitions (source of truth)
│   ├── tables.g.dart       # Generated — do not edit manually
│   ├── schema_versions.dart # Migration steps (generated, then hand-edited)
│   └── platform/           # Platform-specific DB initialization (mobile vs web)
├── pages/                  # Full-screen route widgets (~44 pages)
├── widgets/                # Reusable UI components (~93 files)
├── struct/                 # Business logic modules
│   ├── settings.dart       # App settings (SharedPreferences wrappers)
│   ├── syncClient.dart     # Firebase Cloud Firestore sync
│   ├── currencyFunctions.dart
│   ├── defaultCategories.dart
│   ├── defaultPreferences.dart
│   └── notifications.dart
└── modified/               # Vendored modified third-party code
```

Local modified packages live in `budget/packages/`.

### State Management

Uses `provider` for state. The database (`AppDatabase`) is a central singleton accessed throughout the app. Settings are persisted via `SharedPreferences` and exposed through helpers in `struct/settings.dart`.

### Database (Drift/SQLite)

- Schema is defined in `database/tables.dart`
- After any schema change: bump the version, export the schema JSON, then regenerate `schema_versions.dart`
- Migrations must be written manually in `schema_versions.dart` after code generation
- Cloud sync via Firebase Cloud Firestore (`struct/syncClient.dart`)

### Naming Conventions (Internal vs UI)

- **Wallets** in code → displayed as **Accounts** in UI
- **Objectives** in code → displayed as **Goals** in UI

### Cross-Platform Utilities

- Use `getPlatform()` instead of `Platform` (not available on web)
- Use `pushRoute()` wrapper for navigation (handles web/mobile differences)

### Localization

- Multi-language via `easy_localization`; translation files in `assets/translations/generated/`
- Source translations managed in Google Sheets; use `generate-translations.py` (or `update_translations.bat` on Windows) to pull updates

## Android Build Environment

The Android build toolchain has been fully migrated to the modern declarative Gradle plugin style.

| Component | Version | Notes |
|-----------|---------|-------|
| Gradle | 8.9 | Required for Java 21 compatibility |
| Android Gradle Plugin (AGP) | 8.7.0 | Required for `compileSdk 35` |
| Kotlin plugin | 2.1.0 | Must match stdlib version |
| `compileSdk` | 35 | Required by `home_widget` |
| `minSdk` | 23 | Required by `firebase_auth` |
| `targetSdk` | 34 | |
| JVM target | 17 | All modules (app + libraries) pinned to Java 17 |

**Key Gradle workarounds in `budget/android/build.gradle`:**
- Old Flutter plugins (e.g. `flutter_charset_detector_android`) don't declare a `namespace` as required by AGP 8.x — the root build file auto-assigns `project.group` as the namespace via `afterEvaluate`.
- All library Kotlin modules are pinned to `jvmTarget = "17"` globally to prevent JVM target mismatch errors when Android Studio's JDK is Java 21.

**Package version constraints** (cannot upgrade without breaking compatibility with Flutter 3.24.5):
- `intl: ^0.19.0` — Flutter 3.24.5 pins intl to 0.19.x
- `carousel_slider: ^5.1.2` — 4.x had a `CarouselController` naming conflict with Flutter material
- `home_widget: ^0.9.0` — 0.5.x used the removed `ViewConfiguration.size` API
- `device_preview` — import removed from `main.dart` (always-disabled; 1.3.1 requires Dart 3.8 which is unavailable on Flutter 3.24.5)
