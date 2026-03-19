import 'package:budget/struct/settings.dart';

const String notificationTransactionLearningSettingKey =
    "notificationTransactionLearning";
const int _maxNotificationPhraseRules = 250;
const int _maxNotificationPackageWalletRules = 80;

class NotificationLearningSuggestion {
  const NotificationLearningSuggestion({
    this.canonicalTitle,
    this.categoryPk,
    this.subCategoryPk,
    this.walletPk,
    this.packageWalletPk,
  });

  final String? canonicalTitle;
  final String? categoryPk;
  final String? subCategoryPk;
  final String? walletPk;
  final String? packageWalletPk;

  bool get hasLearnedValues =>
      (canonicalTitle?.trim().isNotEmpty == true) ||
      (categoryPk?.trim().isNotEmpty == true) ||
      (subCategoryPk?.trim().isNotEmpty == true) ||
      (walletPk?.trim().isNotEmpty == true) ||
      (packageWalletPk?.trim().isNotEmpty == true);
}

String? extractNotificationPackageName(String messageString) {
  final RegExpMatch? match = RegExp(
    r'^Package name:\s*(.+)$',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(messageString);
  return match?.group(1)?.trim();
}

String normalizeNotificationLearningPhrase(String value) {
  String normalized = value.toLowerCase().trim();
  normalized = normalized.replaceAll(RegExp(r'[\n\r\t]+'), ' ');
  normalized = normalized.replaceAll(RegExp(r'[/_|:#*]+'), ' ');
  normalized = normalized.replaceAll(
    RegExp(
      r'\b(?:ref|reference|txn|txnid|utr|rrn|upi|imps|neft|ach|pos|purchase|payment|paid|received|transfer|debited|credited|card|acct|account|merchant|bank|via|ending|success|successful|info)\b',
    ),
    ' ',
  );
  normalized = normalized.replaceAll(RegExp(r'\b[x*]{2,}\d{2,}\b'), ' ');
  normalized = normalized.replaceAll(RegExp(r'\b\d{4,}\b'), ' ');
  normalized = normalized.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

  if (normalized.isEmpty) {
    normalized = value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  return normalized;
}

NotificationLearningSuggestion getNotificationLearningSuggestion({
  required String? packageName,
  required String rawTitle,
}) {
  final String normalizedPackageName = (packageName ?? '').trim();
  if (normalizedPackageName.isEmpty || rawTitle.trim().isEmpty) {
    return const NotificationLearningSuggestion();
  }

  final Map<String, dynamic> learning = _getNotificationLearning();
  final String phraseKey = normalizeNotificationLearningPhrase(rawTitle);
  if (phraseKey.isEmpty) return const NotificationLearningSuggestion();

  final List<Map<String, dynamic>> phraseRules =
      _getMapList(learning["phraseRules"]);
  final Map<String, dynamic>? phraseRule = phraseRules.firstWhere(
    (rule) =>
        _asString(rule["packageName"]) == normalizedPackageName &&
        _asString(rule["phraseKey"]) == phraseKey,
    orElse: () => <String, dynamic>{},
  );

  final List<Map<String, dynamic>> packageWallets =
      _getMapList(learning["packageWallets"]);
  final Map<String, dynamic>? packageWalletRule = packageWallets.firstWhere(
    (rule) => _asString(rule["packageName"]) == normalizedPackageName,
    orElse: () => <String, dynamic>{},
  );

  return NotificationLearningSuggestion(
    canonicalTitle: _nullIfEmpty(phraseRule?["canonicalTitle"]),
    categoryPk: _nullIfEmpty(phraseRule?["categoryPk"]),
    subCategoryPk: _nullIfEmpty(phraseRule?["subCategoryPk"]),
    walletPk: _nullIfEmpty(phraseRule?["walletPk"]),
    packageWalletPk: _nullIfEmpty(packageWalletRule?["walletPk"]),
  );
}

Future<void> learnAcceptedNotificationDraft({
  required String? packageName,
  required String rawTitle,
  required String finalTitle,
  required String? categoryPk,
  required String? subCategoryPk,
  required String? walletPk,
}) async {
  final String normalizedPackageName = (packageName ?? '').trim();
  final String phraseKey = normalizeNotificationLearningPhrase(rawTitle);
  if (normalizedPackageName.isEmpty || phraseKey.isEmpty) return;

  final Map<String, dynamic> learning = _getNotificationLearning();
  final List<Map<String, dynamic>> phraseRules =
      _getMapList(learning["phraseRules"]);
  final List<Map<String, dynamic>> packageWallets =
      _getMapList(learning["packageWallets"]);
  final String updatedAt = DateTime.now().toIso8601String();

  final int existingPhraseRuleIndex = phraseRules.indexWhere(
    (rule) =>
        _asString(rule["packageName"]) == normalizedPackageName &&
        _asString(rule["phraseKey"]) == phraseKey,
  );

  final Map<String, dynamic> phraseRule = {
    "packageName": normalizedPackageName,
    "phraseKey": phraseKey,
    "rawTitle": rawTitle.trim(),
    "canonicalTitle": finalTitle.trim(),
    "categoryPk": _nullIfEmpty(categoryPk),
    "subCategoryPk": _nullIfEmpty(subCategoryPk),
    "walletPk": _nullIfEmpty(walletPk),
    "updatedAt": updatedAt,
    "hitCount": ((existingPhraseRuleIndex >= 0
                    ? phraseRules[existingPhraseRuleIndex]["hitCount"]
                    : 0) ??
                0) +
            1,
  };

  if (existingPhraseRuleIndex >= 0) {
    phraseRules.removeAt(existingPhraseRuleIndex);
  }
  phraseRules.insert(0, phraseRule);

  if (_nullIfEmpty(walletPk) != null) {
    final int existingPackageWalletIndex = packageWallets.indexWhere(
      (rule) => _asString(rule["packageName"]) == normalizedPackageName,
    );
    final Map<String, dynamic> packageWalletRule = {
      "packageName": normalizedPackageName,
      "walletPk": walletPk,
      "updatedAt": updatedAt,
      "hitCount": ((existingPackageWalletIndex >= 0
                      ? packageWallets[existingPackageWalletIndex]["hitCount"]
                      : 0) ??
                  0) +
              1,
    };

    if (existingPackageWalletIndex >= 0) {
      packageWallets.removeAt(existingPackageWalletIndex);
    }
    packageWallets.insert(0, packageWalletRule);
  }

  final Map<String, dynamic> updatedLearning = {
    "version": 1,
    "phraseRules": phraseRules.take(_maxNotificationPhraseRules).toList(),
    "packageWallets":
        packageWallets.take(_maxNotificationPackageWalletRules).toList(),
  };

  await updateSettings(
    notificationTransactionLearningSettingKey,
    updatedLearning,
    updateGlobalState: false,
  );
}

Map<String, dynamic> _getNotificationLearning() {
  final dynamic rawLearning =
      appStateSettings[notificationTransactionLearningSettingKey];
  if (rawLearning is Map<String, dynamic>) {
    return {
      "version": rawLearning["version"] ?? 1,
      "phraseRules": _getMapList(rawLearning["phraseRules"]),
      "packageWallets": _getMapList(rawLearning["packageWallets"]),
    };
  }
  if (rawLearning is Map) {
    return {
      "version": rawLearning["version"] ?? 1,
      "phraseRules": _getMapList(rawLearning["phraseRules"]),
      "packageWallets": _getMapList(rawLearning["packageWallets"]),
    };
  }
  return {
    "version": 1,
    "phraseRules": <Map<String, dynamic>>[],
    "packageWallets": <Map<String, dynamic>>[],
  };
}

List<Map<String, dynamic>> _getMapList(dynamic value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value.whereType<Map>().map((entry) {
    return Map<String, dynamic>.from(entry.map((key, value) {
      return MapEntry(key.toString(), value);
    }));
  }).toList();
}

String _asString(dynamic value) {
  return value?.toString().trim() ?? '';
}

String? _nullIfEmpty(dynamic value) {
  final String stringValue = _asString(value);
  if (stringValue.isEmpty) return null;
  return stringValue;
}