# Notification Transactions

Android-only feature that listens to posted notifications from allowlisted financial apps and converts them into transaction drafts or saved transactions. The current implementation supports deterministic template parsing, AI-assisted template creation, confidence-based auto-create, local learning, duplicate suppression, and confirmation notifications that deep-link back into the saved transaction.

## Architecture

```
Android NotificationListenerService (notification_listener_service ^0.3.3)
    ↓
InitializeNotificationService widget (main.dart)
    ↓ on posted notifications only
onNotification()
    ↓
Allowlist filter + fingerprint dedupe + capture buffer
    ↓
queueTransactionFromMessage()
    ↓
_buildNotificationDraft()
    ├─ existing ScannerTemplate match
    └─ AI template generation fallback (if Intelligence is configured)
    ↓
title/category/wallet learning + direction inference + confidence scoring
    ↓
Capture mode decision
    ├─ Review → open AddTransactionPage
    ├─ Smart → auto-create only when confidence is high enough
    └─ Instant → auto-create whenever the draft is complete
    ↓
createOrUpdateTransaction(... MethodAdded.notification)
    ↓
learnAcceptedNotificationDraft() + showNotificationTransactionSavedNotification()
```

## Key Files

| File | Role |
|------|------|
| `lib/pages/autoTransactionsPageEmail.dart` | Listener setup, package filtering, template matching, AI fallback, draft building, settings UI |
| `lib/struct/notificationCapture.dart` | Capture modes, direction inference, confidence scoring, dedupe fingerprint normalization |
| `lib/struct/notificationLearning.dart` | Learns accepted titles, categories, subcategories, and wallet mappings per package |
| `lib/struct/intelligence.dart` | `NotificationTemplateAnalysis` and AI notification-template generation |
| `lib/struct/notificationsGlobal.dart` | Confirmation notification with transaction deep link |
| `lib/database/tables.dart` | `ScannerTemplates`, `Transactions`, and `MethodAdded.notification` persistence |
| `lib/struct/defaultPreferences.dart` | Notification feature defaults and capture mode default |
| `android/app/src/main/AndroidManifest.xml` | Notification-listener service declaration |
| `android/notification-simulator/` | Separate Android app that posts bank-style test notifications |
| `test/notification_capture_test.dart` | Focused tests for direction inference, confidence, and capture-mode behavior |

## Flow

### 1. Initialization (`initNotificationScanning()`)
- Returns early on non-Android platforms.
- Requires `appStateSettings["notificationScanning"] == true`.
- Checks or requests Android notification-listener access.
- Cancels any previous listener subscription before attaching a new one.
- Subscribes to `NotificationListenerService.notificationsStream`.

### 2. Notification Capture (`onNotification()`)
- Ignores removal events (`event.hasRemoved == true`).
- Only processes notifications from the built-in allowlist or `notificationCustomPackages`.
- Builds a normalized fingerprint from package, title, and content and suppresses duplicates inside a 12-second window.
- Stores the most recent 50 captured notification payloads in `recentCapturedNotifications` for debugging and template authoring.
- Converts the event to a normalized message string with package name, title, and content before queueing it.

### 3. Draft Building (`queueTransactionFromMessage()` / `_buildNotificationDraft()`)
- Reads scanner templates from cache, refreshing when needed.
- Uses the first matching `ScannerTemplate.contains` rule as the fast path.
- If no template matches and AI learning is allowed, `analyzeNotificationMessage()` attempts to generate a reusable template.
- AI-generated boundaries are validated by reparsing the original notification text before the template is persisted.
- If the title or amount still cannot be extracted, the pipeline returns `false` and does not create a transaction.

### 4. Learning and Resolution
- `notificationTransactionLearning` can canonicalize a raw title and restore previously accepted category, subcategory, and wallet values for the same package and phrase.
- `AssociatedTitles` are used as the next fallback for category resolution.
- If no learned or associated category exists, the template's default category is used, and then a fallback category is picked based on inferred income/expense direction.
- Wallet resolution prefers learned wallet mappings, then template wallet, then the currently selected wallet.
- Direction is inferred from category polarity first, then notification keywords, then the parsed amount sign.
- Confidence is scored from template match quality, parsed fields, resolved category/wallet, learned values, and fallback usage.

### 5. Capture Modes
- `Review`: always opens `AddTransactionPage` with the parsed draft.
- `Smart`: auto-creates only when the draft has title, amount, category, and confidence >= 80.
- `Instant`: auto-creates whenever the draft is complete, regardless of confidence.

### 6. Transaction Creation
- Auto-created transactions are inserted with `paid: true`, `skipPaid: false`, and `methodAdded: MethodAdded.notification`.
- Stored amount sign is normalized from the inferred direction before insert.
- Accepted titles are added back into `AssociatedTitles`.
- Accepted drafts are learned so future notifications from the same package can reuse the approved title/category/wallet choices.
- A local confirmation notification is shown after save with payload `openTransaction?transactionPk=...`.

## ScannerTemplate Schema

Defined in `lib/database/tables.dart`.

| Column | Purpose |
|--------|---------|
| `templateName` | Display name |
| `contains` | Keyword that must appear in the notification text to trigger this template |
| `titleTransactionBefore` | Exact text immediately before the merchant/title |
| `titleTransactionAfter` | Exact text immediately after the merchant/title |
| `amountTransactionBefore` | Exact text immediately before the amount |
| `amountTransactionAfter` | Exact text immediately after the amount |
| `defaultCategoryFk` | Fallback main category if no learned or associated title match exists |
| `walletFk` | Account to assign by default (`"-1"` = no fixed wallet) |
| `ignore` | Skip this template entirely |

## Settings

| Key | Default | Purpose |
|-----|---------|---------|
| `notificationScanning` | `false` | Master on/off toggle |
| `notificationCaptureMode` | `smart` | Review, Smart, or Instant auto-capture behavior |
| `notificationCustomPackages` | `[]` | Extra package names to treat as financial notification sources |
| `notificationScanningDebug` | `true` | Debug-only setting surfaced from the debug page |

## Android Setup

`AndroidManifest.xml` declares the notification-listener service:

```xml
<service
  android:label="notifications"
  android:name="notification.listener.service.NotificationListener"
  android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
  android:exported="true">
  <intent-filter>
    <action android:name="android.service.notification.NotificationListenerService" />
  </intent-filter>
</service>
```

The service comes from `notification_listener_service: ^0.3.3`; Cashew does not provide custom Android listener code for this feature.

## Notification Simulator

The repo includes a separate Android test app at `budget/android/notification-simulator/` with package `com.cashew.notificationsimulator`.

- Cashew already allowlists this package in `_knownFinancialPackages`.
- The simulator posts notifications from a separate installed app, which exercises the real Android listener path instead of an in-app shortcut.
- Built-in presets currently cover card purchase, UPI debit, salary credit, ATM withdrawal, refund, and fee scenarios.
- The simulator can append a unique reference to avoid dedupe suppression during repeated testing.

Build and install it from `budget/android`:

```bash
./gradlew :notification-simulator:installDebug
```

Basic test flow:

1. Install Cashew and enable notification scanning.
2. Install the notification simulator app.
3. Open the simulator, choose a preset, and post a notification.
4. Verify Cashew captures, reviews, or auto-creates the transaction according to the configured capture mode.

## Test Coverage

`test/notification_capture_test.dart` covers:

- direction inference for common incoming and outgoing phrases
- confidence-score behavior
- smart vs instant capture-mode thresholds
- amount sign normalization

## Known Limitations

| Limitation | Detail |
|------------|--------|
| In-memory capture history | `recentCapturedNotifications` and the recent dedupe fingerprint cache are reset on app restart |
| First-match template precedence | Overlapping templates are resolved by first match, so a broad template can shadow a more specific one |
| No persisted review queue | Unmatched or low-confidence notifications are not stored in a replayable inbox yet |
| AI fallback is optional | Automatic template generation only runs when Intelligence is configured with a provider, API key, and model |
| Plugin lifecycle noise | `notification_listener_service` can emit detached `FlutterJNI` warnings when the engine is not attached; observed as non-fatal during emulator testing |
