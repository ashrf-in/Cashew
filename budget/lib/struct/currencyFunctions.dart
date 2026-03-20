import 'package:budget/struct/settings.dart';
import 'dart:convert';
import 'package:budget/database/tables.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

Map<String, dynamic> currenciesJSON = {};

loadCurrencyJSON() async {
  currenciesJSON = await json.decode(
      await rootBundle.loadString('assets/static/generated/currencies.json'));
}

Future<bool> getExchangeRates() async {
  print("Getting exchange rates for current wallets");
  // List<String?> uniqueCurrencies =
  //     await database.getUniqueCurrenciesFromWallets();
  Map<dynamic, dynamic> cachedCurrencyExchange =
      appStateSettings["cachedCurrencyExchange"];
  try {
    Uri url = Uri.parse(
        "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json");
    dynamic response = await http.get(url);
    if (response.statusCode == 200) {
      cachedCurrencyExchange = json.decode(response.body)?["usd"];
    }
  } catch (e) {
    print("Error getting currency rates: " + e.toString());
    return false;
  }
  // print(cachedCurrencyExchange);
  updateSettings(
    "cachedCurrencyExchange",
    cachedCurrencyExchange,
    updateGlobalState:
        appStateSettings["cachedCurrencyExchange"].keys.length <= 0,
  );
  return true;
}

double amountRatioToPrimaryCurrencyGivenPk(
  AllWallets allWallets,
  String walletPk, {
  Map<String, dynamic>? appStateSettingsPassed,
}) {
  if (allWallets.indexedByPk[walletPk] == null) return 1;
  return amountRatioToPrimaryCurrency(
    allWallets,
    allWallets.indexedByPk[walletPk]?.currency,
    appStateSettingsPassed: appStateSettingsPassed,
  );
}

double amountRatioToPrimaryCurrency(
  AllWallets allWallets,
  String? walletCurrency, {
  Map<String, dynamic>? appStateSettingsPassed,
}) {
  if (walletCurrency == null) {
    return 1;
  }
  if (allWallets
          .indexedByPk[
              (appStateSettingsPassed ?? appStateSettings)["selectedWalletPk"]]
          ?.currency ==
      walletCurrency) {
    return 1;
  }
  if (allWallets.indexedByPk[
          (appStateSettingsPassed ?? appStateSettings)["selectedWalletPk"]] ==
      null) {
    return 1;
  }

  double exchangeRateFromUSDToTarget = getCurrencyExchangeRate(
    allWallets
        .indexedByPk[
            (appStateSettingsPassed ?? appStateSettings)["selectedWalletPk"]]
        ?.currency,
    appStateSettingsPassed: appStateSettingsPassed,
  );
  double exchangeRateFromCurrentToUSD = 1 /
      getCurrencyExchangeRate(
        walletCurrency,
        appStateSettingsPassed: appStateSettingsPassed,
      );
  return exchangeRateFromUSDToTarget * exchangeRateFromCurrentToUSD;
}

double? amountRatioFromToCurrency(
    String walletCurrencyBefore, String walletCurrencyAfter) {
  double exchangeRateFromUSDToTarget =
      getCurrencyExchangeRate(walletCurrencyAfter);
  double exchangeRateFromCurrentToUSD =
      1 / getCurrencyExchangeRate(walletCurrencyBefore);
  return exchangeRateFromUSDToTarget * exchangeRateFromCurrentToUSD;
}

String getCurrencyCode(String? currencyKey) {
  if (currencyKey == null || currencyKey == "") return "";

  String normalizedCurrencyKey = currencyKey.toLowerCase();
  return (currenciesJSON[normalizedCurrencyKey]?["Code"] ??
      currenciesJSON[currencyKey]?["Code"] ??
      currencyKey)
    .toString()
    .toUpperCase();
}

String getCurrencySymbol(String? currencyKey) {
  if (currencyKey == null || currencyKey == "") return "";

  String normalizedCurrencyKey = currencyKey.toLowerCase();
  return (currenciesJSON[normalizedCurrencyKey]?["Symbol"] ??
      currenciesJSON[currencyKey]?["Symbol"] ??
      "")
    .toString();
}

const Map<String, String> _disambiguatedCurrencyTokenMap = <String, String>{
  'US\$': 'usd',
  'AU\$': 'aud',
  'A\$': 'aud',
  'CA\$': 'cad',
  'C\$': 'cad',
  'SG\$': 'sgd',
  'S\$': 'sgd',
  'HK\$': 'hkd',
  'NZ\$': 'nzd',
};

String _normalizeCurrencyLookupToken(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String? normalizeCurrencyKey(String? currencyValue) {
  final String rawValue = currencyValue?.trim() ?? '';
  if (rawValue.isEmpty) return null;

  final String uppercaseToken =
      rawValue.toUpperCase().replaceAll(RegExp(r'\s+'), '');
  final String? mappedToken = _disambiguatedCurrencyTokenMap[uppercaseToken];
  if (mappedToken != null) {
    return mappedToken;
  }

  final String normalizedToken = _normalizeCurrencyLookupToken(rawValue);
  if (normalizedToken.isEmpty) return null;

  for (final MapEntry<String, dynamic> entry in currenciesJSON.entries) {
    final dynamic value = entry.value;
    final String normalizedKey = _normalizeCurrencyLookupToken(entry.key);
    final String normalizedCode = value is Map
        ? _normalizeCurrencyLookupToken(value['Code']?.toString() ?? '')
        : '';
    if (normalizedToken == normalizedKey || normalizedToken == normalizedCode) {
      return entry.key.toLowerCase();
    }
  }

  return null;
}

String? extractCurrencyKeyFromText(
  String text, {
  Iterable<String>? preferredCurrencyKeys,
}) {
  final String trimmedText = text.trim();
  if (trimmedText.isEmpty) return null;

  final List<String> normalizedPreferredCurrencies = preferredCurrencyKeys
          ?.map(normalizeCurrencyKey)
          .whereType<String>()
          .toSet()
          .toList() ??
      <String>[];

  final List<RegExp> patterns = <RegExp>[
    RegExp(
      r'((?:US|AU|CA|SG|HK|NZ)\$|[$₹€£¥₩₦₨₱₫₽₴₺₲₵₭₮₡₸₼]|[A-Za-z]{3,5})\s*[+\-−]?\s*\d[\d,]*(?:\.\d+)?',
      caseSensitive: false,
    ),
    RegExp(
      r'[+\-−]?\s*\d[\d,]*(?:\.\d+)?\s*((?:US|AU|CA|SG|HK|NZ)\$|[A-Za-z]{3,5})\b',
      caseSensitive: false,
    ),
  ];

  for (final RegExp pattern in patterns) {
    for (final RegExpMatch match in pattern.allMatches(trimmedText)) {
      final String token = match.group(1)?.trim() ?? '';
      final String? currencyKey = _resolveCurrencyToken(
        token,
        preferredCurrencyKeys: normalizedPreferredCurrencies,
      );
      if (currencyKey != null) {
        return currencyKey;
      }
    }
  }

  return null;
}

String? _resolveCurrencyToken(
  String token, {
  required List<String> preferredCurrencyKeys,
}) {
  if (token.isEmpty) return null;

  final String uppercaseToken =
      token.toUpperCase().replaceAll(RegExp(r'\s+'), '');
  final String? mappedToken = _disambiguatedCurrencyTokenMap[uppercaseToken];
  if (mappedToken != null) {
    return mappedToken;
  }

  final String? normalizedCurrency = normalizeCurrencyKey(token);
  if (normalizedCurrency != null) {
    return normalizedCurrency;
  }

  final List<String> symbolMatches = _findCurrencyKeysForSymbol(token);
  if (symbolMatches.isEmpty) return null;
  if (symbolMatches.length == 1) return symbolMatches.first;

  final List<String> preferredMatches = symbolMatches
      .where((currencyKey) => preferredCurrencyKeys.contains(currencyKey))
      .toList();
  if (preferredMatches.length == 1) {
    return preferredMatches.first;
  }

  return null;
}

List<String> _findCurrencyKeysForSymbol(String symbolToken) {
  final List<String> matches = <String>[];
  final Set<String> seen = <String>{};

  for (final MapEntry<String, dynamic> entry in currenciesJSON.entries) {
    final dynamic value = entry.value;
    if (value is! Map) continue;
    final String symbol = value['Symbol']?.toString().trim() ?? '';
    if (symbol.isEmpty || symbol != symbolToken) continue;
    final String currencyKey = entry.key.toLowerCase();
    if (seen.add(currencyKey)) {
      matches.add(currencyKey);
    }
  }

  return matches;
}

// assume selected wallets currency
String getCurrencyString(AllWallets allWallets, {String? currencyKey}) {
  String? selectedWalletCurrency =
      allWallets.indexedByPk[appStateSettings["selectedWalletPk"]]?.currency;
  return currencyKey != null
    ? getCurrencySymbol(currencyKey)
      : selectedWalletCurrency == null
          ? ""
      : getCurrencySymbol(selectedWalletCurrency);
}

double getCurrencyExchangeRate(
  String? currencyKey, {
  Map<String, dynamic>? appStateSettingsPassed,
}) {
  if (currencyKey == null || currencyKey == "") return 1;
  if ((appStateSettingsPassed ?? appStateSettings)["customCurrencyAmounts"]
          ?[currencyKey] !=
      null) {
    return (appStateSettingsPassed ?? appStateSettings)["customCurrencyAmounts"]
            [currencyKey]
        .toDouble();
  } else if ((appStateSettingsPassed ??
          appStateSettings)["cachedCurrencyExchange"]?[currencyKey] !=
      null) {
    return (appStateSettingsPassed ??
            appStateSettings)["cachedCurrencyExchange"][currencyKey]
        .toDouble();
  } else {
    return 1;
  }
}

double budgetAmountToPrimaryCurrency(AllWallets allWallets, Budget budget) {
  return budget.amount *
      (amountRatioToPrimaryCurrencyGivenPk(allWallets, budget.walletFk));
}

double objectiveAmountToPrimaryCurrency(
    AllWallets allWallets, Objective objective) {
  return objective.amount *
      (amountRatioToPrimaryCurrencyGivenPk(allWallets, objective.walletFk));
}

double categoryBudgetLimitToPrimaryCurrency(
    AllWallets allWallets, CategoryBudgetLimit limit) {
  return limit.amount *
      (amountRatioToPrimaryCurrencyGivenPk(allWallets, limit.walletFk));
}

// Positive (input)
double getAmountRatioWalletTransferTo(AllWallets allWallets, String walletToPk,
    {String? enteredAmountWalletPk}) {
  return amountRatioFromToCurrency(
        allWallets
            .indexedByPk[
                enteredAmountWalletPk ?? appStateSettings["selectedWalletPk"]]!
            .currency!,
        allWallets.indexedByPk[walletToPk]!.currency!,
      ) ??
      1;
}

// Negative (output)
double getAmountRatioWalletTransferFrom(
    AllWallets allWallets, String walletFromPk,
    {String? enteredAmountWalletPk}) {
  return -1 *
      (amountRatioFromToCurrency(
            allWallets
                .indexedByPk[enteredAmountWalletPk ??
                    appStateSettings["selectedWalletPk"]]!
                .currency!,
            allWallets.indexedByPk[walletFromPk]!.currency!,
          ) ??
          1);
}
