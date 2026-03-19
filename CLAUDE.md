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

## Intelligence / AI

- AI provider configuration is stored in SharedPreferences-backed settings via `lib/struct/defaultPreferences.dart` and `lib/struct/settings.dart`
- Current AI service layer lives in `lib/struct/intelligence.dart`
- Supported providers today:
	- OpenAI-compatible APIs (`/v1/models`, chat completions-style vision requests)
	- Gemini API (`v1beta/models`, `generateContent`)
- UI for selecting provider, base URL, API key, and model is in `lib/pages/intelligenceSettingsPage.dart`
- Current production AI feature is receipt capture in `lib/pages/addTransactionPage.dart`
	- pick image from camera / gallery / file
	- analyze receipt into merchant, date, amount, tax, wallet/category suggestion, and itemized line items
	- allow per-line editing before split-save
	- auto-attach the scanned receipt image via `lib/struct/uploadAttachment.dart`
- If you extend AI features, keep provider/model handling inside `lib/struct/intelligence.dart` instead of scattering HTTP code across pages
- Prefer deterministic local matching first where possible, then AI as an assistive or fallback layer when confidence is low

## Notification Auto Transactions

- Android-only notification auto-transaction logic currently lives in `lib/pages/autoTransactionsPageEmail.dart`
- `InitializeNotificationService` in `main.dart` starts notification scanning on app launch
- Notification scanning is gated by:
	- `notificationScanning`
	- Android notification-listener permission
	- app-package allowlisting (`_knownFinancialPackages` plus `notificationCustomPackages`)
- Captured notifications are normalized into a single message string containing package name, title, and content
- Recent notifications are kept in-memory in `recentCapturedNotifications`, capped to 50 items
- Parsing is currently deterministic, not AI-driven:
	- first matching `ScannerTemplate.contains` wins
	- `_extractTemplateSegment(...)` extracts title / amount using before/after boundaries
	- `_parseNotificationAmount(...)` handles comma/dot locale variants and negative signs
- Category assignment flow:
	- first try `AssociatedTitles`
	- then fall back to the template's `defaultCategoryFk`
- Route behavior:
	- push `AddTransactionPage` for confirmation by default
	- or silently call `processAddTransactionFromParams(...)`
- Transactions created from notifications are still tagged `MethodAdded.email` because `MethodAdded` has no dedicated notification value yet
- `NOTIFICATION_TRANSACTIONS.md` documents this feature, but verify the code path before relying on the doc if behavior seems inconsistent

### AI Ideas For Notification Auto Transactions

If improving notification auto-transactions with AI, keep the current template system as the primary path and layer AI around it for accuracy and reliability.

- Hybrid parsing: keep current boundary/template extraction as the fast path, then call AI only when a template misses, extracted values are incomplete, or confidence is below threshold
- Template generation: use AI on captured notifications to suggest new `ScannerTemplate` boundaries, package allowlist additions, and likely default categories, but require explicit user approval before saving
- Merchant normalization: map noisy strings like card descriptors, reference codes, or `POS/UPI/ACH` text into canonical merchant names and feed those back into `AssociatedTitles`
- Confidence-based UX: have AI return structured fields plus confidence and rationale; auto-create only above a high threshold, otherwise open `AddTransactionPage` prefilled with a review banner
- Duplicate suppression: use package name, normalized merchant, amount, timestamp window, and AI classification to avoid double-creating a transaction when the same bank emits multiple notifications for one event
- Transaction-type classification: infer debit vs credit vs refund vs transfer vs fee so the app can avoid treating every financial notification as a simple expense
- Wallet inference: learn package-specific and phrase-specific wallet/account mappings so one bank app can map to the right Cashew wallet without relying only on the template default
- User correction learning: when the user edits AI- or template-generated drafts, store the accepted merchant/category/title patterns locally and reuse them as retrieval context for future notifications
- Source-specific prompting: keep separate few-shot examples or heuristics by package name because the text structure for one bank/payment app is usually stable within that package
- Span extraction for auditability: require AI to return not just values, but the exact text spans it used for amount, merchant, and date so the UI can highlight why a draft was produced
- Reliability guardrails: persist raw notification payload, parse status, confidence, and failure reason so notifications can be replayed after model bugs, template edits, or provider outages
- Privacy/cost controls: keep AI optional for notifications, default to local/template parsing, and avoid sending every notification upstream unless the user explicitly enables AI parsing

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
