import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/widgets/transactionEntry/transactionLabel.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

String? notificationPayload;

const String notificationTransactionsChannelId = 'notificationTransactions';
const String notificationTransactionsChannelName =
        'Notification Transactions';
const String notificationTransactionsThreadId = 'notificationTransactions';

int _notificationTransactionNotificationId = 5000;

Future<void> showNotificationTransactionSavedNotification(
    Transaction transaction,
) async {
    try {
        final TransactionWallet? wallet =
                await database.getWalletInstanceOrNull(transaction.walletFk);
        final AllWallets allWallets = AllWallets(
            list: wallet == null ? <TransactionWallet>[] : <TransactionWallet>[wallet],
            indexedByPk: wallet == null
                    ? <String, TransactionWallet>{}
                    : <String, TransactionWallet>{wallet.walletPk: wallet},
        );

        final String transactionLabel = await getTransactionLabel(transaction);
        final String amountLabel = convertToMoney(
            allWallets,
            transaction.amount,
            currencyKey: wallet?.currency,
        );
        final String walletLabel = wallet?.name.trim().isNotEmpty == true
                ? ' • ${wallet!.name}'
                : '';

        final NotificationDetails notificationDetails = NotificationDetails(
            android: AndroidNotificationDetails(
                notificationTransactionsChannelId,
                notificationTransactionsChannelName,
                channelDescription:
                        'Transaction confirmations for captured bank notifications',
                importance: Importance.max,
                priority: Priority.high,
            ),
            iOS: const DarwinNotificationDetails(
                threadIdentifier: notificationTransactionsThreadId,
            ),
        );

        await flutterLocalNotificationsPlugin.show(
            _nextNotificationTransactionNotificationId(),
            transaction.income == true
                    ? 'Income added from notification'
                    : 'Transaction added from notification',
            '$transactionLabel • $amountLabel$walletLabel',
            notificationDetails,
            payload:
                    'openTransaction?transactionPk=${Uri.encodeQueryComponent(transaction.transactionPk)}',
        );
    } catch (_) {
        return;
    }
}

int _nextNotificationTransactionNotificationId() {
    _notificationTransactionNotificationId++;
    if (_notificationTransactionNotificationId >= 2000000000) {
        _notificationTransactionNotificationId = 5000;
    }
    return _notificationTransactionNotificationId;
}
