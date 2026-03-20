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
      'usd': {
        'Currency': 'Dollar',
        'Code': 'USD',
        'Symbol': r'$',
        'CountryName': 'United States',
        'CountryCode': 'US',
      },
      'cad': {
        'Currency': 'Dollar',
        'Code': 'CAD',
        'Symbol': r'$',
        'CountryName': 'Canada',
        'CountryCode': 'CA',
      },
      'eur': {
        'Currency': 'Euro',
        'Code': 'EUR',
        'Symbol': '€',
        'CountryName': 'Eurozone',
        'CountryCode': 'EU',
      },
      'inr': {
        'Currency': 'Indian Rupee',
        'Code': 'INR',
        'Symbol': '₹',
        'CountryName': 'India',
        'CountryCode': 'IN',
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

  test('normalizes currency keys from codes and disambiguated tokens', () {
    expect(normalizeCurrencyKey('AED'), 'aed');
    expect(normalizeCurrencyKey('usd'), 'usd');
    expect(normalizeCurrencyKey(r'C$'), 'cad');
  });

  test('extracts explicit currency codes and unique symbols from text', () {
    expect(
      extractCurrencyKeyFromText('Your account was credited with AED 250.00'),
      'aed',
    );
    expect(
      extractCurrencyKeyFromText('Paid ₹1,250.00 at the grocery store'),
      'inr',
    );
    expect(
      extractCurrencyKeyFromText('Card purchase of 24.99 EUR completed'),
      'eur',
    );
  });

  test('uses preferred currencies to resolve ambiguous symbols', () {
    expect(extractCurrencyKeyFromText(r'Spent $24.99 on your card'), isNull);
    expect(
      extractCurrencyKeyFromText(
        r'Spent $24.99 on your card',
        preferredCurrencyKeys: <String>['usd'],
      ),
      'usd',
    );
  });
}