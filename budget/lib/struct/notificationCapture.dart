const String notificationCaptureModeSettingKey = "notificationCaptureMode";
const String notificationCaptureModeSmart = "smart";
const String notificationCaptureModeReview = "review";
const String notificationCaptureModeInstant = "instant";

const List<String> notificationCaptureModes = <String>[
  notificationCaptureModeSmart,
  notificationCaptureModeReview,
  notificationCaptureModeInstant,
];

const int notificationAutoCreateConfidenceThreshold = 80;

enum NotificationTransactionDirection {
  income,
  expense,
}

String getNotificationCaptureModeLabel(String mode) {
  switch (mode) {
    case notificationCaptureModeReview:
      return "Review";
    case notificationCaptureModeInstant:
      return "Instant";
    case notificationCaptureModeSmart:
    default:
      return "Smart";
  }
}

String getNotificationCaptureModeDescription(String mode) {
  switch (mode) {
    case notificationCaptureModeReview:
      return "Always review AI-parsed notifications before saving them.";
    case notificationCaptureModeInstant:
      return "Save complete AI-parsed notifications instantly.";
    case notificationCaptureModeSmart:
    default:
      return "Save high-confidence AI-parsed notifications instantly and surface weaker matches for review.";
  }
}

String normalizeNotificationFingerprint(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

NotificationTransactionDirection inferNotificationTransactionDirection({
  required String message,
  bool? categoryIncome,
  double? parsedAmount,
}) {
  if (categoryIncome != null) {
    return categoryIncome
        ? NotificationTransactionDirection.income
        : NotificationTransactionDirection.expense;
  }

  final String normalizedMessage = normalizeNotificationFingerprint(message);
  const List<String> incomingKeywords = <String>[
    "credited",
    "credit alert",
    "received",
    "refund",
    "cashback",
    "deposited",
    "deposit",
    "salary",
    "reversed",
    "returned",
  ];
  const List<String> outgoingKeywords = <String>[
    "debited",
    "debit alert",
    "spent",
    "purchase",
    "paid",
    "sent",
    "withdrawn",
    "withdrawal",
    "charged",
    "bill payment",
  ];

  final bool mentionsIncoming =
      incomingKeywords.any(normalizedMessage.contains);
  final bool mentionsOutgoing =
      outgoingKeywords.any(normalizedMessage.contains);

  if (mentionsIncoming && !mentionsOutgoing) {
    return NotificationTransactionDirection.income;
  }
  if (mentionsOutgoing && !mentionsIncoming) {
    return NotificationTransactionDirection.expense;
  }
  if (parsedAmount != null && parsedAmount.isNegative) {
    return NotificationTransactionDirection.expense;
  }

  return NotificationTransactionDirection.expense;
}

int scoreNotificationConfidence({
  required bool hasTemplate,
  required bool hasParsedTitle,
  required bool hasParsedAmount,
  required bool hasResolvedCategory,
  required bool hasResolvedWallet,
  required bool hasLearnedValues,
  required bool hasAssociatedTitle,
  required bool usedFallbackCategory,
}) {
  int confidence = 0;
  if (hasTemplate) confidence += 30;
  if (hasParsedTitle) confidence += 25;
  if (hasParsedAmount) confidence += 20;
  if (hasResolvedCategory) confidence += 10;
  if (hasResolvedWallet) confidence += 5;
  if (hasLearnedValues) confidence += 8;
  if (hasAssociatedTitle) confidence += 5;
  if (usedFallbackCategory) confidence -= 5;
  return confidence.clamp(0, 100);
}

bool shouldAutoCreateNotification({
  required String captureMode,
  required int confidence,
  required bool hasAmount,
  required bool hasTitle,
  required bool hasCategory,
}) {
  if (!hasAmount || !hasTitle || !hasCategory) return false;

  if (captureMode == notificationCaptureModeReview) {
    return false;
  }
  if (captureMode == notificationCaptureModeInstant) {
    return true;
  }

  return confidence >= notificationAutoCreateConfidenceThreshold;
}

double applyNotificationDirectionToAmount({
  required double amount,
  required NotificationTransactionDirection direction,
}) {
  return direction == NotificationTransactionDirection.income
      ? amount.abs()
      : -amount.abs();
}