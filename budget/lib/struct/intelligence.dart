import 'dart:convert';
import 'package:budget/database/tables.dart';
import 'package:budget/struct/notificationCapture.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/walletAccountMatcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

const String intelligenceProviderOpenAICompatible = "openai-compatible";
const String intelligenceProviderGemini = "gemini";

const String defaultIntelligenceOpenAIBaseUrl =
    "https://api.openai.com/v1";
const String defaultIntelligenceGeminiBaseUrl =
    "https://generativelanguage.googleapis.com/v1beta";

class IntelligenceConfig {
  const IntelligenceConfig({
    required this.provider,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String provider;
  final String baseUrl;
  final String apiKey;
  final String model;

  bool get isConfigured => apiKey.trim().isNotEmpty && model.trim().isNotEmpty;
}

class IntelligenceModelOption {
  const IntelligenceModelOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class ReceiptImageSelection {
  const ReceiptImageSelection({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

class ReceiptLineItemAnalysis {
  const ReceiptLineItemAnalysis({
    required this.name,
    this.amount,
    this.quantity,
    this.suggestedCategoryName,
    this.notes,
  });

  final String name;
  final double? amount;
  final double? quantity;
  final String? suggestedCategoryName;
  final String? notes;

  factory ReceiptLineItemAnalysis.fromJson(Map<String, dynamic> json) {
    return ReceiptLineItemAnalysis(
      name: _stringFromJson(
            json["name"] ?? json["title"] ?? json["description"],
          ) ??
          "Item",
      amount: _doubleFromJson(json["amount"] ?? json["price"]),
      quantity: _doubleFromJson(json["quantity"]),
      suggestedCategoryName: _stringFromJson(
        json["suggestedCategoryName"] ?? json["category"],
      ),
      notes: _stringFromJson(json["notes"]),
    );
  }
}

class ReceiptAnalysis {
  const ReceiptAnalysis({
    this.merchantName,
    this.title,
    this.transactionDate,
    this.currencyCode,
    this.totalAmount,
    this.subtotalAmount,
    this.taxAmount,
    this.suggestedCategoryName,
    this.suggestedAccountName,
    this.reasoning,
    required this.lineItems,
  });

  final String? merchantName;
  final String? title;
  final DateTime? transactionDate;
  final String? currencyCode;
  final double? totalAmount;
  final double? subtotalAmount;
  final double? taxAmount;
  final String? suggestedCategoryName;
  final String? suggestedAccountName;
  final String? reasoning;
  final List<ReceiptLineItemAnalysis> lineItems;

  factory ReceiptAnalysis.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawLineItems = json["lineItems"] is List<dynamic>
        ? (json["lineItems"] as List<dynamic>)
        : json["items"] is List<dynamic>
            ? (json["items"] as List<dynamic>)
            : <dynamic>[];

    final List<ReceiptLineItemAnalysis> lineItems = rawLineItems
        .whereType<Map<String, dynamic>>()
        .map(ReceiptLineItemAnalysis.fromJson)
        .where((item) => item.name.trim().isNotEmpty)
        .toList();

    final double? parsedTotal =
        _doubleFromJson(json["totalAmount"] ?? json["total"]);

    return ReceiptAnalysis(
      merchantName:
          _stringFromJson(json["merchantName"] ?? json["merchant"]),
      title: _stringFromJson(json["title"]),
      transactionDate: _dateFromJson(
        json["transactionDate"] ?? json["date"] ?? json["receiptDate"],
      ),
      currencyCode:
          _stringFromJson(json["currencyCode"] ?? json["currency"]),
      totalAmount: parsedTotal ??
          _sumLineItemsIfPossible(
            lineItems,
          ),
      subtotalAmount:
          _doubleFromJson(json["subtotalAmount"] ?? json["subtotal"]),
      taxAmount: _doubleFromJson(json["taxAmount"] ?? json["tax"]),
      suggestedCategoryName: _stringFromJson(
        json["suggestedCategoryName"] ?? json["suggestedCategory"],
      ),
      suggestedAccountName: _stringFromJson(
        json["suggestedAccountName"] ?? json["suggestedWalletName"],
      ),
      reasoning: _stringFromJson(json["reasoning"]),
      lineItems: lineItems,
    );
  }
}

class NotificationTemplateAnalysis {
  const NotificationTemplateAnalysis({
    required this.canCreateTemplate,
    this.templateName,
    this.contains,
    this.titleTransactionBefore,
    this.titleTransactionAfter,
    this.amountTransactionBefore,
    this.amountTransactionAfter,
    this.extractedTitle,
    this.extractedAmount,
    this.direction,
    this.suggestedCategoryName,
    this.suggestedAccountName,
    this.reasoning,
    this.confidence,
  });

  final bool canCreateTemplate;
  final String? templateName;
  final String? contains;
  final String? titleTransactionBefore;
  final String? titleTransactionAfter;
  final String? amountTransactionBefore;
  final String? amountTransactionAfter;
  final String? extractedTitle;
  final double? extractedAmount;
  final NotificationTransactionDirection? direction;
  final String? suggestedCategoryName;
  final String? suggestedAccountName;
  final String? reasoning;
  final int? confidence;

  bool get hasTemplateSegments =>
      contains?.trim().isNotEmpty == true &&
      titleTransactionBefore != null &&
      titleTransactionAfter != null &&
      amountTransactionBefore != null &&
      amountTransactionAfter != null;

  factory NotificationTemplateAnalysis.fromJson(Map<String, dynamic> json) {
    final String? rawDirection =
        _stringFromJson(json["direction"])?.toLowerCase();
    return NotificationTemplateAnalysis(
      canCreateTemplate:
          json["canCreateTemplate"] == true || json["canParse"] == true,
      templateName: _stringFromJson(json["templateName"]),
      contains: _stringAllowEmptyFromJson(json["contains"]),
      titleTransactionBefore:
          _stringAllowEmptyFromJson(json["titleTransactionBefore"]),
      titleTransactionAfter:
          _stringAllowEmptyFromJson(json["titleTransactionAfter"]),
      amountTransactionBefore:
          _stringAllowEmptyFromJson(json["amountTransactionBefore"]),
      amountTransactionAfter:
          _stringAllowEmptyFromJson(json["amountTransactionAfter"]),
      extractedTitle: _stringFromJson(
        json["extractedTitle"] ?? json["title"],
      ),
      extractedAmount: _doubleFromJson(
        json["extractedAmount"] ?? json["amount"],
      ),
      direction: rawDirection == "income"
          ? NotificationTransactionDirection.income
          : rawDirection == "expense"
              ? NotificationTransactionDirection.expense
              : null,
      suggestedCategoryName: _stringFromJson(
        json["suggestedCategoryName"] ?? json["suggestedCategory"],
      ),
      suggestedAccountName: _stringFromJson(
        json["suggestedAccountName"] ?? json["suggestedWalletName"],
      ),
      reasoning: _stringFromJson(json["reasoning"]),
      confidence: _intFromJson(json["confidence"]),
    );
  }
}

class NotificationTransactionAnalysis {
  const NotificationTransactionAnalysis({
    required this.isTransaction,
    this.title,
    this.amount,
    this.direction,
    this.transactionDate,
    this.suggestedCategoryName,
    this.suggestedAccountName,
    this.reasoning,
    this.confidence,
  });

  final bool isTransaction;
  final String? title;
  final double? amount;
  final NotificationTransactionDirection? direction;
  final DateTime? transactionDate;
  final String? suggestedCategoryName;
  final String? suggestedAccountName;
  final String? reasoning;
  final int? confidence;

  factory NotificationTransactionAnalysis.fromJson(
    Map<String, dynamic> json,
  ) {
    final String? rawDirection =
        _stringFromJson(json["direction"])?.toLowerCase();
    return NotificationTransactionAnalysis(
      isTransaction:
          json["isTransaction"] == true || json["shouldSave"] == true,
      title: _stringFromJson(
        json["title"] ?? json["transactionTitle"] ?? json["merchantName"],
      ),
      amount: _doubleFromJson(json["amount"] ?? json["totalAmount"]),
      direction: rawDirection == "income"
          ? NotificationTransactionDirection.income
          : rawDirection == "expense"
              ? NotificationTransactionDirection.expense
              : null,
      transactionDate:
          _dateFromJson(json["transactionDate"] ?? json["date"]),
      suggestedCategoryName: _stringFromJson(
        json["suggestedCategoryName"] ?? json["suggestedCategory"],
      ),
      suggestedAccountName: _stringFromJson(
        json["suggestedAccountName"] ?? json["suggestedWalletName"],
      ),
      reasoning: _stringFromJson(json["reasoning"]),
      confidence: _intFromJson(json["confidence"]),
    );
  }
}

enum ReceiptCaptureSource {
  camera,
  gallery,
  file,
}

String getIntelligenceProviderLabel(String provider) {
  if (provider == intelligenceProviderGemini) return "Gemini API";
  return "OpenAI Compatible";
}

String maskSecret(String value) {
  if (value.trim().isEmpty) return "Not set";
  if (value.length <= 8) return "Set";
  return "${value.substring(0, 4)}...${value.substring(value.length - 4)}";
}

String getIntelligenceApiKeySettingKey(String provider) {
  if (provider == intelligenceProviderGemini) {
    return "intelligenceGeminiApiKey";
  }
  return "intelligenceOpenAIApiKey";
}

String getIntelligenceBaseUrlSettingKey(String provider) {
  if (provider == intelligenceProviderGemini) {
    return "intelligenceGeminiBaseUrl";
  }
  return "intelligenceOpenAIBaseUrl";
}

String getIntelligenceModelSettingKey(String provider) {
  if (provider == intelligenceProviderGemini) {
    return "intelligenceGeminiModel";
  }
  return "intelligenceOpenAIModel";
}

String getDefaultIntelligenceBaseUrl(String provider) {
  if (provider == intelligenceProviderGemini) {
    return defaultIntelligenceGeminiBaseUrl;
  }
  return defaultIntelligenceOpenAIBaseUrl;
}

String getCurrentIntelligenceProvider([Map<String, dynamic>? settings]) {
  final Map<String, dynamic> sourceSettings = settings ?? appStateSettings;
  final String provider =
      sourceSettings["intelligenceProvider"]?.toString() ??
          intelligenceProviderOpenAICompatible;
  if (provider == intelligenceProviderGemini) return provider;
  return intelligenceProviderOpenAICompatible;
}

String getConfiguredIntelligenceApiKey([Map<String, dynamic>? settings]) {
  final Map<String, dynamic> sourceSettings = settings ?? appStateSettings;
  final String provider = getCurrentIntelligenceProvider(sourceSettings);
  return sourceSettings[getIntelligenceApiKeySettingKey(provider)]?.toString() ??
      "";
}

String getConfiguredIntelligenceBaseUrl([Map<String, dynamic>? settings]) {
  final Map<String, dynamic> sourceSettings = settings ?? appStateSettings;
  final String provider = getCurrentIntelligenceProvider(sourceSettings);
  final String value =
      sourceSettings[getIntelligenceBaseUrlSettingKey(provider)]?.toString() ??
          "";
  if (value.trim().isEmpty) return getDefaultIntelligenceBaseUrl(provider);
  return value;
}

String getConfiguredIntelligenceModel([Map<String, dynamic>? settings]) {
  final Map<String, dynamic> sourceSettings = settings ?? appStateSettings;
  final String provider = getCurrentIntelligenceProvider(sourceSettings);
  return sourceSettings[getIntelligenceModelSettingKey(provider)]?.toString() ??
      "";
}

IntelligenceConfig getCurrentIntelligenceConfig([Map<String, dynamic>? settings]) {
  final Map<String, dynamic> sourceSettings = settings ?? appStateSettings;
  final String provider = getCurrentIntelligenceProvider(sourceSettings);
  return IntelligenceConfig(
    provider: provider,
    baseUrl: getConfiguredIntelligenceBaseUrl(sourceSettings),
    apiKey: getConfiguredIntelligenceApiKey(sourceSettings),
    model: getConfiguredIntelligenceModel(sourceSettings),
  );
}

TransactionCategory? matchReceiptCategory(
  String? suggestedCategoryName,
  List<TransactionCategory> categories,
) {
  if (suggestedCategoryName == null || suggestedCategoryName.trim().isEmpty) {
    return null;
  }

  final String suggested = _normalizeLookupValue(suggestedCategoryName);
  for (final TransactionCategory category in categories) {
    if (_normalizeLookupValue(category.name) == suggested) {
      return category;
    }
  }
  for (final TransactionCategory category in categories) {
    final String normalized = _normalizeLookupValue(category.name);
    if (normalized.contains(suggested) || suggested.contains(normalized)) {
      return category;
    }
  }
  return null;
}

TransactionWallet? matchReceiptWallet(
  String? suggestedWalletName,
  List<TransactionWallet> wallets,
) {
  if (suggestedWalletName == null || suggestedWalletName.trim().isEmpty) {
    return null;
  }

  final String suggested = _normalizeLookupValue(suggestedWalletName);
  for (final TransactionWallet wallet in wallets) {
    if (_normalizeLookupValue(wallet.name) == suggested) {
      return wallet;
    }
    for (final String tag in sanitizeWalletAccountTags(wallet.accountTags)) {
      final String normalizedTag = _normalizeLookupValue(tag);
      if (normalizedTag == suggested || suggested.contains(normalizedTag)) {
        return wallet;
      }
    }
  }
  for (final TransactionWallet wallet in wallets) {
    final String normalized = _normalizeLookupValue(wallet.name);
    if (normalized.contains(suggested) || suggested.contains(normalized)) {
      return wallet;
    }
    for (final String tag in sanitizeWalletAccountTags(wallet.accountTags)) {
      final String normalizedTag = _normalizeLookupValue(tag);
      if (normalizedTag.isNotEmpty &&
          (normalizedTag.contains(suggested) ||
              suggested.contains(normalizedTag))) {
        return wallet;
      }
    }
  }
  return null;
}

Future<List<IntelligenceModelOption>> fetchAvailableIntelligenceModels({
  IntelligenceConfig? config,
}) async {
  final IntelligenceConfig activeConfig = config ?? getCurrentIntelligenceConfig();
  if (activeConfig.apiKey.trim().isEmpty) {
    throw ("Set an API key before loading models.");
  }

  if (activeConfig.provider == intelligenceProviderGemini) {
    return _fetchGeminiModels(activeConfig);
  }
  return _fetchOpenAICompatibleModels(activeConfig);
}

Future<ReceiptAnalysis> analyzeReceiptImage({
  required ReceiptImageSelection image,
  required List<TransactionCategory> categories,
  required List<TransactionWallet> wallets,
  TransactionWallet? selectedWallet,
  IntelligenceConfig? config,
}) async {
  final IntelligenceConfig activeConfig = config ?? getCurrentIntelligenceConfig();
  if (activeConfig.apiKey.trim().isEmpty) {
    throw ("Configure an API key in Intelligence settings first.");
  }
  if (activeConfig.model.trim().isEmpty) {
    throw ("Select a model in Intelligence settings first.");
  }

  final List<TransactionCategory> suggestedCategories = categories
      .where((category) => category.income == false && category.categoryPk != "0")
      .toList();

  final String prompt = _buildReceiptPrompt(
    categories: suggestedCategories,
    wallets: wallets,
    selectedWallet: selectedWallet,
  );

  final String responseText;
  if (activeConfig.provider == intelligenceProviderGemini) {
    responseText = await _analyzeReceiptWithGemini(
      config: activeConfig,
      image: image,
      prompt: prompt,
    );
  } else {
    responseText = await _analyzeReceiptWithOpenAICompatible(
      config: activeConfig,
      image: image,
      prompt: prompt,
    );
  }

  final Map<String, dynamic> parsedJson = _extractJsonObject(responseText);
  return ReceiptAnalysis.fromJson(parsedJson);
}

Future<NotificationTemplateAnalysis> analyzeNotificationMessage({
  required String notificationMessage,
  required List<TransactionCategory> categories,
  required List<TransactionWallet> wallets,
  TransactionWallet? selectedWallet,
  IntelligenceConfig? config,
}) async {
  final IntelligenceConfig activeConfig = config ?? getCurrentIntelligenceConfig();
  if (activeConfig.apiKey.trim().isEmpty) {
    throw ("Configure an API key in Intelligence settings first.");
  }
  if (activeConfig.model.trim().isEmpty) {
    throw ("Select a model in Intelligence settings first.");
  }

  final String prompt = _buildNotificationTemplatePrompt(
    notificationMessage: notificationMessage,
    categories: categories,
    wallets: wallets,
    selectedWallet: selectedWallet,
  );

  const String systemPrompt =
      "You analyze financial notification text and return strict JSON only. "
      "All template boundary fields must be copied exactly from the source text with no paraphrasing.";

  final String responseText;
  if (activeConfig.provider == intelligenceProviderGemini) {
    responseText = await _analyzeTextWithGemini(
      config: activeConfig,
      prompt: "$systemPrompt\n\n$prompt",
    );
  } else {
    responseText = await _analyzeTextWithOpenAICompatible(
      config: activeConfig,
      systemPrompt: systemPrompt,
      prompt: prompt,
    );
  }

  final Map<String, dynamic> parsedJson = _extractJsonObject(responseText);
  return NotificationTemplateAnalysis.fromJson(parsedJson);
}

Future<NotificationTransactionAnalysis> analyzeNotificationTransaction({
  required String notificationMessage,
  required List<TransactionCategory> categories,
  required List<TransactionWallet> wallets,
  TransactionWallet? selectedWallet,
  IntelligenceConfig? config,
}) async {
  final IntelligenceConfig activeConfig = config ?? getCurrentIntelligenceConfig();
  if (activeConfig.apiKey.trim().isEmpty) {
    throw ("Configure an API key in Intelligence settings first.");
  }
  if (activeConfig.model.trim().isEmpty) {
    throw ("Select a model in Intelligence settings first.");
  }

  final String prompt = _buildNotificationTransactionPrompt(
    notificationMessage: notificationMessage,
    categories: categories,
    wallets: wallets,
    selectedWallet: selectedWallet,
  );

  const String systemPrompt =
      "You analyze financial notification text and return strict JSON only. "
      "Do not invent transactions or fields that are not supported by the notification text.";

  final String responseText;
  if (activeConfig.provider == intelligenceProviderGemini) {
    responseText = await _analyzeTextWithGemini(
      config: activeConfig,
      prompt: "$systemPrompt\n\n$prompt",
    );
  } else {
    responseText = await _analyzeTextWithOpenAICompatible(
      config: activeConfig,
      systemPrompt: systemPrompt,
      prompt: prompt,
    );
  }

  final Map<String, dynamic> parsedJson = _extractJsonObject(responseText);
  return NotificationTransactionAnalysis.fromJson(parsedJson);
}

Future<ReceiptImageSelection> pickReceiptImage({
  required ReceiptCaptureSource source,
}) async {
  if (source == ReceiptCaptureSource.file || kIsWeb) {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      throw ("No image selected.");
    }

    final PlatformFile file = result.files.single;
    final Uint8List? bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw ("Could not read the selected image.");
    }

    return ReceiptImageSelection(
      bytes: bytes,
      fileName: file.name,
      mimeType: _guessMimeType(file.name, bytes),
    );
  }

  final XFile? pickedImage = await ImagePicker().pickImage(
    source: source == ReceiptCaptureSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    imageQuality: 88,
    maxWidth: 2200,
  );

  if (pickedImage == null) {
    throw (source == ReceiptCaptureSource.camera
        ? "No photo taken."
        : "No image selected.");
  }

  final Uint8List bytes = await pickedImage.readAsBytes();
  if (bytes.isEmpty) {
    throw ("Could not read the selected image.");
  }

  return ReceiptImageSelection(
    bytes: bytes,
    fileName: pickedImage.name,
    mimeType: _guessMimeType(pickedImage.name, bytes),
  );
}

Future<List<IntelligenceModelOption>> _fetchOpenAICompatibleModels(
  IntelligenceConfig config,
) async {
  final Uri uri = Uri.parse(
    "${_normalizeBaseUrl(config.baseUrl)}/models",
  );
  final http.Response response = await http.get(
    uri,
    headers: <String, String>{
      "Authorization": "Bearer ${config.apiKey}",
      "Content-Type": "application/json",
    },
  );

  final Map<String, dynamic> decoded = _decodeJsonResponse(response);
  final List<dynamic> data = decoded["data"] is List<dynamic>
      ? decoded["data"] as List<dynamic>
      : <dynamic>[];

  final List<IntelligenceModelOption> models = data
      .whereType<Map<String, dynamic>>()
      .map((model) => IntelligenceModelOption(
            id: model["id"].toString(),
            label: model["id"].toString(),
          ))
      .toList()
    ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

  return models;
}

Future<List<IntelligenceModelOption>> _fetchGeminiModels(
  IntelligenceConfig config,
) async {
  final Uri uri = Uri.parse(
    "${_normalizeBaseUrl(config.baseUrl)}/models",
  ).replace(queryParameters: <String, String>{"key": config.apiKey});

  final http.Response response = await http.get(uri);
  final Map<String, dynamic> decoded = _decodeJsonResponse(response);
  final List<dynamic> rawModels = decoded["models"] is List<dynamic>
      ? decoded["models"] as List<dynamic>
      : <dynamic>[];

  final List<IntelligenceModelOption> models = rawModels
      .whereType<Map<String, dynamic>>()
      .where((model) {
        final String name = model["name"]?.toString() ?? "";
        final List<dynamic> supported =
            model["supportedGenerationMethods"] is List<dynamic>
                ? model["supportedGenerationMethods"] as List<dynamic>
                : <dynamic>[];
        return name.startsWith("models/gemini") &&
            supported.map((item) => item.toString()).contains("generateContent");
      })
      .map(
        (model) => IntelligenceModelOption(
          id: model["name"].toString(),
          label: model["displayName"]?.toString().trim().isNotEmpty == true
              ? "${model["displayName"]} (${model["name"]})"
              : model["name"].toString(),
        ),
      )
      .toList()
    ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

  return models;
}

Future<String> _analyzeReceiptWithOpenAICompatible({
  required IntelligenceConfig config,
  required ReceiptImageSelection image,
  required String prompt,
}) async {
  final Uri uri = Uri.parse(
    "${_normalizeBaseUrl(config.baseUrl)}/chat/completions",
  );

  final String imageData = base64Encode(image.bytes);
  final Map<String, dynamic> body = <String, dynamic>{
    "model": config.model,
    "temperature": 0.1,
    "messages": <Map<String, dynamic>>[
      <String, dynamic>{
        "role": "system",
        "content":
            "You read receipt images and return strict JSON with no markdown fences and no extra prose.",
      },
      <String, dynamic>{
        "role": "user",
        "content": <Map<String, dynamic>>[
          <String, dynamic>{
            "type": "text",
            "text": prompt,
          },
          <String, dynamic>{
            "type": "image_url",
            "image_url": <String, dynamic>{
              "url": "data:${image.mimeType};base64,$imageData",
            },
          },
        ],
      },
    ],
  };

  final http.Response response = await http.post(
    uri,
    headers: <String, String>{
      "Authorization": "Bearer ${config.apiKey}",
      "Content-Type": "application/json",
    },
    body: jsonEncode(body),
  );

  final Map<String, dynamic> decoded = _decodeJsonResponse(response);
  final List<dynamic> choices = decoded["choices"] is List<dynamic>
      ? decoded["choices"] as List<dynamic>
      : <dynamic>[];
  if (choices.isEmpty) {
    throw ("The AI provider returned an empty response.");
  }

  final dynamic message = (choices.first as Map<String, dynamic>)["message"];
  if (message is Map<String, dynamic>) {
    final dynamic content = message["content"];
    if (content is String && content.trim().isNotEmpty) {
      return content;
    }
  }

  throw ("The AI provider did not return usable receipt data.");
}

Future<String> _analyzeTextWithOpenAICompatible({
  required IntelligenceConfig config,
  required String systemPrompt,
  required String prompt,
}) async {
  final Uri uri = Uri.parse(
    "${_normalizeBaseUrl(config.baseUrl)}/chat/completions",
  );

  final Map<String, dynamic> body = <String, dynamic>{
    "model": config.model,
    "temperature": 0.1,
    "messages": <Map<String, dynamic>>[
      <String, dynamic>{
        "role": "system",
        "content": systemPrompt,
      },
      <String, dynamic>{
        "role": "user",
        "content": prompt,
      },
    ],
  };

  final http.Response response = await http.post(
    uri,
    headers: <String, String>{
      "Authorization": "Bearer ${config.apiKey}",
      "Content-Type": "application/json",
    },
    body: jsonEncode(body),
  );

  final Map<String, dynamic> decoded = _decodeJsonResponse(response);
  final List<dynamic> choices = decoded["choices"] is List<dynamic>
      ? decoded["choices"] as List<dynamic>
      : <dynamic>[];
  if (choices.isEmpty) {
    throw ("The AI provider returned an empty response.");
  }

  final dynamic message = (choices.first as Map<String, dynamic>)["message"];
  if (message is Map<String, dynamic>) {
    final dynamic content = message["content"];
    if (content is String && content.trim().isNotEmpty) {
      return content;
    }
    if (content is List<dynamic>) {
      final String combined = content
          .whereType<Map<String, dynamic>>()
          .map((part) => part["text"]?.toString() ?? "")
          .join("\n")
          .trim();
      if (combined.isNotEmpty) {
        return combined;
      }
    }
  }

  throw ("The AI provider did not return usable notification data.");
}

Future<String> _analyzeReceiptWithGemini({
  required IntelligenceConfig config,
  required ReceiptImageSelection image,
  required String prompt,
}) async {
  final String model = config.model.startsWith("models/")
      ? config.model
      : "models/${config.model}";
  final Uri uri = Uri.parse(
    "${_normalizeBaseUrl(config.baseUrl)}/$model:generateContent",
  ).replace(queryParameters: <String, String>{"key": config.apiKey});

  final Map<String, dynamic> body = <String, dynamic>{
    "contents": <Map<String, dynamic>>[
      <String, dynamic>{
        "parts": <Map<String, dynamic>>[
          <String, dynamic>{"text": prompt},
          <String, dynamic>{
            "inlineData": <String, dynamic>{
              "mimeType": image.mimeType,
              "data": base64Encode(image.bytes),
            },
          },
        ],
      },
    ],
    "generationConfig": <String, dynamic>{
      "temperature": 0.1,
      "responseMimeType": "application/json",
    },
  };

  final http.Response response = await http.post(
    uri,
    headers: <String, String>{"Content-Type": "application/json"},
    body: jsonEncode(body),
  );

  final Map<String, dynamic> decoded = _decodeJsonResponse(response);
  final List<dynamic> candidates = decoded["candidates"] is List<dynamic>
      ? decoded["candidates"] as List<dynamic>
      : <dynamic>[];
  if (candidates.isEmpty) {
    throw ("The Gemini API returned an empty response.");
  }

  final Map<String, dynamic>? content =
      (candidates.first as Map<String, dynamic>)["content"]
          as Map<String, dynamic>?;
  final List<dynamic> parts = content?["parts"] is List<dynamic>
      ? content!["parts"] as List<dynamic>
      : <dynamic>[];
  final String text = parts
      .whereType<Map<String, dynamic>>()
      .map((part) => part["text"]?.toString() ?? "")
      .join("\n")
      .trim();
  if (text.isEmpty) {
    throw ("The Gemini API did not return usable receipt data.");
  }
  return text;
}

Future<String> _analyzeTextWithGemini({
  required IntelligenceConfig config,
  required String prompt,
}) async {
  final String model = config.model.startsWith("models/")
      ? config.model
      : "models/${config.model}";
  final Uri uri = Uri.parse(
    "${_normalizeBaseUrl(config.baseUrl)}/$model:generateContent",
  ).replace(queryParameters: <String, String>{"key": config.apiKey});

  final Map<String, dynamic> body = <String, dynamic>{
    "contents": <Map<String, dynamic>>[
      <String, dynamic>{
        "parts": <Map<String, dynamic>>[
          <String, dynamic>{"text": prompt},
        ],
      },
    ],
    "generationConfig": <String, dynamic>{
      "temperature": 0.1,
      "responseMimeType": "application/json",
    },
  };

  final http.Response response = await http.post(
    uri,
    headers: <String, String>{"Content-Type": "application/json"},
    body: jsonEncode(body),
  );

  final Map<String, dynamic> decoded = _decodeJsonResponse(response);
  final List<dynamic> candidates = decoded["candidates"] is List<dynamic>
      ? decoded["candidates"] as List<dynamic>
      : <dynamic>[];
  if (candidates.isEmpty) {
    throw ("The Gemini API returned an empty response.");
  }

  final Map<String, dynamic>? content =
      (candidates.first as Map<String, dynamic>)["content"]
          as Map<String, dynamic>?;
  final List<dynamic> parts = content?["parts"] is List<dynamic>
      ? content!["parts"] as List<dynamic>
      : <dynamic>[];
  final String text = parts
      .whereType<Map<String, dynamic>>()
      .map((part) => part["text"]?.toString() ?? "")
      .join("\n")
      .trim();
  if (text.isEmpty) {
    throw ("The Gemini API did not return usable notification data.");
  }
  return text;
}

Map<String, dynamic> _decodeJsonResponse(http.Response response) {
  Map<String, dynamic> decodedBody = <String, dynamic>{};
  if (response.body.trim().isNotEmpty) {
    final dynamic decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      decodedBody = decoded;
    }
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    final dynamic error = decodedBody["error"];
    if (error is Map<String, dynamic>) {
      final String message =
          error["message"]?.toString() ?? "Request failed.";
      throw (message);
    }
    throw ("Request failed with status ${response.statusCode}.");
  }

  return decodedBody;
}

Map<String, dynamic> _extractJsonObject(String text) {
  String cleaned = text.trim();
  if (cleaned.startsWith("```") && cleaned.endsWith("```")) {
    cleaned = cleaned
        .replaceFirst(RegExp(r'^```[a-zA-Z0-9_-]*\n?'), '')
        .replaceFirst(RegExp(r'\n?```$'), '')
        .trim();
  }

  final int firstBrace = cleaned.indexOf("{");
  final int lastBrace = cleaned.lastIndexOf("}");
  if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
    cleaned = cleaned.substring(firstBrace, lastBrace + 1);
  }

  final dynamic decoded = jsonDecode(cleaned);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }

  throw ("The AI response was not valid receipt JSON.");
}

String _buildReceiptPrompt({
  required List<TransactionCategory> categories,
  required List<TransactionWallet> wallets,
  required TransactionWallet? selectedWallet,
}) {
  final StringBuffer buffer = StringBuffer()
    ..writeln(
      "Analyze this receipt image and return a single JSON object only.",
    )
    ..writeln(
      "Do not wrap the JSON in markdown. Do not add commentary.",
    )
    ..writeln(
      "Today is ${DateTime.now().toIso8601String().split('T').first}.",
    )
    ..writeln()
    ..writeln("Use this JSON shape exactly:")
    ..writeln("{")
    ..writeln('  "merchantName": string|null,')
    ..writeln('  "title": string|null,')
    ..writeln('  "transactionDate": "YYYY-MM-DD"|null,')
    ..writeln('  "currencyCode": string|null,')
    ..writeln('  "totalAmount": number|null,')
    ..writeln('  "subtotalAmount": number|null,')
    ..writeln('  "taxAmount": number|null,')
    ..writeln('  "suggestedCategoryName": string|null,')
    ..writeln('  "suggestedAccountName": string|null,')
    ..writeln('  "reasoning": string|null,')
    ..writeln('  "lineItems": [')
    ..writeln("    {")
    ..writeln('      "name": string,')
    ..writeln('      "amount": number|null,')
    ..writeln('      "quantity": number|null,')
    ..writeln('      "suggestedCategoryName": string|null,')
    ..writeln('      "notes": string|null')
    ..writeln("    }")
    ..writeln("  ]")
    ..writeln("}")
    ..writeln()
    ..writeln("Rules:")
    ..writeln(
      "- Use suggestedCategoryName only from the available categories below when you are confident. Otherwise return null.",
    )
    ..writeln(
      "- Use suggestedAccountName only from the available accounts below when you are confident. Otherwise return null.",
    )
    ..writeln(
      "- Prefer the merchant name for title unless the receipt clearly suggests a better transaction title.",
    )
    ..writeln(
      "- Include itemized lineItems when the receipt has readable item rows. If itemization is not visible, return an empty list.",
    )
    ..writeln(
      "- lineItems should contain purchasable items, not store metadata.",
    )
    ..writeln(
      "- Amounts must be positive numbers.",
    )
    ..writeln()
    ..writeln("Available categories:");

  for (final TransactionCategory category in categories) {
    buffer.writeln("- ${category.name}");
  }

  buffer
    ..writeln()
    ..writeln("Available accounts:");

  for (final TransactionWallet wallet in wallets) {
    buffer.writeln("- ${buildWalletMatchingContext(wallet)}");
  }

  if (selectedWallet != null) {
    buffer
      ..writeln()
      ..writeln(
        "Current selected account: ${buildWalletMatchingContext(selectedWallet)}",
      );
  }

  return buffer.toString();
}

String _buildNotificationTemplatePrompt({
  required String notificationMessage,
  required List<TransactionCategory> categories,
  required List<TransactionWallet> wallets,
  required TransactionWallet? selectedWallet,
}) {
  final StringBuffer buffer = StringBuffer()
    ..writeln(
      "Analyze this financial notification and return a single JSON object only.",
    )
    ..writeln("Do not wrap the JSON in markdown. Do not add commentary.")
    ..writeln(
      "Today is ${DateTime.now().toIso8601String().split('T').first}.",
    )
    ..writeln()
    ..writeln("Use this JSON shape exactly:")
    ..writeln("{")
    ..writeln('  "canCreateTemplate": boolean,')
    ..writeln('  "templateName": string|null,')
    ..writeln('  "contains": string|null,')
    ..writeln('  "titleTransactionBefore": string|null,')
    ..writeln('  "titleTransactionAfter": string|null,')
    ..writeln('  "amountTransactionBefore": string|null,')
    ..writeln('  "amountTransactionAfter": string|null,')
    ..writeln('  "extractedTitle": string|null,')
    ..writeln('  "extractedAmount": number|null,')
    ..writeln('  "direction": "expense"|"income"|null,')
    ..writeln('  "suggestedCategoryName": string|null,')
    ..writeln('  "suggestedAccountName": string|null,')
    ..writeln('  "reasoning": string|null,')
    ..writeln('  "confidence": number|null')
    ..writeln("}")
    ..writeln()
    ..writeln("Rules:")
    ..writeln(
      "- contains, titleTransactionBefore, titleTransactionAfter, amountTransactionBefore, and amountTransactionAfter must be copied exactly from the notification text below.",
    )
    ..writeln(
      "- Use \"\" for before/after values only when the field starts at the beginning or ends at the end of the notification text.",
    )
    ..writeln(
      "- contains should be a stable literal phrase that identifies similar notifications from the same app. Avoid amounts, dates, reference numbers, and masked account suffixes when possible.",
    )
    ..writeln(
      "- extractedTitle should be the merchant or transaction title to save in the budget app.",
    )
    ..writeln(
      "- extractedAmount must be a positive number with no currency symbols.",
    )
    ..writeln(
      "- direction must be expense for money leaving the account and income for money entering the account.",
    )
    ..writeln(
      "- suggestedCategoryName must be chosen only from the available categories below when confident. Otherwise return null.",
    )
    ..writeln(
      "- suggestedAccountName must be chosen only from the available accounts below when confident. Otherwise return null.",
    )
    ..writeln(
      "- Use account tags or masked account/card suffixes when they clearly map to one available account.",
    )
    ..writeln(
      "- If the notification is too ambiguous or does not have reusable structure, return canCreateTemplate=false and set template fields to null.",
    )
    ..writeln()
    ..writeln("Available categories:");

  for (final TransactionCategory category in categories) {
    buffer.writeln("- ${category.name}");
  }

  buffer
    ..writeln()
    ..writeln("Available accounts:");

  for (final TransactionWallet wallet in wallets) {
    buffer.writeln("- ${buildWalletMatchingContext(wallet)}");
  }

  if (selectedWallet != null) {
    buffer
      ..writeln()
      ..writeln(
        "Current selected account: ${buildWalletMatchingContext(selectedWallet)}",
      );
  }

  buffer
    ..writeln()
    ..writeln("Notification text:")
    ..writeln("<<<MESSAGE")
    ..writeln(notificationMessage)
    ..writeln("MESSAGE");

  return buffer.toString();
}

String _buildNotificationTransactionPrompt({
  required String notificationMessage,
  required List<TransactionCategory> categories,
  required List<TransactionWallet> wallets,
  required TransactionWallet? selectedWallet,
}) {
  final StringBuffer buffer = StringBuffer()
    ..writeln(
      "Analyze this notification and decide whether it describes a single completed financial transaction.",
    )
    ..writeln("Return a single JSON object only.")
    ..writeln("Do not wrap the JSON in markdown. Do not add commentary.")
    ..writeln(
      "Today is ${DateTime.now().toIso8601String().split('T').first}.",
    )
    ..writeln()
    ..writeln("Use this JSON shape exactly:")
    ..writeln("{")
    ..writeln('  "isTransaction": boolean,')
    ..writeln('  "title": string|null,')
    ..writeln('  "amount": number|null,')
    ..writeln('  "direction": "expense"|"income"|null,')
    ..writeln('  "transactionDate": "YYYY-MM-DD"|"YYYY-MM-DDTHH:MM:SS"|null,')
    ..writeln('  "suggestedCategoryName": string|null,')
    ..writeln('  "suggestedAccountName": string|null,')
    ..writeln('  "reasoning": string|null,')
    ..writeln('  "confidence": number|null')
    ..writeln("}")
    ..writeln()
    ..writeln("Rules:")
    ..writeln(
      "- Return isTransaction=false for OTPs, offers, reminders, balance summaries, low balance alerts, card controls, account statements, and any notification that does not describe one completed transaction.",
    )
    ..writeln(
      "- title should be the merchant, payee, sender, or source that should be saved as the transaction name.",
    )
    ..writeln(
      "- amount must be a positive number with no currency symbols.",
    )
    ..writeln(
      "- direction must be expense when money leaves the account and income when money enters the account.",
    )
    ..writeln(
      "- transactionDate must be null unless the notification explicitly provides the transaction date or time in a way that can be trusted.",
    )
    ..writeln(
      "- suggestedCategoryName must be chosen only from the available categories below when confident. Otherwise return null.",
    )
    ..writeln(
      "- suggestedAccountName must be chosen only from the available accounts below when confident. Otherwise return null.",
    )
    ..writeln(
      "- Use account tags or masked account/card suffixes when they clearly map to one available account.",
    )
    ..writeln(
      "- confidence should be 0 to 100 and reflect how certain you are that this is a single transaction and that the extracted fields are correct.",
    )
    ..writeln()
    ..writeln("Available categories:");

  for (final TransactionCategory category in categories) {
    buffer.writeln("- ${category.name}");
  }

  buffer
    ..writeln()
    ..writeln("Available accounts:");

  for (final TransactionWallet wallet in wallets) {
    final String currency = wallet.currency?.trim().isNotEmpty == true
        ? " (${wallet.currency})"
        : "";
    buffer.writeln("- ${wallet.name}$currency");
  }

  if (selectedWallet != null) {
    buffer
      ..writeln()
      ..writeln(
        "Current selected account: ${selectedWallet.name}${selectedWallet.currency == null ? '' : ' (${selectedWallet.currency})'}",
      );
  }

  buffer
    ..writeln()
    ..writeln("Notification text:")
    ..writeln("<<<MESSAGE")
    ..writeln(notificationMessage)
    ..writeln("MESSAGE");

  return buffer.toString();
}

String _normalizeBaseUrl(String value) {
  String normalized = value.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

String _guessMimeType(String fileName, Uint8List bytes) {
  final String lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return 'image/jpeg';
  }
  return 'image/jpeg';
}

String _normalizeLookupValue(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

String? _stringFromJson(dynamic value) {
  if (value == null) return null;
  final String text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') {
    return null;
  }
  return text;
}

String? _stringAllowEmptyFromJson(dynamic value) {
  if (value == null) return null;
  return value.toString();
}

double? _doubleFromJson(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();

  final String cleaned = value
      .toString()
      .replaceAll(RegExp(r'[^0-9,.-]'), '')
      .replaceAll(',', '');
  if (cleaned.trim().isEmpty) return null;
  return double.tryParse(cleaned);
}

int? _intFromJson(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString().trim());
}

DateTime? _dateFromJson(dynamic value) {
  final String? raw = _stringFromJson(value);
  if (raw == null) return null;
  return DateTime.tryParse(raw);
}

double? _sumLineItemsIfPossible(List<ReceiptLineItemAnalysis> items) {
  final List<double> values = items
      .map((item) => item.amount)
      .whereType<double>()
      .where((value) => value > 0)
      .toList();
  if (values.isEmpty) return null;
  return values.fold<double>(0, (sum, value) => sum + value);
}