import 'package:budget/database/tables.dart';
import 'package:budget/struct/walletAccountMatcher.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionWallet buildWallet({
  required String walletPk,
  required String name,
  String? accountType,
  List<String>? accountTags,
}) {
  return TransactionWallet(
    walletPk: walletPk,
    name: name,
    accountType: accountType,
    accountTags: accountTags,
    colour: null,
    iconName: null,
    dateCreated: DateTime(2024, 1, 1),
    dateTimeModified: null,
    order: 0,
    currency: 'usd',
    currencyFormat: null,
    decimals: 2,
    homePageWidgetDisplay: defaultWalletHomePageWidgetDisplay,
  );
}

void main() {
  test('extracts masked card and bank account suffixes', () {
    final List<NotificationAccountIdentifier> identifiers =
        extractNotificationAccountIdentifiers(
      'Debit card XX1234 used at STORE. Savings account ending 567890 credited.',
    );

    expect(
      identifiers.map((identifier) => identifier.tag),
      containsAll(<String>['1234', '567890']),
    );
    expect(
      identifiers.map((identifier) => identifier.accountType),
      containsAll(<String>[
        walletAccountTypeDebitCard,
        walletAccountTypeSavings,
      ]),
    );
  });

  test('matches wallets by normalized account tags', () {
    final List<TransactionWallet> wallets = <TransactionWallet>[
      buildWallet(
        walletPk: '1',
        name: 'Personal Card',
        accountType: walletAccountTypeCreditCard,
        accountTags: <String>['XX1234'],
      ),
      buildWallet(
        walletPk: '2',
        name: 'Main Bank',
        accountType: walletAccountTypeBank,
        accountTags: <String>['7890'],
      ),
    ];

    final TransactionWallet? matched = matchWalletByAccountIdentifiers(
      const <NotificationAccountIdentifier>[
        NotificationAccountIdentifier(
          tag: '1234',
          accountType: walletAccountTypeCreditCard,
          matchedText: 'card xx1234',
        ),
      ],
      wallets,
    );

    expect(matched?.walletPk, '1');
  });

  test('merges wallet metadata and keeps the more specific type', () {
    final TransactionWallet merged = mergeWalletMetadata(
      buildWallet(
        walletPk: '1',
        name: 'Primary',
        accountType: walletAccountTypeBank,
        accountTags: <String>['1234'],
      ),
      buildWallet(
        walletPk: '2',
        name: 'Merged',
        accountType: walletAccountTypeCreditCard,
        accountTags: <String>['5678'],
      ),
    );

    expect(merged.accountType, walletAccountTypeCreditCard);
    expect(merged.accountTags, <String>['1234', '5678']);
  });
}