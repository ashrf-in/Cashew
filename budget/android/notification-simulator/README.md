# Notification Simulator

Android-only helper app for testing Cashew's notification capture pipeline.

## What It Does

- Installs as a separate app with package `com.cashew.notificationsimulator`
- Posts bank-style notifications with editable title and body fields
- Includes several realistic presets for debit, credit, refund, fee, and ATM scenarios
- Can append a unique reference so Cashew does not ignore repeat sends during deduplication

Cashew already allowlists this package in `lib/pages/autoTransactionsPageEmail.dart`, so once both apps are installed you can test immediately.

## Build

From `budget/android`:

```bash
./gradlew :notification-simulator:assembleDebug
./gradlew :notification-simulator:installDebug
```

## Test Flow

1. In Cashew, enable notification scanning and grant notification-listener access.
2. Open Notification Simulator.
3. Pick a preset or edit the title and body manually.
4. Tap `Post Notification`.
5. Check Cashew for the captured draft or auto-created transaction.