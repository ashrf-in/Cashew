# Notification Transactions

Experimental Android-only feature that listens to system notifications from other apps (banks, payment apps, etc.) and automatically creates expense transactions by parsing notification text using user-defined templates.

## Architecture

```
Android NotificationListenerService (notification_listener_service ^0.3.3)
    ↓
InitializeNotificationService widget (main.dart:152)
    ↓ on each notification
onNotification() → getNotificationMessage() → queueTransactionFromMessage()
    ↓
Match against ScannerTemplates in SQLite DB
    ↓
Extract title + amount using string boundary parsing
    ↓
Auto-categorize → Show AddTransactionPage (or silently create)
```

## Key Files

| File | Role |
|------|------|
| `lib/pages/autoTransactionsPageEmail.dart` | All notification logic: init, listener, parsing, UI |
| `lib/pages/addEmailTemplate.dart` | Template editor UI |
| `lib/database/tables.dart:488` | `ScannerTemplates` DB table schema |
| `android/app/src/main/AndroidManifest.xml:87` | `BIND_NOTIFICATION_LISTENER_SERVICE` declaration |
| `lib/struct/defaultPreferences.dart:128` | Feature flags |

## Flow

### 1. Initialization (`initNotificationScanning()`)
- Returns early on non-Android platforms
- Checks `appStateSettings["notificationScanning"] == true`
- Requests `BIND_NOTIFICATION_LISTENER_SERVICE` permission from user
- Subscribes to `NotificationListenerService.notificationsStream`
- Called on app startup via `InitializeNotificationService` widget

### 2. Notification Capture (`onNotification()`)
- Formats `ServiceNotificationEvent` into a plain string: package name + title + content
- Stores last 50 in `recentCapturedNotifications[]` (in-memory, for template debugging)
- Passes to `queueTransactionFromMessage()`

> **Bug:** `recentCapturedNotifications.take(50)` returns an iterable without mutating the list — the list grows unbounded.

### 3. Template Matching (`queueTransactionFromMessage()`)
- Fetches all `ScannerTemplate` rows from DB
- Checks if notification string contains template's `contains` keyword (first match wins)
- On no match: returns `false` silently

### 4. Parsing Logic

```dart
// Title: extract text between two boundary strings
startIndex = message.indexOf(titleBefore) + titleBefore.length
endIndex   = message.indexOf(titleAfter, startIndex)
title      = message.substring(startIndex, endIndex)
             .replaceAll("\n", "")
             .toLowerCase()
             .capitalizeFirst

// Amount: same boundary approach, then strip non-numeric chars
amountDouble = double.parse(amountString.replaceAll(RegExp('[^0-9.]'), ''))
```

Parse errors are silently swallowed (empty catch blocks). If extraction returns `null`, the notification is ignored.

### 5. Auto-Categorization
1. Looks up `AssociatedTitles` for the extracted title (most recent match)
2. Falls back to template's `defaultCategoryFk`

### 6. Transaction Creation
- `willPushRoute = true` (default): opens `AddTransactionPage` pre-filled for user confirmation
- `willPushRoute = false`: silently calls `processAddTransactionFromParams()` in background

Transactions are tagged with `MethodAdded.email` (no dedicated `notification` value exists in the enum).

## ScannerTemplate Schema

Defined in `lib/database/tables.dart:488`.

| Column | Purpose |
|--------|---------|
| `templateName` | Display name |
| `contains` | Keyword that must appear in notification text to trigger this template |
| `titleTransactionBefore` | String immediately before the merchant/title text |
| `titleTransactionAfter` | String immediately after the merchant/title text |
| `amountTransactionBefore` | String immediately before the amount |
| `amountTransactionAfter` | String immediately after the amount |
| `defaultCategoryFk` | Fallback category if no title history match found |
| `walletFk` | Account to assign the transaction to (`"-1"` = none) |
| `ignore` | Skip this template entirely |

## Settings

| Key | Default | Purpose |
|-----|---------|---------|
| `notificationScanning` | `false` | Master on/off toggle |
| `notificationScanningDebug` | `false` | Debug mode (unused in production) |

## Android Setup

`AndroidManifest.xml` declares the service and permission:

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

The service is provided entirely by the `notification_listener_service: ^0.3.3` Flutter package — no custom Kotlin/Java code exists for this feature.

## Known Issues

| Issue | Detail |
|-------|--------|
| `take(50)` bug | `List.take()` returns an iterable, does not mutate the list — `recentCapturedNotifications` grows unbounded |
| Silent parse failures | Empty catch blocks mean malformed notifications produce no feedback |
| Wrong `MethodAdded` tag | Notification-sourced transactions are tagged `MethodAdded.email` instead of a dedicated value |
| No deduplication | Same notification firing multiple times creates duplicate transactions |
| No notification filtering | Listens to every installed app; filtered only when template matching fails |
| In-memory capture list | `recentCapturedNotifications` is lost on app restart |
