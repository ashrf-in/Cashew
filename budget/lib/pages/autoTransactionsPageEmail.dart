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
const Duration _notificationTemplateCacheTtl = Duration(seconds: 30);

final Map<String, DateTime> _recentNotificationFingerprints =
    <String, DateTime>{};
final Set<String> _notificationAiTemplateRequestsInFlight = <String>{};
List<ScannerTemplate> _notificationTemplateCache = <ScannerTemplate>[];
DateTime? _notificationTemplateCacheUpdatedAt;

class _ResolvedNotificationCategorySelection {
  const _ResolvedNotificationCategorySelection({
    this.mainCategory,
    this.subCategory,
  });

  final TransactionCategory? mainCategory;
  final TransactionCategory? subCategory;
}

class _NotificationTemplateResolution {
  const _NotificationTemplateResolution({
    required this.template,
    required this.extractedTitle,
    required this.amountDouble,
  });

  final ScannerTemplate template;
  final String? extractedTitle;
  final double? amountDouble;
}

class _NotificationDraft {
  const _NotificationDraft({
    required this.template,
    required this.packageName,
    required this.rawTitle,
    required this.title,
    required this.absoluteAmount,
    required this.signedAmount,
    required this.category,
    required this.subCategory,
    required this.wallet,
    required this.direction,
    required this.confidence,
    required this.createdTemplateWithAi,
    required this.hasLearnedValues,
    required this.hasAssociatedTitle,
    required this.usedFallbackCategory,
  });

  final ScannerTemplate template;
  final String? packageName;
  final String rawTitle;
  final String title;
  final double absoluteAmount;
  final double signedAmount;
  final TransactionCategory? category;
  final TransactionCategory? subCategory;
  final TransactionWallet? wallet;
  final NotificationTransactionDirection direction;
  final int confidence;
  final bool createdTemplateWithAi;
  final bool hasLearnedValues;
  final bool hasAssociatedTitle;
  final bool usedFallbackCategory;
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

Future<List<ScannerTemplate>> _getNotificationScannerTemplates(
    {bool forceRefresh = false}) async {
  final DateTime now = DateTime.now();
  if (!forceRefresh &&
      _notificationTemplateCacheUpdatedAt != null &&
      now.difference(_notificationTemplateCacheUpdatedAt!) <=
          _notificationTemplateCacheTtl &&
      _notificationTemplateCache.isNotEmpty) {
    return _notificationTemplateCache;
  }

  final List<ScannerTemplate> scannerTemplates =
      await database.getAllScannerTemplates();
  scannerTemplates.sort(
    (a, b) => b.contains.length.compareTo(a.contains.length),
  );
  _notificationTemplateCache = scannerTemplates;
  _notificationTemplateCacheUpdatedAt = now;
  return _notificationTemplateCache;
}

_NotificationTemplateResolution? _matchNotificationTemplate(
  String messageString,
  List<ScannerTemplate> scannerTemplates,
) {
  for (final ScannerTemplate scannerTemplate in scannerTemplates) {
    if (scannerTemplate.ignore || scannerTemplate.contains.trim().isEmpty) {
      continue;
    }
    if (!messageString.contains(scannerTemplate.contains)) {
      continue;
    }

    return _NotificationTemplateResolution(
      template: scannerTemplate,
      extractedTitle: getTransactionTitleFromEmail(
        messageString,
        scannerTemplate.titleTransactionBefore,
        scannerTemplate.titleTransactionAfter,
      ),
      amountDouble: getTransactionAmountFromEmail(
        messageString,
        scannerTemplate.amountTransactionBefore,
        scannerTemplate.amountTransactionAfter,
      ),
    );
  }
  return null;
}

String _normalizeNotificationTitleValue(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _buildAutomaticNotificationTemplateName(
  String? templateName,
  String? extractedTitle,
  String? packageName,
) {
  final String candidate = (templateName?.trim().isNotEmpty == true
          ? templateName!.trim()
          : extractedTitle?.trim().isNotEmpty == true
              ? extractedTitle!.trim()
              : packageName?.split('.').last.replaceAll('_', ' ').trim() ??
                  'Notification')
      .capitalizeFirst;
  final String output = 'AI $candidate';
  if (output.length <= 48) return output;
  return output.substring(0, 48).trim();
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

Future<TransactionCategory?> _getMainCategoryForTemplate(
  TransactionCategory? category,
) async {
  if (category == null) return null;
  if (category.mainCategoryPk?.trim().isNotEmpty == true) {
    return await database.getCategoryInstanceOrNull(category.mainCategoryPk!);
  }
  return category;
}

Future<ScannerTemplate?> _generateNotificationTemplateWithAi(
  String messageString, {
  required String? packageName,
}) async {
  final IntelligenceConfig intelligenceConfig = getCurrentIntelligenceConfig();
  if (!intelligenceConfig.isConfigured) return null;

  final String fingerprint = normalizeNotificationFingerprint(messageString);
  if (_notificationAiTemplateRequestsInFlight.contains(fingerprint)) {
    return null;
  }

  _notificationAiTemplateRequestsInFlight.add(fingerprint);
  try {
    final List<TransactionCategory> categories =
        await database.getAllCategories(includeSubCategories: true);
    final List<TransactionWallet> wallets = await database.getAllWallets();
    final TransactionWallet? selectedWallet = await database
        .getWalletInstanceOrNull(appStateSettings["selectedWalletPk"] ?? "0");

    final NotificationTemplateAnalysis analysis = await analyzeNotificationMessage(
      notificationMessage: messageString,
      categories: categories,
      wallets: wallets,
      selectedWallet: selectedWallet,
      config: intelligenceConfig,
    );

    if (!analysis.canCreateTemplate || !analysis.hasTemplateSegments) {
      return null;
    }

    final String? parsedTitle = getTransactionTitleFromEmail(
      messageString,
      analysis.titleTransactionBefore ?? '',
      analysis.titleTransactionAfter ?? '',
    );
    final double? parsedAmount = getTransactionAmountFromEmail(
      messageString,
      analysis.amountTransactionBefore ?? '',
      analysis.amountTransactionAfter ?? '',
    );
    if (parsedTitle == null || parsedAmount == null) return null;

    final String? aiExtractedTitle = analysis.extractedTitle;
    if (aiExtractedTitle?.trim().isNotEmpty == true) {
      final String normalizedParsedTitle =
          _normalizeNotificationTitleValue(parsedTitle);
      final String normalizedAiTitle =
          _normalizeNotificationTitleValue(aiExtractedTitle!);
      if (normalizedParsedTitle != normalizedAiTitle &&
          !normalizedParsedTitle.contains(normalizedAiTitle) &&
          !normalizedAiTitle.contains(normalizedParsedTitle)) {
        return null;
      }
    }

    TransactionCategory? matchedCategory =
        matchReceiptCategory(analysis.suggestedCategoryName, categories);
    final _ResolvedNotificationCategorySelection associatedSelection =
        await _findAssociatedNotificationCategorySelection(parsedTitle);
    matchedCategory ??=
        associatedSelection.subCategory ?? associatedSelection.mainCategory;

    final NotificationTransactionDirection direction = analysis.direction ??
        inferNotificationTransactionDirection(
          message: messageString,
          categoryIncome: matchedCategory?.income,
          parsedAmount: parsedAmount,
        );

    matchedCategory ??= await _getFallbackNotificationCategory(direction);
    final TransactionCategory? templateCategory =
        await _getMainCategoryForTemplate(matchedCategory);
    final TransactionWallet? matchedWallet =
        matchReceiptWallet(analysis.suggestedAccountName, wallets) ??
            selectedWallet;

    final List<ScannerTemplate> existingTemplates =
        await _getNotificationScannerTemplates();
    for (final ScannerTemplate scannerTemplate in existingTemplates) {
      if (scannerTemplate.contains == analysis.contains &&
          scannerTemplate.titleTransactionBefore ==
              analysis.titleTransactionBefore &&
          scannerTemplate.titleTransactionAfter ==
              analysis.titleTransactionAfter &&
          scannerTemplate.amountTransactionBefore ==
              analysis.amountTransactionBefore &&
          scannerTemplate.amountTransactionAfter ==
              analysis.amountTransactionAfter) {
        return scannerTemplate;
      }
    }

    final ScannerTemplate template = ScannerTemplate(
      scannerTemplatePk: '-1',
      dateCreated: DateTime.now(),
      dateTimeModified: null,
      templateName: _buildAutomaticNotificationTemplateName(
        analysis.templateName,
        parsedTitle,
        packageName,
      ),
      contains: analysis.contains!.trim(),
      titleTransactionBefore: analysis.titleTransactionBefore ?? '',
      titleTransactionAfter: analysis.titleTransactionAfter ?? '',
      amountTransactionBefore: analysis.amountTransactionBefore ?? '',
      amountTransactionAfter: analysis.amountTransactionAfter ?? '',
      defaultCategoryFk:
          (templateCategory ?? matchedCategory)?.categoryPk ?? '1',
      walletFk: matchedWallet?.walletPk ?? '-1',
      ignore: false,
    );

    await database.createOrUpdateScannerTemplate(template, insert: true);
    final List<ScannerTemplate> refreshedTemplates =
        await _getNotificationScannerTemplates(forceRefresh: true);
    for (final ScannerTemplate scannerTemplate in refreshedTemplates) {
      if (scannerTemplate.contains == template.contains &&
          scannerTemplate.titleTransactionBefore ==
              template.titleTransactionBefore &&
          scannerTemplate.titleTransactionAfter ==
              template.titleTransactionAfter &&
          scannerTemplate.amountTransactionBefore ==
              template.amountTransactionBefore &&
          scannerTemplate.amountTransactionAfter ==
              template.amountTransactionAfter) {
        return scannerTemplate;
      }
    }
    return null;
  } catch (e) {
    debugPrint('Notification AI template generation failed: $e');
    return null;
  } finally {
    _notificationAiTemplateRequestsInFlight.remove(fingerprint);
  }
}

Future<_NotificationDraft?> _buildNotificationDraft(
  String messageString, {
  bool allowAiTemplateCreation = false,
}) async {
  final String? packageName = extractNotificationPackageName(messageString);
  List<ScannerTemplate> scannerTemplates =
      await _getNotificationScannerTemplates();
  _NotificationTemplateResolution? templateResolution =
      _matchNotificationTemplate(messageString, scannerTemplates);
  bool createdTemplateWithAi = false;

  if (templateResolution == null && allowAiTemplateCreation) {
    final ScannerTemplate? aiTemplate = await _generateNotificationTemplateWithAi(
      messageString,
      packageName: packageName,
    );
    if (aiTemplate != null) {
      createdTemplateWithAi = true;
      scannerTemplates = await _getNotificationScannerTemplates(forceRefresh: true);
      templateResolution = _NotificationTemplateResolution(
        template: aiTemplate,
        extractedTitle: getTransactionTitleFromEmail(
          messageString,
          aiTemplate.titleTransactionBefore,
          aiTemplate.titleTransactionAfter,
        ),
        amountDouble: getTransactionAmountFromEmail(
          messageString,
          aiTemplate.amountTransactionBefore,
          aiTemplate.amountTransactionAfter,
        ),
      );
      if (templateResolution.extractedTitle == null ||
          templateResolution.amountDouble == null) {
        templateResolution = _matchNotificationTemplate(messageString, scannerTemplates);
      }
    }
  }

  if (templateResolution == null ||
      templateResolution.extractedTitle == null ||
      templateResolution.amountDouble == null) {
    return null;
  }

  final String rawTitle = templateResolution.extractedTitle!;
  final NotificationLearningSuggestion learnedSuggestion =
      getNotificationLearningSuggestion(
    packageName: packageName,
    rawTitle: rawTitle,
  );

  final String title =
      learnedSuggestion.canonicalTitle?.trim().isNotEmpty == true
          ? learnedSuggestion.canonicalTitle!.trim()
          : rawTitle;

  final _ResolvedNotificationCategorySelection learnedCategorySelection =
      await _resolveNotificationCategorySelectionFromPks(
    categoryPk: learnedSuggestion.categoryPk,
    subCategoryPk: learnedSuggestion.subCategoryPk,
  );

  _ResolvedNotificationCategorySelection associatedTitleSelection =
      await _findAssociatedNotificationCategorySelection(title);
  if (associatedTitleSelection.mainCategory == null && title != rawTitle) {
    associatedTitleSelection =
        await _findAssociatedNotificationCategorySelection(rawTitle);
  }

  final TransactionCategory? templateCategoryInstance =
      await database.getCategoryInstanceOrNull(
    templateResolution.template.defaultCategoryFk,
  );
  final NotificationTransactionDirection direction =
      inferNotificationTransactionDirection(
    message: messageString,
    categoryIncome: learnedCategorySelection.mainCategory?.income ??
        associatedTitleSelection.mainCategory?.income ??
        templateCategoryInstance?.income,
    parsedAmount: templateResolution.amountDouble,
  );
  final TransactionCategory? fallbackCategory =
      templateCategoryInstance ?? await _getFallbackNotificationCategory(direction);
  final _ResolvedNotificationCategorySelection templateCategorySelection =
      await _resolveNotificationCategorySelection(fallbackCategory);

  final TransactionCategory? category = learnedCategorySelection.mainCategory ??
      associatedTitleSelection.mainCategory ??
      templateCategorySelection.mainCategory;
  final TransactionCategory? subCategory = learnedCategorySelection.subCategory ??
      associatedTitleSelection.subCategory;

  TransactionWallet? wallet;
  final String? learnedWalletPk =
      learnedSuggestion.walletPk ?? learnedSuggestion.packageWalletPk;
  if (learnedWalletPk?.trim().isNotEmpty == true) {
    wallet = await database.getWalletInstanceOrNull(learnedWalletPk!);
  }
  wallet ??= templateResolution.template.walletFk == '-1'
      ? null
      : await database.getWalletInstanceOrNull(templateResolution.template.walletFk);
  wallet ??= await database
      .getWalletInstanceOrNull(appStateSettings['selectedWalletPk'] ?? '0');

  final bool usedFallbackCategory = learnedCategorySelection.mainCategory == null &&
      associatedTitleSelection.mainCategory == null;
  final double signedAmount = applyNotificationDirectionToAmount(
    amount: templateResolution.amountDouble!,
    direction: direction,
  );
  final int confidence = scoreNotificationConfidence(
    hasTemplate: true,
    hasParsedTitle: true,
    hasParsedAmount: true,
    hasResolvedCategory: category != null,
    hasResolvedWallet: wallet != null,
    hasLearnedValues:
        learnedSuggestion.hasLearnedValues || createdTemplateWithAi,
    hasAssociatedTitle: associatedTitleSelection.mainCategory != null,
    usedFallbackCategory: usedFallbackCategory,
  );

  return _NotificationDraft(
    template: templateResolution.template,
    packageName: packageName,
    rawTitle: rawTitle,
    title: title,
    absoluteAmount: templateResolution.amountDouble!.abs(),
    signedAmount: signedAmount,
    category: category,
    subCategory: subCategory,
    wallet: wallet,
    direction: direction,
    confidence: confidence,
    createdTemplateWithAi: createdTemplateWithAi,
    hasLearnedValues: learnedSuggestion.hasLearnedValues,
    hasAssociatedTitle: associatedTitleSelection.mainCategory != null,
    usedFallbackCategory: usedFallbackCategory,
  );
}

Future<Transaction?> _autoCreateNotificationTransaction(
  _NotificationDraft draft, {
  DateTime? dateTime,
}) async {
  if (draft.category == null) return null;

  final String walletPk =
      draft.wallet?.walletPk ?? appStateSettings['selectedWalletPk'] ?? '0';
  final int? rowId = await database.createOrUpdateTransaction(
    Transaction(
      transactionPk: '-1',
      name: draft.title,
      amount: draft.signedAmount,
      note: '',
      categoryFk: draft.category!.categoryPk,
      subCategoryFk: draft.subCategory?.categoryPk,
      walletFk: walletPk,
      dateCreated: dateTime ?? DateTime.now(),
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
  if (event.hasRemoved == true) return;

  final packageName = event.packageName ?? '';
  final String notificationText =
      [event.title ?? '', event.content ?? ''].join('\n').trim();

  // Only process notifications from banking/payment/wallet apps
  if (!_isFinancialNotification(packageName, notificationText)) return;

  final String fingerprint = normalizeNotificationFingerprint(
    [packageName, event.title ?? '', event.content ?? ''].join(' | '),
  );
  if (_shouldIgnoreDuplicateNotification(fingerprint)) return;

  final String messageString = getNotificationMessage(event);
  _storeRecentCapturedNotification(messageString);
  await queueTransactionFromMessage(
    messageString,
    willPushRoute: false,
    allowAutoCreate: true,
    allowAiTemplateCreation: true,
    dateTime: DateTime.now(),
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
      bool allowAiTemplateCreation = false,
      DateTime? dateTime,
    }) async {
  final _NotificationDraft? draft = await _buildNotificationDraft(
    messageString,
    allowAiTemplateCreation: allowAiTemplateCreation,
  );
  if (draft == null) return false;

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
      dateTime: dateTime,
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
        selectedCategory: draft.category,
        selectedSubCategory: draft.subCategory,
        startInitialAddTransactionSequence: false,
        selectedWallet: draft.wallet,
        selectedDate: dateTime,
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
  String output = "";
  output = output + "Package name: " + event.packageName.toString() + "\n";
  output =
      output + "Notification removed: " + event.hasRemoved.toString() + "\n";
  output = output + "\n----\n\n";
  output = output + "Notification Title: " + event.title.toString() + "\n\n";
  output = output + "Notification Content: " + event.content.toString();
  return output;
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
                "Transactions can be captured instantly from supported financial notifications. Cashew can also learn new notification formats automatically with Intelligence.",
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
              "When a supported financial app posts a notification, Cashew will try to parse it immediately, auto-learn the format when needed, and send a confirmation notification for captured transactions.",
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
                ? "AI auto-template learning is active. If a supported financial app sends a new notification format, Cashew will try to create a reusable parsing template automatically."
                : "Configure Intelligence in Settings to let Cashew learn new financial notification formats automatically when no template matches.",
            fontSize: 13,
            maxLines: 6,
            textColor: Colors.grey,
          ),
        ),
        StreamBuilder<List<ScannerTemplate>>(
          stream: database.watchAllScannerTemplates(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              if (snapshot.data!.length <= 0) {
                return Padding(
                  padding: const EdgeInsetsDirectional.all(5),
                  child: StatusBox(
                    title: "No Notification Templates Yet",
                    description: intelligenceConfig.isConfigured
                        ? "Cashew will try to learn the first supported notification format automatically. You can still add templates manually below."
                        : "Add a template manually, or configure Intelligence so Cashew can learn notification formats automatically.",
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.auto_awesome_outlined
                        : Icons.auto_awesome_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                );
              }
              return Column(
                children: [
                  for (ScannerTemplate scannerTemplate in snapshot.data!)
                    ScannerTemplateEntry(
                      messagesList: recentCapturedNotifications,
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
            messagesList: recentCapturedNotifications,
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
                "Notifications from these apps will always be processed, in addition to the built-in banking app list.",
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
