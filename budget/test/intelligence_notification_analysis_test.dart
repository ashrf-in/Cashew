import 'package:budget/struct/intelligence.dart';
import 'package:budget/struct/notificationCapture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NotificationTransactionAnalysis parses direct AI output', () {
    final NotificationTransactionAnalysis analysis =
        NotificationTransactionAnalysis.fromJson({
      'isTransaction': true,
      'title': 'Starbucks',
      'amount': 18.75,
      'direction': 'expense',
      'transactionDate': '2026-03-20',
      'suggestedCategoryName': 'Dining',
      'suggestedAccountName': 'Main Account',
      'confidence': 91,
    });

    expect(analysis.isTransaction, isTrue);
    expect(analysis.title, 'Starbucks');
    expect(analysis.amount, 18.75);
    expect(
      analysis.direction,
      NotificationTransactionDirection.expense,
    );
    expect(analysis.transactionDate, DateTime.parse('2026-03-20'));
    expect(analysis.suggestedCategoryName, 'Dining');
    expect(analysis.suggestedAccountName, 'Main Account');
    expect(analysis.confidence, 91);
  });

  test('NotificationTransactionAnalysis accepts alternative field names', () {
    final NotificationTransactionAnalysis analysis =
        NotificationTransactionAnalysis.fromJson({
      'shouldSave': true,
      'transactionTitle': 'Payroll',
      'totalAmount': '2500.00',
      'direction': 'income',
      'date': '2026-03-19T09:30:00',
      'suggestedCategory': 'Salary',
      'suggestedWalletName': 'Checking',
    });

    expect(analysis.isTransaction, isTrue);
    expect(analysis.title, 'Payroll');
    expect(analysis.amount, 2500.0);
    expect(
      analysis.direction,
      NotificationTransactionDirection.income,
    );
    expect(
      analysis.transactionDate,
      DateTime.parse('2026-03-19T09:30:00'),
    );
    expect(analysis.suggestedCategoryName, 'Salary');
    expect(analysis.suggestedAccountName, 'Checking');
  });
}