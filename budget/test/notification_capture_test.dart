import 'package:budget/struct/notificationCapture.dart';
import 'package:budget/struct/notificationLearning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('inferNotificationTransactionDirection', () {
    test('detects credited notifications as income', () {
      final NotificationTransactionDirection direction =
          inferNotificationTransactionDirection(
        message: 'Your account was credited with AED 250.00 from payroll',
      );

      expect(direction, NotificationTransactionDirection.income);
    });

    test('prefers category polarity when available', () {
      final NotificationTransactionDirection direction =
          inferNotificationTransactionDirection(
        message: 'Refund received for your last card transaction',
        categoryIncome: false,
      );

      expect(direction, NotificationTransactionDirection.expense);
    });
  });

  group('scoreNotificationConfidence', () {
    test('scores high confidence for complete learned drafts', () {
      final int confidence = scoreNotificationConfidence(
        hasTemplate: true,
        hasParsedTitle: true,
        hasParsedAmount: true,
        hasResolvedCategory: true,
        hasResolvedWallet: true,
        hasLearnedValues: true,
        hasAssociatedTitle: true,
        usedFallbackCategory: false,
      );

      expect(confidence, greaterThanOrEqualTo(95));
    });

    test('penalizes fallback-only drafts', () {
      final int confidence = scoreNotificationConfidence(
        hasTemplate: true,
        hasParsedTitle: true,
        hasParsedAmount: true,
        hasResolvedCategory: true,
        hasResolvedWallet: false,
        hasLearnedValues: false,
        hasAssociatedTitle: false,
        usedFallbackCategory: true,
      );

      expect(confidence, lessThan(90));
    });
  });

  group('shouldAutoCreateNotification', () {
    test('smart mode requires strong confidence', () {
      expect(
        shouldAutoCreateNotification(
          captureMode: notificationCaptureModeSmart,
          confidence: 79,
          hasAmount: true,
          hasTitle: true,
          hasCategory: true,
        ),
        isFalse,
      );

      expect(
        shouldAutoCreateNotification(
          captureMode: notificationCaptureModeSmart,
          confidence: 80,
          hasAmount: true,
          hasTitle: true,
          hasCategory: true,
        ),
        isTrue,
      );
    });

    test('instant mode only requires a complete draft', () {
      expect(
        shouldAutoCreateNotification(
          captureMode: notificationCaptureModeInstant,
          confidence: 10,
          hasAmount: true,
          hasTitle: true,
          hasCategory: true,
        ),
        isTrue,
      );
    });
  });

  test('applyNotificationDirectionToAmount signs the stored value', () {
    expect(
      applyNotificationDirectionToAmount(
        amount: 42.5,
        direction: NotificationTransactionDirection.expense,
      ),
      -42.5,
    );
    expect(
      applyNotificationDirectionToAmount(
        amount: 42.5,
        direction: NotificationTransactionDirection.income,
      ),
      42.5,
    );
  });

  test('extractNotificationPackageName reads the captured package field', () {
    expect(
      extractNotificationPackageName(
        'Package name: com.example.bank\nNotification removed: false\n\n----\n\nNotification Title: Paid\n\nNotification Content: Coffee shop',
      ),
      'com.example.bank',
    );
  });
}