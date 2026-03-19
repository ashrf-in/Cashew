# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cashew is a cross-platform personal finance / expense tracking Flutter app (iOS, Android, Web PWA, Desktop). All app code lives in the `budget/` subdirectory.

## Common Commands

All commands should be run from `budget/`:

```bash
# Run the app
flutter run

# Install dependencies
flutter pub get

# Lint/analyze
flutter analyze

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Regenerate database code after schema changes
dart run build_runner build

# Export database schema (replace VERSION with next version number)
dart run drift_dev schema dump lib/database/tables.dart drift_schemas/drift_schema_vVERSION.json

# Regenerate schema migration steps after adding a new schema version
dart run drift_dev schema steps drift_schemas/ lib/database/schema_versions.dart

# Build for web (Firebase hosting)
flutter build web --release --web-renderer canvaskit --no-tree-shake-icons

# Deploy to Firebase
firebase deploy
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
