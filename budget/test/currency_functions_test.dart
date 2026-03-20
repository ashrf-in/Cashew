import 'package:budget/struct/currencyFunctions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> previousCurrenciesJson;

  setUp(() {
    previousCurrenciesJson = Map<String, dynamic>.from(currenciesJSON);
    currenciesJSON = {
      'aed': {
        'Currency': 'Dirham',
        'Code': 'AED',
        'Symbol': '',
        'CountryName': 'United Arab Emirates',
        'CountryCode': 'AE',
      },
      'usdc': {
        'Currency': 'USDC',
        'Code': 'usdc',
        'NotKnown': true,
      },
    };
  });

  tearDown(() {
    currenciesJSON = previousCurrenciesJson;
  });

  test('AED is treated as a code-only currency', () {
    expect(getCurrencyCode('aed'), 'AED');
    expect(getCurrencySymbol('aed'), '');
  });

  test('USDC remains a code-only currency', () {
    expect(getCurrencyCode('usdc'), 'USDC');
    expect(getCurrencySymbol('usdc'), '');
  });
}