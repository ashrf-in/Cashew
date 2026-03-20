import 'package:budget/database/tables.dart';
import 'package:drift/drift.dart' show Value;

const String walletAccountTypeBank = 'bank';
const String walletAccountTypeSavings = 'savings';
const String walletAccountTypeChecking = 'checking';
const String walletAccountTypeCash = 'cash';
const String walletAccountTypeCard = 'card';
const String walletAccountTypeCreditCard = 'credit-card';
const String walletAccountTypeDebitCard = 'debit-card';
const String walletAccountTypeDigitalWallet = 'digital-wallet';

const List<String> walletAccountTypes = <String>[
  walletAccountTypeBank,
  walletAccountTypeSavings,
  walletAccountTypeChecking,
  walletAccountTypeCash,
  walletAccountTypeCard,
  walletAccountTypeCreditCard,
  walletAccountTypeDebitCard,
  walletAccountTypeDigitalWallet,
];

class NotificationAccountIdentifier {
  const NotificationAccountIdentifier({
    required this.tag,
    required this.accountType,
    required this.matchedText,
  });

  final String tag;
  final String accountType;
  final String matchedText;
}

String sanitizeWalletAccountType(String? value) {
  final String normalized = value?.trim().toLowerCase() ?? '';
  if (walletAccountTypes.contains(normalized)) {
    return normalized;
  }
  return walletAccountTypeBank;
}

String getWalletAccountTypeLabel(String? value) {
  switch (sanitizeWalletAccountType(value)) {
    case walletAccountTypeSavings:
      return 'Savings';
    case walletAccountTypeChecking:
      return 'Checking';
    case walletAccountTypeCash:
      return 'Cash';
    case walletAccountTypeCard:
      return 'Card';
    case walletAccountTypeCreditCard:
      return 'Credit Card';
    case walletAccountTypeDebitCard:
      return 'Debit Card';
    case walletAccountTypeDigitalWallet:
      return 'Wallet';
    case walletAccountTypeBank:
    default:
      return 'Bank';
  }
}

String getWalletAutoCreatedNameSuffix(String? value) {
  switch (sanitizeWalletAccountType(value)) {
    case walletAccountTypeCash:
      return 'Cash';
    case walletAccountTypeCard:
    case walletAccountTypeCreditCard:
    case walletAccountTypeDebitCard:
      return 'Card';
    case walletAccountTypeDigitalWallet:
      return 'Wallet';
    case walletAccountTypeSavings:
    case walletAccountTypeChecking:
    case walletAccountTypeBank:
    default:
      return 'Bank Ac';
  }
}

String mergePreferredWalletAccountType(String? primary, String? secondary) {
  final String? normalizedPrimary = _nullableWalletAccountType(primary);
  final String? normalizedSecondary = _nullableWalletAccountType(secondary);
  if (normalizedPrimary == null) {
    return normalizedSecondary ?? walletAccountTypeBank;
  }
  if (normalizedPrimary == walletAccountTypeBank &&
      normalizedSecondary != null &&
      normalizedSecondary != walletAccountTypeBank) {
    return normalizedSecondary;
  }
  return normalizedPrimary;
}

String? _nullableWalletAccountType(String? value) {
  final String normalized = value?.trim().toLowerCase() ?? '';
  if (normalized.isEmpty) return null;
  if (walletAccountTypes.contains(normalized)) {
    return normalized;
  }
  return null;
}

String sanitizeWalletAccountTag(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) return '';

  final String digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.isNotEmpty) {
    if (digitsOnly.length > 6) {
      return digitsOnly.substring(digitsOnly.length - 6);
    }
    return digitsOnly;
  }

  return trimmed.replaceAll(RegExp(r'\s+'), ' ');
}

String normalizeWalletAccountTag(String value) {
  final String sanitized = sanitizeWalletAccountTag(value);
  if (sanitized.isEmpty) return '';
  if (RegExp(r'^\d+$').hasMatch(sanitized)) {
    return sanitized;
  }
  return sanitized.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

List<String> sanitizeWalletAccountTags(Iterable<String>? tags) {
  if (tags == null) return <String>[];

  final List<String> sanitized = <String>[];
  final Set<String> seen = <String>{};
  for (final String tag in tags) {
    final String cleaned = sanitizeWalletAccountTag(tag);
    final String normalized = normalizeWalletAccountTag(cleaned);
    if (cleaned.isEmpty || normalized.isEmpty || !seen.add(normalized)) {
      continue;
    }
    sanitized.add(cleaned);
  }
  return sanitized;
}

List<String> parseWalletAccountTagsInput(String? rawValue) {
  return sanitizeWalletAccountTags(
    (rawValue ?? '').split(RegExp(r'[,;\n]+')),
  );
}

String formatWalletAccountTagsInput(List<String>? tags) {
  return sanitizeWalletAccountTags(tags).join(', ');
}

String buildWalletMatchingContext(TransactionWallet wallet) {
  final List<String> details = <String>[];
  if (wallet.currency?.trim().isNotEmpty == true) {
    details.add(wallet.currency!.toUpperCase());
  }
  if (_nullableWalletAccountType(wallet.accountType) != null) {
    details.add('type: ${getWalletAccountTypeLabel(wallet.accountType)}');
  }
  final List<String> tags = sanitizeWalletAccountTags(wallet.accountTags);
  if (tags.isNotEmpty) {
    details.add('tags: ${tags.join(', ')}');
  }

  if (details.isEmpty) return wallet.name;
  return '${wallet.name} [${details.join(' | ')}]';
}

TransactionWallet mergeWalletMetadata(
  TransactionWallet target,
  TransactionWallet source,
) {
  return target.copyWith(
    accountType: Value(
      mergePreferredWalletAccountType(target.accountType, source.accountType),
    ),
    accountTags: Value(
      mergeWalletAccountTags(target.accountTags, source.accountTags),
    ),
  );
}

TransactionWallet mergeWalletMetadataWithIdentifier(
  TransactionWallet wallet,
  NotificationAccountIdentifier identifier,
) {
  return wallet.copyWith(
    accountType: Value(
      mergePreferredWalletAccountType(wallet.accountType, identifier.accountType),
    ),
    accountTags: Value(
      mergeWalletAccountTags(wallet.accountTags, <String>[identifier.tag]),
    ),
  );
}

List<String> mergeWalletAccountTags(
  Iterable<String>? primary,
  Iterable<String>? secondary,
) {
  return sanitizeWalletAccountTags(
    <String>[
      ...?primary,
      ...?secondary,
    ],
  );
}

String buildAutoCreatedWalletName(NotificationAccountIdentifier identifier) {
  return 'XX${identifier.tag} ${getWalletAutoCreatedNameSuffix(identifier.accountType)}'
      .trim();
}

TransactionWallet? matchWalletByAccountIdentifiers(
  List<NotificationAccountIdentifier> identifiers,
  List<TransactionWallet> wallets,
) {
  if (identifiers.isEmpty || wallets.isEmpty) return null;

  for (final NotificationAccountIdentifier identifier in identifiers) {
    final String normalizedTag = normalizeWalletAccountTag(identifier.tag);
    if (normalizedTag.isEmpty) continue;

    final List<TransactionWallet> matches = wallets.where((wallet) {
      final List<String> tags = sanitizeWalletAccountTags(wallet.accountTags);
      return tags.any(
        (tag) => normalizeWalletAccountTag(tag) == normalizedTag,
      );
    }).toList();

    if (matches.isEmpty) continue;
    if (matches.length == 1) return matches.first;

    final List<TransactionWallet> typedMatches = matches.where((wallet) {
      return sanitizeWalletAccountType(wallet.accountType) ==
          sanitizeWalletAccountType(identifier.accountType);
    }).toList();
    if (typedMatches.isNotEmpty) {
      return typedMatches.first;
    }
    return matches.first;
  }

  return null;
}

List<NotificationAccountIdentifier> extractNotificationAccountIdentifiers(
  String text,
) {
  if (text.trim().isEmpty) return <NotificationAccountIdentifier>[];

  final List<NotificationAccountIdentifier> identifiers =
      <NotificationAccountIdentifier>[];
  final Set<String> seen = <String>{};

  void addIdentifier(String digits, String contextText, String fallbackType) {
    final String tag = sanitizeWalletAccountTag(digits);
    if (tag.isEmpty) return;

    final String accountType = inferWalletAccountTypeFromText(
      contextText,
      fallbackType: fallbackType,
    );
    final String key = '$accountType:$tag';
    if (!seen.add(key)) return;

    identifiers.add(NotificationAccountIdentifier(
      tag: tag,
      accountType: accountType,
      matchedText: contextText.trim(),
    ));
  }

  final List<Map<String, dynamic>> patterns = <Map<String, dynamic>>[
    <String, dynamic>{
      'regex': RegExp(
        r'\b(?:credit\s*card|credit-card)\b[^\n]{0,48}?(?:ending(?:\s+in)?|ends?\s+with|last(?:\s+\w+){0,2}\s+digits?|xx|x{2,}|\*{2,}|•{2,}|·{2,}|#{2,})\D{0,8}(\d{2,18})',
        caseSensitive: false,
      ),
      'type': walletAccountTypeCreditCard,
    },
    <String, dynamic>{
      'regex': RegExp(
        r'\b(?:debit\s*card|debit-card)\b[^\n]{0,48}?(?:ending(?:\s+in)?|ends?\s+with|last(?:\s+\w+){0,2}\s+digits?|xx|x{2,}|\*{2,}|•{2,}|·{2,}|#{2,})\D{0,8}(\d{2,18})',
        caseSensitive: false,
      ),
      'type': walletAccountTypeDebitCard,
    },
    <String, dynamic>{
      'regex': RegExp(
        r'\b(?:card|visa|mastercard|master\s*card|amex|rupay)\b[^\n]{0,48}?(?:ending(?:\s+in)?|ends?\s+with|last(?:\s+\w+){0,2}\s+digits?|xx|x{2,}|\*{2,}|•{2,}|·{2,}|#{2,}|no\.?|number)?\D{0,8}(\d{2,18})',
        caseSensitive: false,
      ),
      'type': walletAccountTypeCard,
    },
    <String, dynamic>{
      'regex': RegExp(
        r'\b(?:wallet)\b[^\n]{0,48}?(?:ending(?:\s+in)?|ends?\s+with|last(?:\s+\w+){0,2}\s+digits?|xx|x{2,}|\*{2,}|•{2,}|·{2,}|#{2,}|no\.?|number)?\D{0,8}(\d{2,18})',
        caseSensitive: false,
      ),
      'type': walletAccountTypeDigitalWallet,
    },
    <String, dynamic>{
      'regex': RegExp(
        r'\b(?:savings|saving|checking|current|account|acct|a/c|bank\s*account|bank\s*a/c|acc(?:ount)?)\b[^\n]{0,48}?(?:ending(?:\s+in)?|ends?\s+with|last(?:\s+\w+){0,2}\s+digits?|xx|x{2,}|\*{2,}|•{2,}|·{2,}|#{2,}|no\.?|number)?\D{0,8}(\d{2,18})',
        caseSensitive: false,
      ),
      'type': walletAccountTypeBank,
    },
  ];

  for (final Map<String, dynamic> pattern in patterns) {
    final RegExp regex = pattern['regex'] as RegExp;
    final String fallbackType = pattern['type'] as String;
    for (final RegExpMatch match in regex.allMatches(text)) {
      final String? digits = match.group(1);
      if (digits == null || digits.trim().isEmpty) continue;
      addIdentifier(digits, match.group(0) ?? digits, fallbackType);
    }
  }

  final RegExp keywordRegex = RegExp(
    r'\b(?:card|wallet|account|acct|a/c|bank|savings|checking|current)\b',
    caseSensitive: false,
  );
  final RegExp maskedDigitsRegex = RegExp(
    r'(?:xx|x{2,}|\*{2,}|•{2,}|·{2,}|#{2,})\s*[-:]?\s*(\d{2,18})',
    caseSensitive: false,
  );
  final RegExp endingDigitsRegex = RegExp(
    r'(?:ending(?:\s+in)?|ends?\s+with|last(?:\s+\w+){0,2}\s+digits?)\D{0,8}(\d{2,18})',
    caseSensitive: false,
  );

  for (final String line in text.split('\n')) {
    if (!keywordRegex.hasMatch(line)) continue;

    for (final RegExpMatch match in maskedDigitsRegex.allMatches(line)) {
      final String? digits = match.group(1);
      if (digits == null || digits.trim().isEmpty) continue;
      addIdentifier(digits, line, walletAccountTypeBank);
    }

    for (final RegExpMatch match in endingDigitsRegex.allMatches(line)) {
      final String? digits = match.group(1);
      if (digits == null || digits.trim().isEmpty) continue;
      addIdentifier(digits, line, walletAccountTypeBank);
    }
  }

  return identifiers;
}

String inferWalletAccountTypeFromText(
  String text, {
  String fallbackType = walletAccountTypeBank,
}) {
  final String normalized = text.toLowerCase();
  if (normalized.contains('credit card') || normalized.contains('credit-card')) {
    return walletAccountTypeCreditCard;
  }
  if (normalized.contains('debit card') || normalized.contains('debit-card')) {
    return walletAccountTypeDebitCard;
  }
  if (normalized.contains('wallet') || normalized.contains('upi lite')) {
    return walletAccountTypeDigitalWallet;
  }
  if (normalized.contains('cash')) {
    return walletAccountTypeCash;
  }
  if (normalized.contains('checking') || normalized.contains('current account')) {
    return walletAccountTypeChecking;
  }
  if (normalized.contains('savings') || normalized.contains('saving account')) {
    return walletAccountTypeSavings;
  }
  if (normalized.contains('card') ||
      normalized.contains('visa') ||
      normalized.contains('mastercard') ||
      normalized.contains('master card') ||
      normalized.contains('amex') ||
      normalized.contains('rupay')) {
    return walletAccountTypeCard;
  }
  return sanitizeWalletAccountType(fallbackType);
}