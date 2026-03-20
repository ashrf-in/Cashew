import 'dart:async';
import 'dart:convert';
import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/pages/addEmailTemplate.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/pages/editCategoriesPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/intelligence.dart';
import 'package:budget/struct/notificationCapture.dart';
import 'package:budget/struct/notificationLearning.dart';
import 'package:budget/struct/notificationsGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/accountAndBackup.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/categoryIcon.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/openContainerNavigation.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/statusBox.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/transactionEntry/transactionEntry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:budget/functions.dart';
import 'package:googleapis/gmail/v1.dart' as gMail;
import 'package:html/parser.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

import 'addButton.dart';

StreamSubscription<ServiceNotificationEvent>? notificationListenerSubscription;
List<String> recentCapturedNotifications = [];

const Duration _notificationDedupWindow = Duration(seconds: 12);

final Map<String, DateTime> _recentNotificationFingerprints =
    <String, DateTime>{};

class _ResolvedNotificationCategorySelection {
  const _ResolvedNotificationCategorySelection({
    this.mainCategory,
    this.subCategory,
  });

  final TransactionCategory? mainCategory;
  final TransactionCategory? subCategory;
}

class _NotificationDraft {
  const _NotificationDraft({
    required this.packageName,
    required this.rawTitle,
    required this.title,
    required this.note,
    required this.absoluteAmount,
    required this.signedAmount,
    required this.category,
    required this.subCategory,
    required this.wallet,
    required this.direction,
    required this.confidence,
    required this.transactionDate,
  });

  final String? packageName;
  final String rawTitle;
  final String title;
  final String note;
  final double absoluteAmount;
  final double signedAmount;
  final TransactionCategory? category;
  final TransactionCategory? subCategory;
  final TransactionWallet? wallet;
  final NotificationTransactionDirection direction;
  final int confidence;
  final DateTime? transactionDate;
}

Future<bool> initNotificationScanning({bool requestPermission = false}) async {
  if (getPlatform(ignoreEmulation: true) != PlatformOS.isAndroid) return false;
  await notificationListenerSubscription?.cancel();
  notificationListenerSubscription = null;
  if (appStateSettings["notificationScanning"] != true) return false;

  bool status = requestPermission
      ? await requestReadNotificationPermission()
      : await hasReadNotificationPermission();
  if (status != true) return false;

  notificationListenerSubscription =
      NotificationListenerService.notificationsStream.listen(onNotification);
  return true;
}

Future<bool> hasReadNotificationPermission() async {
  return await NotificationListenerService.isPermissionGranted();
}

Future<bool> requestReadNotificationPermission() async {
  bool status = await hasReadNotificationPermission();
  if (status != true) {
    status = await NotificationListenerService.requestPermission();
  }
  return status;
}

// Known financial app package names sourced from FinArtReborn's static mapping
const Set<String> _knownFinancialPackages = {
  // Internal Android test app that posts bank-style notifications for Cashew.
  "com.cashew.notificationsimulator",
  "com.truist.mobile",
  "ae.ahb.digital",
  "com.sbi.lotusintouch",
  "com.sbi.SBIFreedomPlus",
  "com.cbt.ajmandigital",
  "com.phonepe.app",
  "ph.seabank.seabank",
  "pl.bzwbk.bzwbk24",
  "com.revolut.revolut",
  "com.revolut.business",
  "com.yellowpepper.pichincha",
  "io.wio.retail",
  "io.wio.sme",
  "de.santander.presentation",
  "com.appdeuna.wallet",
  "com.transferwise.android",
  "com.navyfederal.android",
  "com.dib.app",
  "com.paypal.android.p2pmobile",
  "money.jupiter",
  "uk.co.santander.santanderUK",
  "in.amazon.mShop.android.shopping",
  "com.Version1",
  "com.adcb.bank",
  "io.telda.app",
  "com.emiratesislamic.android",
  "com.scb.ae.bmw",
  "in.org.npci.upiapp",
  "ae.hsbc.hsbcuae",
  "com.snapwork.hdfc",
  "com.globe.gcash.android",
  "com.firstdirect.bankingonthego",
  "com.cbd.mobile",
  "com.db.businessline.cardapp",
  "com.db.pwcc.dbmobile",
  "com.nexta.nexta",
  "com.squareup.cash",
  "com.fineco.it",
  "com.barclays.android.barclaysmobilebanking",
  "com.csam.icici.bank.imobile",
  "com.nationstrust.frimi",
  "com.dreamplug.androidapp",
  "net.one97.paytm",
  "com.cbq.CBMobile",
  "com.iexceed.unoConsumerBanking",
  "com.bpi.ng.app",
  "com.google.android.apps.walletnfcrel",
  "com.citibank.mobile.citiuaePAT",
  "com.c6bank.app",
  "ar.com.santander.rio.mbanking",
  "com.sadapay.app",
  "com.askari",
  "za.co.fnb.connect.itt",
  "com.emiratesnbd.android",
  "com.hbl.android.hblmobilebanking",
  "com.sovereign.santander",
  "com.rak",
  "com.chase.sig.android",
  "com.ge.capital.konysbiapp",
  "uk.co.hsbc.hsbcukmobilebanking",
  "com.kiya.mahaplus",
  "br.com.neon",
  "com.google.android.apps.nbu.paisa.user",
  "com.samsung.android.spay",
  "com.varomoney.bank",
  "com.axis.mobile",
  "com.adib.mobile",
  "pk.com.telenor.phoenix",
  "in.irisbyyes.app",
  "com.infonow.bofa",
  "com.msf.kbank.mobile",
  "com.sofi.mobile",
  "mx.bancosantander.supermovil",
  "com.fab.personalbanking",
  "indwin.c3.shareapp",
  "com.sib.retail",
  "com.adcbmobile.pfm",
  "com.uab.personal",
  "com.bankfab.pbg.ae.dubaifirst",
  "com.simpl.android",
  "com.vipera.ts.starter.MashreqAE",
  "eu.eleader.mobilebanking.nbk",
  "com.rbs.mobile.android.natwest",
  "com.epifi.paisa",
  "com.wf.wellsfargomobile",
  "es.bancosantander.apps",
  "com.samsung.android.samsungpay.gear",
  "com.google.android.gm",
  "com.samsung.android.email.provider",
  "com.yahoo.mobile.client.android.mail",
  "com.yahoo.mobile.client.android.mail.lite",
};


List<String> getCustomNotificationPackages() {
  final raw = appStateSettings["notificationCustomPackages"];
  if (raw is List) return List<String>.from(raw);
  return [];
}

Future<void> addCustomNotificationPackage(String packageName) async {
  final packages = getCustomNotificationPackages();
  if (!packages.contains(packageName)) {
    packages.add(packageName);
    await updateSettings("notificationCustomPackages", packages,
        updateGlobalState: false);
  }
}

Future<void> removeCustomNotificationPackage(String packageName) async {
  final packages = getCustomNotificationPackages();
  packages.remove(packageName);
  await updateSettings("notificationCustomPackages", packages,
      updateGlobalState: false);
}

bool _isFinancialNotification(String packageName, String payload) {
  if (payload.trim().isEmpty) return false;

  // Only allow explicitly allowlisted apps — user-defined custom packages or built-in list.
  // No keyword/regex fallbacks: anything not on the list is ignored.
  return getCustomNotificationPackages().contains(packageName) ||
      _knownFinancialPackages.contains(packageName);
}

String _getCurrentNotificationCaptureMode() {
  final String configuredMode =
      appStateSettings[notificationCaptureModeSettingKey]?.toString() ??
          notificationCaptureModeSmart;
  if (notificationCaptureModes.contains(configuredMode)) {
    return configuredMode;
  }
  return notificationCaptureModeSmart;
}

void _storeRecentCapturedNotification(String messageString) {
  recentCapturedNotifications.insert(0, messageString);
  if (recentCapturedNotifications.length > 50) {
    recentCapturedNotifications = recentCapturedNotifications.sublist(0, 50);
  }
}

String getNotificationMessageFromFields({
  String? packageName,
  bool? hasRemoved,
  String? title,
  String? content,
}) {
  String output = "";
  output = output + "Package name: " + packageName.toString() + "\n";
  output = output + "Notification removed: " + hasRemoved.toString() + "\n";
  output = output + "\n----\n\n";
  output = output + "Notification Title: " + title.toString() + "\n\n";
  output = output + "Notification Content: " + content.toString();
  return output;
}

String getExactNotificationMessageFromFields({
  String? title,
  String? content,
}) {
  final List<String> lines = <String>[];
  if (title?.isNotEmpty == true && title != 'null') {
    lines.add(title!);
  }
  if (content?.isNotEmpty == true && content != 'null') {
    lines.add(content!);
  }
  return lines.join('\n').trim();
}

String _extractNotificationFieldValue(
  String messageString,
  String fieldLabel, {
  String? nextFieldLabel,
}) {
  final int startIndex = messageString.indexOf(fieldLabel);
  if (startIndex == -1) return '';
  final int valueStart = startIndex + fieldLabel.length;
  final int endIndex = nextFieldLabel == null
      ? messageString.length
      : messageString.indexOf(nextFieldLabel, valueStart);
  final String value = messageString
      .substring(valueStart, endIndex == -1 ? messageString.length : endIndex)
      .trim();
  if (value.toLowerCase() == 'null') return '';
  return value;
}

String extractExactNotificationMessage(String messageString) {
  final String title = _extractNotificationFieldValue(
    messageString,
    'Notification Title:',
    nextFieldLabel: 'Notification Content:',
  );
  final String content = _extractNotificationFieldValue(
    messageString,
    'Notification Content:',
  );
  final String exactMessage = getExactNotificationMessageFromFields(
    title: title,
    content: content,
  );
  if (exactMessage.isNotEmpty) {
    return exactMessage;
  }
  return messageString.trim();
}

bool _shouldIgnoreDuplicateNotification(String fingerprint) {
  final DateTime now = DateTime.now();
  _recentNotificationFingerprints.removeWhere(
    (_, capturedAt) => now.difference(capturedAt) > _notificationDedupWindow,
  );

  final DateTime? existing = _recentNotificationFingerprints[fingerprint];
  if (existing != null && now.difference(existing) <= _notificationDedupWindow) {
    return true;
  }

  _recentNotificationFingerprints[fingerprint] = now;
  return false;
}

Future<TransactionCategory?> _getFallbackNotificationCategory(
  NotificationTransactionDirection direction,
) async {
  final List<TransactionCategory> categories = await database.getAllCategories();
  for (final TransactionCategory category in categories) {
    if (category.income ==
        (direction == NotificationTransactionDirection.income)) {
      return category;
    }
  }
  return categories.firstOrNull;
}

Future<_NotificationDraft?> _buildNotificationDraft(
  String messageString,
) async {
  final IntelligenceConfig intelligenceConfig = getCurrentIntelligenceConfig();
  if (!intelligenceConfig.isConfigured) {
    debugPrint(
      'Notification AI parsing skipped because Intelligence is not configured.',
    );
    return null;
  }

  try {
    final String? packageName = extractNotificationPackageName(messageString);
    final String exactNotificationMessage =
        extractExactNotificationMessage(messageString);
    final List<TransactionCategory> categories =
        await database.getAllCategories(includeSubCategories: true);
    final List<TransactionWallet> wallets = await database.getAllWallets();
    final TransactionWallet? selectedWallet = await database
        .getWalletInstanceOrNull(appStateSettings['selectedWalletPk'] ?? '0');

    final NotificationTransactionAnalysis analysis =
        await analyzeNotificationTransaction(
      notificationMessage: messageString,
      categories: categories,
      wallets: wallets,
      selectedWallet: selectedWallet,
      config: intelligenceConfig,
    );

    final String? extractedTitle = analysis.title?.trim();
    final double? extractedAmount = analysis.amount?.abs();
    if (!analysis.isTransaction ||
        extractedTitle == null ||
        extractedTitle.isEmpty ||
        extractedAmount == null ||
        extractedAmount <= 0) {
      return null;
    }

    final NotificationLearningSuggestion learnedSuggestion =
        getNotificationLearningSuggestion(
      packageName: packageName,
      rawTitle: extractedTitle,
    );

    final String title =
        learnedSuggestion.canonicalTitle?.trim().isNotEmpty == true
            ? learnedSuggestion.canonicalTitle!.trim()
            : extractedTitle;

    final _ResolvedNotificationCategorySelection learnedCategorySelection =
        await _resolveNotificationCategorySelectionFromPks(
      categoryPk: learnedSuggestion.categoryPk,
      subCategoryPk: learnedSuggestion.subCategoryPk,
    );
    final TransactionCategory? aiCategory =
        matchReceiptCategory(analysis.suggestedCategoryName, categories);
    final _ResolvedNotificationCategorySelection aiCategorySelection =
        await _resolveNotificationCategorySelection(aiCategory);

    _ResolvedNotificationCategorySelection associatedTitleSelection =
        await _findAssociatedNotificationCategorySelection(title);
    if (associatedTitleSelection.mainCategory == null && title != extractedTitle) {
      associatedTitleSelection =
          await _findAssociatedNotificationCategorySelection(extractedTitle);
    }

    final NotificationTransactionDirection direction = analysis.direction ??
        inferNotificationTransactionDirection(
          message: exactNotificationMessage.isEmpty
              ? messageString
              : exactNotificationMessage,
          categoryIncome: learnedCategorySelection.mainCategory?.income ??
              aiCategorySelection.mainCategory?.income ??
              associatedTitleSelection.mainCategory?.income,
          parsedAmount: extractedAmount,
        );
    final TransactionCategory? fallbackCategory =
        await _getFallbackNotificationCategory(direction);
    final _ResolvedNotificationCategorySelection fallbackCategorySelection =
        await _resolveNotificationCategorySelection(fallbackCategory);

    final TransactionCategory? category = learnedCategorySelection.mainCategory ??
        aiCategorySelection.mainCategory ??
        associatedTitleSelection.mainCategory ??
        fallbackCategorySelection.mainCategory;
    final TransactionCategory? subCategory =
        learnedCategorySelection.subCategory ??
            aiCategorySelection.subCategory ??
            associatedTitleSelection.subCategory ??
            fallbackCategorySelection.subCategory;

    TransactionWallet? wallet;
    final String? learnedWalletPk =
        learnedSuggestion.walletPk ?? learnedSuggestion.packageWalletPk;
    if (learnedWalletPk?.trim().isNotEmpty == true) {
      wallet = await database.getWalletInstanceOrNull(learnedWalletPk!);
    }
    wallet ??= matchReceiptWallet(analysis.suggestedAccountName, wallets);
    wallet ??= selectedWallet;

    final bool usedFallbackCategory = learnedCategorySelection.mainCategory == null &&
        aiCategorySelection.mainCategory == null &&
        associatedTitleSelection.mainCategory == null;
    final int localConfidence = scoreNotificationConfidence(
      hasTemplate: analysis.isTransaction,
      hasParsedTitle: true,
      hasParsedAmount: true,
      hasResolvedCategory: category != null,
      hasResolvedWallet: wallet != null,
      hasLearnedValues: learnedSuggestion.hasLearnedValues,
      hasAssociatedTitle: associatedTitleSelection.mainCategory != null,
      usedFallbackCategory: usedFallbackCategory,
    );
    final int aiConfidence = analysis.confidence == null
        ? localConfidence
        : (analysis.confidence! < 0
            ? 0
            : analysis.confidence! > 100
                ? 100
                : analysis.confidence!);
    final int confidence = analysis.confidence == null
        ? localConfidence
        : (localConfidence < aiConfidence ? localConfidence : aiConfidence);
    final double signedAmount = applyNotificationDirectionToAmount(
      amount: extractedAmount,
      direction: direction,
    );

    return _NotificationDraft(
      packageName: packageName,
      rawTitle: extractedTitle,
      title: title,
      note: exactNotificationMessage.isEmpty
          ? messageString.trim()
          : exactNotificationMessage,
      absoluteAmount: extractedAmount,
      signedAmount: signedAmount,
      category: category,
      subCategory: subCategory,
      wallet: wallet,
      direction: direction,
      confidence: confidence,
      transactionDate: analysis.transactionDate,
    );
  } catch (e) {
    debugPrint('Notification AI parsing failed: $e');
    return null;
  }
}

DateTime _resolveNotificationDraftDate(DateTime? parsedDate, DateTime fallback) {
  if (parsedDate == null) return fallback;
  final bool looksDateOnly = parsedDate.hour == 0 &&
      parsedDate.minute == 0 &&
      parsedDate.second == 0 &&
      parsedDate.millisecond == 0 &&
      parsedDate.microsecond == 0;
  if (looksDateOnly) {
    return fallback.copyWith(
      year: parsedDate.year,
      month: parsedDate.month,
      day: parsedDate.day,
    );
  }
  return parsedDate;
}

Future<Transaction?> _autoCreateNotificationTransaction(
  _NotificationDraft draft, {
  DateTime? dateTime,
}) async {
  if (draft.category == null) return null;

  final String walletPk =
      draft.wallet?.walletPk ?? appStateSettings['selectedWalletPk'] ?? '0';
  final DateTime resolvedDate = _resolveNotificationDraftDate(
    draft.transactionDate,
    dateTime ?? DateTime.now(),
  );
  final int? rowId = await database.createOrUpdateTransaction(
    Transaction(
      transactionPk: '-1',
      name: draft.title,
      amount: draft.signedAmount,
      note: draft.note,
      categoryFk: draft.category!.categoryPk,
      subCategoryFk: draft.subCategory?.categoryPk,
      walletFk: walletPk,
      dateCreated: resolvedDate,
      dateTimeModified: null,
      income: draft.direction == NotificationTransactionDirection.income,
      paid: true,
      skipPaid: false,
      methodAdded: MethodAdded.notification,
    ),
    insert: true,
  );
  if (rowId == null) return null;

  final Transaction transactionJustAdded =
      await database.getTransactionFromRowId(rowId);
  flashTransaction(transactionJustAdded.transactionPk, flashCount: 2);
  if (draft.title.trim().isNotEmpty) {
    await addAssociatedTitles(
      draft.title,
      draft.subCategory ?? draft.category!,
    );
  }
  await learnAcceptedNotificationDraft(
    packageName: draft.packageName,
    rawTitle: draft.rawTitle,
    finalTitle: transactionJustAdded.name,
    categoryPk: transactionJustAdded.categoryFk,
    subCategoryPk: transactionJustAdded.subCategoryFk,
    walletPk: transactionJustAdded.walletFk,
  );
  await showNotificationTransactionSavedNotification(transactionJustAdded);
  return transactionJustAdded;
}

Future<void> onNotification(ServiceNotificationEvent event) async {
  await processIncomingNotificationEvent(
    packageName: event.packageName,
    title: event.title,
    content: event.content,
    hasRemoved: event.hasRemoved == true,
    receivedAt: DateTime.now(),
  );
}

Future<void> processIncomingNotificationEvent({
  required String? packageName,
  required String? title,
  required String? content,
  required bool hasRemoved,
  DateTime? receivedAt,
}) async {
  if (hasRemoved) return;
  if (appStateSettings["notificationScanning"] != true) return;

  final String resolvedPackageName = packageName ?? '';
  final String notificationText = [title ?? '', content ?? ''].join('\n').trim();

  if (!_isFinancialNotification(resolvedPackageName, notificationText)) return;

  final String fingerprint = normalizeNotificationFingerprint(
    [resolvedPackageName, title ?? '', content ?? ''].join(' | '),
  );
  if (_shouldIgnoreDuplicateNotification(fingerprint)) return;

  final String messageString = getNotificationMessageFromFields(
    packageName: resolvedPackageName,
    hasRemoved: hasRemoved,
    title: title,
    content: content,
  );
  _storeRecentCapturedNotification(messageString);
  await queueTransactionFromMessage(
    messageString,
    willPushRoute: false,
    allowAutoCreate: true,
    dateTime: receivedAt ?? DateTime.now(),
  );
}

class InitializeNotificationService extends StatefulWidget {
  const InitializeNotificationService({required this.child, super.key});
  final Widget child;

  @override
  State<InitializeNotificationService> createState() =>
      _InitializeNotificationServiceState();
}

class _InitializeNotificationServiceState
    extends State<InitializeNotificationService> {
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () async {
      initNotificationScanning();
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

Future<bool> queueTransactionFromMessage(String messageString,
    {
      bool willPushRoute = true,
      bool allowAutoCreate = false,
      DateTime? dateTime,
    }) async {
  final _NotificationDraft? draft = await _buildNotificationDraft(messageString);
  if (draft == null) return false;

  final DateTime resolvedDate = _resolveNotificationDraftDate(
    draft.transactionDate,
    dateTime ?? DateTime.now(),
  );

  if (allowAutoCreate &&
      shouldAutoCreateNotification(
        captureMode: _getCurrentNotificationCaptureMode(),
        confidence: draft.confidence,
        hasAmount: draft.absoluteAmount > 0,
        hasTitle: draft.title.trim().isNotEmpty,
        hasCategory: draft.category != null,
      )) {
    final Transaction? createdTransaction = await _autoCreateNotificationTransaction(
      draft,
      dateTime: resolvedDate,
    );
    return createdTransaction != null;
  }

  if (willPushRoute) {
    await pushRoute(
      null,
      AddTransactionPage(
        useCategorySelectedIncome: true,
        routesToPopAfterDelete: RoutesToPopAfterDelete.None,
        selectedAmount: draft.signedAmount,
        selectedTitle: draft.title,
        selectedNotes: draft.note,
        selectedCategory: draft.category,
        selectedSubCategory: draft.subCategory,
        startInitialAddTransactionSequence: false,
        selectedWallet: draft.wallet,
        selectedDate: resolvedDate,
        onTransactionSaved: (transaction) async {
          await learnAcceptedNotificationDraft(
            packageName: draft.packageName,
            rawTitle: draft.rawTitle,
            finalTitle: transaction.name,
            categoryPk: transaction.categoryFk,
            subCategoryPk: transaction.subCategoryFk,
            walletPk: transaction.walletFk,
          );
        },
      ),
    );
    return true;
  }

  return false;
}

Future<_ResolvedNotificationCategorySelection>
    _findAssociatedNotificationCategorySelection(String title) async {
  final TransactionAssociatedTitleWithCategory? foundTitle =
      (await database.getSimilarAssociatedTitles(title: title, limit: 1))
          .firstOrNull;
  return _resolveNotificationCategorySelection(foundTitle?.category);
}

Future<_ResolvedNotificationCategorySelection>
    _resolveNotificationCategorySelection(TransactionCategory? category) async {
  if (category == null) {
    return const _ResolvedNotificationCategorySelection();
  }
  if (category.mainCategoryPk == null) {
    return _ResolvedNotificationCategorySelection(mainCategory: category);
  }

  final TransactionCategory? mainCategory =
      await database.getCategoryInstanceOrNull(category.mainCategoryPk!);
  if (mainCategory == null) {
    return const _ResolvedNotificationCategorySelection();
  }

  return _ResolvedNotificationCategorySelection(
    mainCategory: mainCategory,
    subCategory: category,
  );
}

Future<_ResolvedNotificationCategorySelection>
    _resolveNotificationCategorySelectionFromPks({
  required String? categoryPk,
  required String? subCategoryPk,
}) async {
  if (subCategoryPk?.trim().isNotEmpty == true) {
    final TransactionCategory? subCategory =
        await database.getCategoryInstanceOrNull(subCategoryPk!);
    return _resolveNotificationCategorySelection(subCategory);
  }

  if (categoryPk?.trim().isNotEmpty == true) {
    final TransactionCategory? category =
        await database.getCategoryInstanceOrNull(categoryPk!);
    return _resolveNotificationCategorySelection(category);
  }

  return const _ResolvedNotificationCategorySelection();
}

String getNotificationMessage(ServiceNotificationEvent event) {
  return getNotificationMessageFromFields(
    packageName: event.packageName,
    hasRemoved: event.hasRemoved,
    title: event.title,
    content: event.content,
  );
}

String? _extractTemplateSegment(
  String messageString,
  String before,
  String after,
) {
  int startIndex = before.isEmpty ? 0 : messageString.indexOf(before);
  if (startIndex == -1) return null;

  startIndex += before.length;
  int endIndex = after.isEmpty
      ? messageString.length
      : messageString.indexOf(after, startIndex);
  if (endIndex == -1 || endIndex < startIndex) return null;

  String extracted = messageString.substring(startIndex, endIndex).trim();
  if (extracted.isEmpty) return null;
  return extracted;
}

double? _parseNotificationAmount(String amountString) {
  bool isNegative = RegExp(r'[-—−–‐⁃‑‒―]').hasMatch(amountString);
  String normalized = amountString.replaceAll(RegExp(r'[^0-9,.]'), '');
  if (normalized.isEmpty) return null;

  int lastComma = normalized.lastIndexOf(',');
  int lastDot = normalized.lastIndexOf('.');

  if (lastComma != -1 && lastDot != -1) {
    if (lastComma > lastDot) {
      normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
    } else {
      normalized = normalized.replaceAll(',', '');
    }
  } else if (lastComma != -1) {
    List<String> parts = normalized.split(',');
    normalized = parts.length == 2 && parts.last.length <= 2
        ? '${parts.first}.${parts.last}'
        : parts.join();
  } else if (lastDot != -1) {
    List<String> parts = normalized.split('.');
    if (parts.length == 2) {
      normalized = parts.last.length <= 2 ? normalized : parts.join();
    } else {
      normalized =
          '${parts.sublist(0, parts.length - 1).join()}.${parts.last}';
    }
  }

  double? amount = double.tryParse(normalized);
  if (amount == null) return null;
  return isNegative ? -amount.abs() : amount.abs();
}

class AutoTransactionsPageNotifications extends StatefulWidget {
  const AutoTransactionsPageNotifications({Key? key}) : super(key: key);

  @override
  State<AutoTransactionsPageNotifications> createState() =>
      _AutoTransactionsPageNotificationsState();
}

class _AutoTransactionsPageNotificationsState
    extends State<AutoTransactionsPageNotifications> {
  bool canReadEmails = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final IntelligenceConfig intelligenceConfig = getCurrentIntelligenceConfig();
    final String captureMode = _getCurrentNotificationCaptureMode();
    return PageFramework(
      dragDownToDismiss: true,
      title: "Auto Transactions",
      actions: [
        RefreshButton(
          timeout: Duration.zero,
          onTap: () async {
            loadingIndeterminateKey.currentState?.setVisibility(true);
            setState(() {});
            loadingIndeterminateKey.currentState?.setVisibility(false);
          },
        ),
      ],
      listWidgets: [
        Padding(
          padding:
              const EdgeInsetsDirectional.only(bottom: 5, start: 20, end: 20),
          child: TextFont(
            text:
                "Transactions from allowed financial apps are sent directly to Intelligence for extraction. Cashew no longer relies on notification templates or regex-style boundary parsing for notification capture.",
            fontSize: 14,
            maxLines: 10,
          ),
        ),
        SettingsContainerSwitch(
          onSwitched: (value) async {
            await updateSettings("notificationScanning", value,
                updateGlobalState: false);
            if (value == true) {
              bool status =
                  await initNotificationScanning(requestPermission: true);
              if (status == false) {
                await updateSettings("notificationScanning", false,
                    updateGlobalState: false);
                openSnackbar(
                  SnackbarMessage(
                    title: "Notification access required",
                    description:
                        "Enable Cashew in Android Settings > Special app access > Notification access.",
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.notifications_off_outlined
                        : Icons.notifications_off_rounded,
                  ),
                );
              }
            } else {
              await notificationListenerSubscription?.cancel();
              notificationListenerSubscription = null;
            }
          },
          title: "Notification Transactions",
          description:
              "When an allowed financial app posts a notification, Cashew sends it directly to Intelligence, saves the parsed transaction, and copies the exact notification text into the transaction note.",
          initialValue: appStateSettings["notificationScanning"],
        ),
        SettingsContainerDropdown(
          title: "Capture Mode",
          description: getNotificationCaptureModeDescription(captureMode),
          initial: captureMode,
          items: notificationCaptureModes,
          getLabel: getNotificationCaptureModeLabel,
          onChanged: (value) async {
            await updateSettings(
              notificationCaptureModeSettingKey,
              value,
              updateGlobalState: false,
            );
            setState(() {});
          },
          icon: appStateSettings["outlinedIcons"]
              ? Icons.bolt_outlined
              : Icons.bolt_rounded,
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 20,
            end: 20,
            top: 6,
            bottom: 10,
          ),
          child: TextFont(
            text: intelligenceConfig.isConfigured
                ? "Direct AI notification parsing is active. Each allowed notification is analyzed immediately and the raw notification text is preserved in the transaction note."
                : "Notification auto-capture is AI-only. Configure Intelligence in Settings before relying on Notification Transactions.",
            fontSize: 13,
            maxLines: 6,
            textColor: Colors.grey,
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 15,
            end: 15,
            bottom: 8,
          ),
          child: StatusBox(
            title: intelligenceConfig.isConfigured
                ? "Direct AI Parsing"
                : "Intelligence Required",
            description: intelligenceConfig.isConfigured
                ? "Notification templates are no longer used here. Each allowed notification is analyzed directly, and the exact notification text is stored in the transaction note."
                : "Configure Intelligence to enable direct AI parsing for allowed financial notifications.",
            icon: appStateSettings["outlinedIcons"]
                ? Icons.auto_awesome_outlined
                : Icons.auto_awesome_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        NotificationPackagesSection(
          onChanged: () => setState(() {}),
        ),
        EmailsList(
          messagesList: recentCapturedNotifications,
        ),
      ],
    );
  }
}

class NotificationPackagesSection extends StatelessWidget {
  const NotificationPackagesSection({required this.onChanged, super.key});
  final VoidCallback onChanged;

  void _showAddDialog(BuildContext context) {
    String input = '';
    openBottomSheet(
      context,
      PopupFramework(
        title: "Add App Package",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 5),
              child: TextFont(
                text:
                    "Enter the full package name of the app (e.g. com.mybank.app). You can find it in the captured notifications list below.",
                fontSize: 13,
                maxLines: 5,
                textColor: Colors.grey,
              ),
            ),
            TextInput(
              autoFocus: true,
              labelText: "com.example.bankapp",
              bubbly: false,
              onChanged: (value) => input = value.trim(),
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 0),
            ),
            const SizedBox(height: 10),
            Button(
              label: "Add",
              onTap: () async {
                if (input.isNotEmpty) {
                  await addCustomNotificationPackage(input);
                  popRoute(context);
                  onChanged();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final packages = getCustomNotificationPackages();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsetsDirectional.only(start: 20, end: 20, top: 16, bottom: 4),
          child: TextFont(
            text: "Allowed App Packages",
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 20, end: 20, bottom: 8),
          child: TextFont(
            text:
                "Notifications from these apps will be sent directly to Intelligence, in addition to the built-in banking app list.",
            fontSize: 13,
            maxLines: 5,
            textColor: Colors.grey,
          ),
        ),
        if (packages.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 20, end: 20, bottom: 8),
            child: TextFont(
              text: "No custom packages added.",
              fontSize: 13,
              textColor: Colors.grey,
            ),
          ),
        for (final pkg in packages)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 15, vertical: 2),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: getColor(context, "lightDarkAccent"),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                    start: 15, end: 4, top: 4, bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFont(
                        text: pkg,
                        fontSize: 14,
                        maxLines: 2,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        appStateSettings["outlinedIcons"]
                            ? Icons.delete_outlined
                            : Icons.delete_rounded,
                        color: Colors.red,
                        size: 20,
                      ),
                      onPressed: () async {
                        await removeCustomNotificationPackage(pkg);
                        onChanged();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.only(
              start: 15, end: 15, top: 6, bottom: 8),
          child: Button(
            label: "Add Package",
            onTap: () => _showAddDialog(context),
            icon: appStateSettings["outlinedIcons"]
                ? Icons.add_circle_outline
                : Icons.add_circle_rounded,
          ),
        ),
      ],
    );
  }
}

class AutoTransactionsPageEmail extends StatefulWidget {
  const AutoTransactionsPageEmail({Key? key}) : super(key: key);

  @override
  State<AutoTransactionsPageEmail> createState() =>
      _AutoTransactionsPageEmailState();
}

class _AutoTransactionsPageEmailState extends State<AutoTransactionsPageEmail> {
  bool canReadEmails =
      appStateSettings["AutoTransactions-canReadEmails"] ?? false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () async {
      if (canReadEmails == true && googleUser == null) {
        await signInGoogle(
            context: context, waitForCompletion: true, gMailPermissions: true);
        updateSettings("AutoTransactions-canReadEmails", true,
            pagesNeedingRefresh: [3], updateGlobalState: false);
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      dragDownToDismiss: true,
      title: "Auto Transactions",
      actions: [
        RefreshButton(onTap: () async {
          loadingIndeterminateKey.currentState?.setVisibility(true);
          await parseEmailsInBackground(context,
              sayUpdates: true, forceParse: true);
          loadingIndeterminateKey.currentState?.setVisibility(false);
        }),
      ],
      listWidgets: [
        Padding(
          padding:
              const EdgeInsetsDirectional.only(bottom: 5, start: 20, end: 20),
          child: TextFont(
            text:
                "Transactions can be created automatically based on your emails. This can be useful when you get emails from your bank, and you want to automatically add these transactions.",
            fontSize: 14,
            maxLines: 10,
          ),
        ),
        SettingsContainerSwitch(
          onSwitched: (value) async {
            if (value == true) {
              bool result = await signInGoogle(
                  context: context,
                  waitForCompletion: true,
                  gMailPermissions: true);
              if (result == false) {
                return false;
              }
              setState(() {
                canReadEmails = true;
              });
              updateSettings("AutoTransactions-canReadEmails", true,
                  pagesNeedingRefresh: [3], updateGlobalState: false);
            } else {
              setState(() {
                canReadEmails = false;
              });
              updateSettings("AutoTransactions-canReadEmails", false,
                  updateGlobalState: false, pagesNeedingRefresh: [3]);
            }
          },
          title: "Read Emails",
          description:
              "Parse Gmail emails on app launch. Every email is only scanned once.",
          initialValue: canReadEmails,
          icon: appStateSettings["outlinedIcons"]
              ? Icons.mark_email_unread_outlined
              : Icons.mark_email_unread_rounded,
        ),
        IgnorePointer(
          ignoring: !canReadEmails,
          child: AnimatedOpacity(
            duration: Duration(milliseconds: 300),
            opacity: canReadEmails ? 1 : 0.4,
            child: GmailApiScreen(),
          ),
        )
      ],
    );
  }
}

Future<void> parseEmailsInBackground(context,
    {bool sayUpdates = false, bool forceParse = false}) async {
  if (appStateSettings["hasSignedIn"] == false) return;
  if (errorSigningInDuringCloud == true) return;
  if (appStateSettings["emailScanning"] == false) return;
  // Prevent sign-in on web - background sign-in cannot access Google Drive etc.
  if (kIsWeb && !entireAppLoaded) return;
  // print(entireAppLoaded);
  //Only run this once, don't run again if the global state changes (e.g. when changing a setting)
  if (entireAppLoaded == false || forceParse) {
    if (appStateSettings["AutoTransactions-canReadEmails"] == true) {
      List<Transaction> transactionsToAdd = [];
      Stopwatch stopwatch = new Stopwatch()..start();
      print("Scanning emails");

      bool hasSignedIn = false;
      if (googleUser == null) {
        hasSignedIn = await signInGoogle(
            context: context,
            gMailPermissions: true,
            waitForCompletion: false,
            silentSignIn: true);
      } else {
        hasSignedIn = true;
      }
      if (hasSignedIn == false) {
        return;
      }

      List<dynamic> emailsParsed =
          appStateSettings["EmailAutoTransactions-emailsParsed"] ?? [];
      int amountOfEmails =
          appStateSettings["EmailAutoTransactions-amountOfEmails"] ?? 10;
      int newEmailCount = 0;

      final authHeaders = await googleUser!.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      gMail.GmailApi gmailApi = gMail.GmailApi(authenticateClient);
      gMail.ListMessagesResponse results = await gmailApi.users.messages
          .list(googleUser!.id.toString(), maxResults: amountOfEmails);

      int currentEmailIndex = 0;

      List<ScannerTemplate> scannerTemplates =
          await database.getAllScannerTemplates();
      if (scannerTemplates.length <= 0) {
        openSnackbar(
          SnackbarMessage(
            title:
                "You have not setup the email scanning configuration in settings.",
            onTap: () {
              pushRoute(
                context,
                AutoTransactionsPageEmail(),
              );
            },
          ),
        );
      }
      for (gMail.Message message in results.messages!) {
        currentEmailIndex++;
        loadingProgressKey.currentState
            ?.setProgressPercentage(currentEmailIndex / amountOfEmails);
        // await Future.delayed(Duration(milliseconds: 1000));

        // Remove this to always parse emails
        if (emailsParsed.contains(message.id!)) {
          print("Already checked this email!");
          continue;
        }
        newEmailCount++;

        gMail.Message messageData = await gmailApi.users.messages
            .get(googleUser!.id.toString(), message.id!);
        DateTime messageDate = DateTime.fromMillisecondsSinceEpoch(
            int.parse(messageData.internalDate ?? ""));
        String messageString = getEmailMessage(messageData);
        print("Adding transaction based on email");

        String? title;
        double? amountDouble;

        bool doesEmailContain = false;
        ScannerTemplate? templateFound;
        for (ScannerTemplate scannerTemplate in scannerTemplates) {
          if (messageString.contains(scannerTemplate.contains)) {
            doesEmailContain = true;
            templateFound = scannerTemplate;
            title = getTransactionTitleFromEmail(
              messageString,
              scannerTemplate.titleTransactionBefore,
              scannerTemplate.titleTransactionAfter,
            );
            amountDouble = getTransactionAmountFromEmail(
              messageString,
              scannerTemplate.amountTransactionBefore,
              scannerTemplate.amountTransactionAfter,
            );
            break;
          }
        }

        if (doesEmailContain == false) {
          emailsParsed.insert(0, message.id!);
          continue;
        }

        if (title == null) {
          openSnackbar(
            SnackbarMessage(
              title:
                  "Couldn't find title in email. Check the email settings page for more information.",
              onTap: () {
                pushRoute(
                  context,
                  AutoTransactionsPageEmail(),
                );
              },
            ),
          );
          emailsParsed.insert(0, message.id!);
          continue;
        } else if (amountDouble == null) {
          openSnackbar(
            SnackbarMessage(
              title:
                  "Couldn't find amount in email. Check the email settings page for more information.",
              onTap: () {
                pushRoute(
                  context,
                  AutoTransactionsPageEmail(),
                );
              },
            ),
          );

          emailsParsed.insert(0, message.id!);
          continue;
        }

        TransactionAssociatedTitleWithCategory? foundTitle =
            (await database.getSimilarAssociatedTitles(title: title, limit: 1))
                .firstOrNull;

        TransactionCategory? selectedCategory = foundTitle?.category;
        if (selectedCategory == null) continue;

        title = filterEmailTitle(title);

        await addAssociatedTitles(title, selectedCategory);

        Transaction transactionToAdd = Transaction(
          transactionPk: "-1",
          name: title,
          amount: (amountDouble).abs() * (selectedCategory.income ? 1 : -1),
          note: "",
          categoryFk: selectedCategory.categoryPk,
          walletFk: appStateSettings["selectedWalletPk"],
          dateCreated: messageDate,
          dateTimeModified: null,
          income: selectedCategory.income,
          paid: true,
          skipPaid: false,
          methodAdded: MethodAdded.email,
        );
        transactionsToAdd.add(transactionToAdd);
        openSnackbar(
          SnackbarMessage(
            title: templateFound!.templateName + ": " + "From Email",
            description: title,
            icon: appStateSettings["outlinedIcons"]
                ? Icons.payments_outlined
                : Icons.payments_rounded,
          ),
        );
        // TODO have setting so they can choose if the emails are markes as read
        gmailApi.users.messages.modify(
          gMail.ModifyMessageRequest(removeLabelIds: ["UNREAD"]),
          googleUser!.id,
          message.id!,
        );

        emailsParsed.insert(0, message.id!);
      }
      // wait for intro animation to finish
      if (Duration(milliseconds: 2500) > stopwatch.elapsed) {
        print("waited extra" +
            (Duration(milliseconds: 2500) - stopwatch.elapsed).toString());
        await Future.delayed(
            Duration(milliseconds: 2500) - stopwatch.elapsed, () {});
      }
      for (Transaction transaction in transactionsToAdd) {
        await database.createOrUpdateTransaction(insert: true, transaction);
      }
      List<dynamic> emails = [
        ...emailsParsed
            .take(appStateSettings["EmailAutoTransactions-amountOfEmails"] + 10)
      ];
      updateSettings(
        "EmailAutoTransactions-emailsParsed",
        emails, // Keep 10 extra in case maybe the user deleted some emails recently
        updateGlobalState: false,
      );
      if (newEmailCount > 0 || sayUpdates == true)
        openSnackbar(
          SnackbarMessage(
            title: "Scanned " + results.messages!.length.toString() + " emails",
            description: newEmailCount.toString() +
                pluralString(newEmailCount == 1, " new email"),
            icon: appStateSettings["outlinedIcons"]
                ? Icons.mark_email_unread_outlined
                : Icons.mark_email_unread_rounded,
            onTap: () {
              pushRoute(context, AutoTransactionsPageEmail());
            },
          ),
        );
    }
  }
}

String? getTransactionTitleFromEmail(String messageString,
    String titleTransactionBefore, String titleTransactionAfter) {
  String? title = _extractTemplateSegment(
    messageString,
    titleTransactionBefore,
    titleTransactionAfter,
  );
  if (title == null) return null;

  title = title.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  if (title.isEmpty) return null;
  return title.capitalizeFirst;
}

double? getTransactionAmountFromEmail(String messageString,
    String amountTransactionBefore, String amountTransactionAfter) {
  String? amountString = _extractTemplateSegment(
    messageString,
    amountTransactionBefore,
    amountTransactionAfter,
  );
  if (amountString == null) return null;

  return _parseNotificationAmount(amountString);
}

class GmailApiScreen extends StatefulWidget {
  @override
  _GmailApiScreenState createState() => _GmailApiScreenState();
}

class _GmailApiScreenState extends State<GmailApiScreen> {
  bool loaded = false;
  bool loading = false;
  String error = "";
  int amountOfEmails =
      appStateSettings["EmailAutoTransactions-amountOfEmails"] ?? 10;

  late gMail.GmailApi gmailApi;
  List<String> messagesList = [];

  @override
  void initState() {
    super.initState();
  }

  init() async {
    loading = true;
    if (googleUser != null) {
      try {
        final authHeaders = await googleUser!.authHeaders;
        final authenticateClient = GoogleAuthClient(authHeaders);
        gMail.GmailApi gmailApi = gMail.GmailApi(authenticateClient);
        gMail.ListMessagesResponse results = await gmailApi.users.messages
            .list(googleUser!.id.toString(), maxResults: amountOfEmails);
        setState(() {
          loaded = true;
          error = "";
        });
        int currentEmailIndex = 0;
        for (gMail.Message message in results.messages!) {
          gMail.Message messageData = await gmailApi.users.messages
              .get(googleUser!.id.toString(), message.id!);
          // print(DateTime.fromMillisecondsSinceEpoch(
          //     int.parse(messageData.internalDate ?? "")));
          String emailMessageString = getEmailMessage(messageData);
          messagesList.add(emailMessageString);
          currentEmailIndex++;
          loadingProgressKey.currentState
              ?.setProgressPercentage(currentEmailIndex / amountOfEmails);
          if (mounted) {
            setState(() {});
          } else {
            loadingProgressKey.currentState?.setProgressPercentage(0);
            break;
          }
        }
      } catch (e) {
        setState(() {
          loaded = true;
          error = e.toString();
        });
      }
    }
    loading = false;
  }

  @override
  Widget build(BuildContext context) {
    if (googleUser == null) {
      return SizedBox();
    } else if (error != "" || (loaded == false && loading == false)) {
      init();
    }
    if (error != "") {
      return Padding(
        padding: const EdgeInsetsDirectional.only(
          top: 28.0,
          start: 20,
          end: 20,
        ),
        child: Center(
          child: TextFont(
            text: error,
            fontSize: 15,
            textAlign: TextAlign.center,
            maxLines: 10,
          ),
        ),
      );
    }
    if (loaded) {
      // If the Future is complete, display the preview.

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsContainerDropdown(
            title: "Amount to Parse",
            description:
                "The number of recent emails to check to add transactions.",
            initial: (amountOfEmails).toString(),
            items: ["5", "10", "15", "20", "25"],
            onChanged: (value) {
              updateSettings(
                "EmailAutoTransactions-amountOfEmails",
                int.parse(value),
                updateGlobalState: false,
              );
            },
            icon: appStateSettings["outlinedIcons"]
                ? Icons.format_list_numbered_outlined
                : Icons.format_list_numbered_rounded,
          ),
          Padding(
            padding:
                const EdgeInsetsDirectional.only(top: 13, bottom: 4, start: 15),
            child: TextFont(
              text: "Configure",
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 5),
          StreamBuilder<List<ScannerTemplate>>(
            stream: database.watchAllScannerTemplates(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                if (snapshot.data!.length <= 0) {
                  return Padding(
                    padding: const EdgeInsetsDirectional.all(5),
                    child: StatusBox(
                      title: "Email Configuration Missing",
                      description: "Please add a configuration.",
                      icon: appStateSettings["outlinedIcons"]
                          ? Icons.warning_outlined
                          : Icons.warning_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (ScannerTemplate scannerTemplate in snapshot.data!)
                      ScannerTemplateEntry(
                        messagesList: messagesList,
                        scannerTemplate: scannerTemplate,
                      )
                  ],
                );
              } else {
                return Container();
              }
            },
          ),
          OpenContainerNavigation(
            openPage: AddEmailTemplate(
              messagesList: messagesList,
            ),
            borderRadius: 15,
            button: (openContainer) {
              return Row(
                children: [
                  Expanded(
                    child: AddButton(
                      margin: EdgeInsetsDirectional.only(
                        start: 15,
                        end: 15,
                        bottom: 9,
                        top: 4,
                      ),
                      onTap: openContainer,
                    ),
                  ),
                ],
              );
            },
          ),
          EmailsList(messagesList: messagesList)
        ],
      );
    } else {
      return Padding(
        padding: const EdgeInsetsDirectional.only(top: 28.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }
  }
}

class ScannerTemplateEntry extends StatelessWidget {
  const ScannerTemplateEntry({
    required this.scannerTemplate,
    required this.messagesList,
    super.key,
  });
  final ScannerTemplate scannerTemplate;
  final List<String> messagesList;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 15, end: 15, bottom: 10),
      child: OpenContainerNavigation(
        openPage: AddEmailTemplate(
          messagesList: messagesList,
          scannerTemplate: scannerTemplate,
        ),
        borderRadius: 15,
        button: (openContainer) {
          return Tappable(
            borderRadius: 15,
            color: getColor(context, "lightDarkAccent"),
            onTap: openContainer,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 7,
                end: 15,
                top: 5,
                bottom: 5,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      CategoryIcon(
                          categoryPk: scannerTemplate.defaultCategoryFk,
                          size: 25),
                      SizedBox(width: 7),
                      TextFont(
                        text: scannerTemplate.templateName,
                        fontWeight: FontWeight.bold,
                      ),
                    ],
                  ),
                  ButtonIcon(
                    onTap: () async {
                      DeletePopupAction? action = await openDeletePopup(
                        context,
                        title: "Delete template?",
                        subtitle: scannerTemplate.templateName,
                      );
                      if (action == DeletePopupAction.Delete) {
                        await database.deleteScannerTemplate(
                            scannerTemplate.scannerTemplatePk);
                        popRoute(context);
                        openSnackbar(
                          SnackbarMessage(
                            title: "Deleted " + scannerTemplate.templateName,
                            icon: Icons.delete,
                          ),
                        );
                      }
                    },
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.delete_outlined
                        : Icons.delete_rounded,
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String parseHtmlString(String htmlString) {
  final document = parse(htmlString);
  final String parsedString = parse(document.body!.text).documentElement!.text;

  return parsedString;
}

class EmailsList extends StatelessWidget {
  const EmailsList({
    required this.messagesList,
    this.onTap,
    this.backgroundColor,
    super.key,
  });
  final List<String> messagesList;
  final Function(String)? onTap;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ScannerTemplate>>(
      stream: database.watchAllScannerTemplates(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          List<ScannerTemplate> scannerTemplates = snapshot.data!;
          List<Widget> messageTxt = [];
          for (String messageString in messagesList) {
            bool doesEmailContain = false;
            String? title;
            double? amountDouble;
            String? templateFound;

            for (ScannerTemplate scannerTemplate in scannerTemplates) {
              if (messageString.contains(scannerTemplate.contains)) {
                doesEmailContain = true;
                templateFound = scannerTemplate.templateName;
                title = getTransactionTitleFromEmail(
                    messageString,
                    scannerTemplate.titleTransactionBefore,
                    scannerTemplate.titleTransactionAfter);
                amountDouble = getTransactionAmountFromEmail(
                    messageString,
                    scannerTemplate.amountTransactionBefore,
                    scannerTemplate.amountTransactionAfter);
                break;
              }
            }

            messageTxt.add(
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 15, vertical: 5),
                child: Tappable(
                  borderRadius: 15,
                  color: doesEmailContain &&
                          (title == null || amountDouble == null)
                      ? Theme.of(context)
                          .colorScheme
                          .selectableColorRed
                          .withOpacity(0.5)
                      : doesEmailContain
                          ? Theme.of(context)
                              .colorScheme
                              .selectableColorGreen
                              .withOpacity(0.5)
                          : backgroundColor ??
                              getColor(context, "lightDarkAccent"),
                  onTap: () {
                    if (onTap != null) onTap!(messageString);
                    if (onTap == null)
                      queueTransactionFromMessage(messageString);
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: 20, vertical: 15),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              doesEmailContain &&
                                      (title == null || amountDouble == null)
                                  ? Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                          bottom: 5),
                                      child: TextFont(
                                        text: "Parsing failed.",
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17,
                                      ),
                                    )
                                  : SizedBox(),
                              doesEmailContain
                                  ? templateFound == null
                                      ? TextFont(
                                          fontSize: 19,
                                          text: "Template Not found.",
                                          maxLines: 10,
                                          fontWeight: FontWeight.bold,
                                        )
                                      : TextFont(
                                          fontSize: 19,
                                          text: templateFound,
                                          maxLines: 10,
                                          fontWeight: FontWeight.bold,
                                        )
                                  : SizedBox(),
                              doesEmailContain
                                  ? title == null
                                      ? TextFont(
                                          fontSize: 15,
                                          text: "Title: Not found.",
                                          maxLines: 10,
                                          fontWeight: FontWeight.bold,
                                        )
                                      : TextFont(
                                          fontSize: 15,
                                          text: "Title: " + title,
                                          maxLines: 10,
                                          fontWeight: FontWeight.bold,
                                        )
                                  : SizedBox(),
                              doesEmailContain
                                  ? amountDouble == null
                                      ? Padding(
                                          padding:
                                              const EdgeInsetsDirectional.only(
                                                  bottom: 8.0),
                                          child: TextFont(
                                            fontSize: 15,
                                            text:
                                                "Amount: Not found / invalid number.",
                                            maxLines: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : Padding(
                                          padding:
                                              const EdgeInsetsDirectional.only(
                                                  bottom: 8.0),
                                          child: TextFont(
                                            fontSize: 15,
                                            text: "Amount: " +
                                                convertToMoney(
                                                    Provider.of<AllWallets>(
                                                        context),
                                                    amountDouble),
                                            maxLines: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                  : SizedBox(),
                              TextFont(
                                fontSize: 13,
                                text: messageString,
                                maxLines: 10,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return Column(
            children: messageTxt,
          );
        } else {
          return Container(width: 100, height: 100, color: Colors.white);
        }
      },
    );
  }
}

String getEmailMessage(gMail.Message messageData) {
  String messageEncoded = messageData.payload?.parts?[0].body?.data ?? "";
  String messageString;
  if (messageEncoded == "") {
    gMail.MessagePart payload = messageData.payload!;
    try {
      String htmlString = utf8
          .decode(payload.body!.dataAsBytes)
          .replaceAll("[^\\x00-\\x7F]", "");
      String parsedString = parseHtmlString(htmlString);
      messageString = parsedString;
    } catch (e) {
      messageString = (messageData.snippet ?? "") +
          "\n\n" +
          "There was an error getting the rest of the email";
    }
  } else {
    messageString = parseHtmlString(utf8.decode(base64.decode(messageEncoded)));
  }
  return messageString
      .split(RegExp(r"[ \t\r\f\v]+"))
      .join(" ")
      .replaceAll(new RegExp(r'(?:[\t ]*(?:\r?\n|\r))+'), '\n\n')
      .replaceAll(RegExp(r"(?<=\n) +"), "");
}
