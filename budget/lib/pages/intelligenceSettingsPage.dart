import 'package:budget/functions.dart';
import 'package:budget/struct/intelligence.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/radioItems.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class IntelligenceSettingsPage extends StatefulWidget {
  const IntelligenceSettingsPage({super.key});

  @override
  State<IntelligenceSettingsPage> createState() =>
      _IntelligenceSettingsPageState();
}

class _IntelligenceSettingsPageState extends State<IntelligenceSettingsPage> {
  String get activeProvider => getCurrentIntelligenceProvider();

  String get activeApiKey =>
      appStateSettings[getIntelligenceApiKeySettingKey(activeProvider)]
              ?.toString() ??
          "";

  String get activeBaseUrl => getConfiguredIntelligenceBaseUrl();

  String get activeModel =>
      appStateSettings[getIntelligenceModelSettingKey(activeProvider)]
              ?.toString() ??
          "";

  Future<void> _editTextSetting({
    required String title,
    required String initialValue,
    required String settingKey,
    bool obscureText = false,
    String? placeholder,
  }) async {
    final TextEditingController controller =
        TextEditingController(text: initialValue);
    await openBottomSheet(
      context,
      popupWithKeyboard: true,
      PopupFramework(
        title: title,
        child: Column(
          children: [
            TextInput(
              controller: controller,
              labelText: placeholder ?? title,
              obscureText: obscureText,
              autoFocus: true,
              padding: EdgeInsetsDirectional.zero,
              icon: obscureText
                  ? (appStateSettings["outlinedIcons"]
                      ? Icons.key_outlined
                      : Icons.key_rounded)
                  : (appStateSettings["outlinedIcons"]
                      ? Icons.tune_outlined
                      : Icons.tune_rounded),
              onEditingComplete: () async {
                await updateSettings(
                  settingKey,
                  controller.text.trim(),
                  updateGlobalState: false,
                );
                if (mounted) {
                  setState(() {});
                }
                popRoute(context);
              },
            ),
            SizedBox(height: 14),
            Button(
              label: "Save",
              onTap: () async {
                await updateSettings(
                  settingKey,
                  controller.text.trim(),
                  updateGlobalState: false,
                );
                if (mounted) {
                  setState(() {});
                }
                popRoute(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openModelPicker() async {
    final IntelligenceConfig config = getCurrentIntelligenceConfig();
    if (config.apiKey.trim().isEmpty) {
      openSnackbar(
        SnackbarMessage(
          title: "Missing API Key",
          description: "Add an API key before loading models.",
          icon: appStateSettings["outlinedIcons"]
              ? Icons.warning_outlined
              : Icons.warning_rounded,
        ),
      );
      return;
    }

    final dynamic result = await openLoadingPopupTryCatch(
      () async {
        return await fetchAvailableIntelligenceModels(config: config);
      },
      onError: (error) {
        openSnackbar(
          SnackbarMessage(
            title: "Could Not Load Models",
            description: error.toString(),
            icon: appStateSettings["outlinedIcons"]
                ? Icons.error_outline
                : Icons.error_rounded,
          ),
        );
      },
    );

    if (result is! List<IntelligenceModelOption> || result.isEmpty) {
      openSnackbar(
        SnackbarMessage(
          title: "No Models Found",
          description:
              "The provider did not return any selectable models for this configuration.",
          icon: appStateSettings["outlinedIcons"]
              ? Icons.info_outline
              : Icons.info_rounded,
        ),
      );
      return;
    }

    await openBottomSheet(
      context,
      PopupFramework(
        title: "Select Model",
        subtitle: "Choose a vision-capable model for receipt images.",
        child: RadioItems(
          items: result.map((model) => model.id).toList(),
          initial: activeModel,
          displayFilter: (value) {
            final IntelligenceModelOption option =
                result.firstWhere((model) => model.id == value);
            return option.label;
          },
          onChanged: (value) async {
            await updateSettings(
              getIntelligenceModelSettingKey(activeProvider),
              value,
              updateGlobalState: false,
            );
            if (mounted) {
              setState(() {});
            }
            popRoute(context);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "Intelligence",
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      listWidgets: [
        SettingsContainer(
          title: "Receipt Intelligence",
          description:
              "Configure an OpenAI-compatible or Gemini model for receipt parsing. Use a multimodal model with image support. API keys are stored locally on this device.",
          icon: appStateSettings["outlinedIcons"]
              ? Icons.auto_awesome_outlined
              : Icons.auto_awesome_rounded,
        ),
        SettingsHeader(title: "Provider"),
        SettingsContainerDropdown(
          title: "AI Provider",
          icon: appStateSettings["outlinedIcons"]
              ? Icons.hub_outlined
              : Icons.hub_rounded,
          initial: activeProvider,
          items: const [
            intelligenceProviderOpenAICompatible,
            intelligenceProviderGemini,
          ],
          onChanged: (value) async {
            await updateSettings(
              "intelligenceProvider",
              value,
              updateGlobalState: false,
            );
            if (mounted) {
              setState(() {});
            }
          },
          getLabel: getIntelligenceProviderLabel,
        ),
        SettingsContainer(
          title: "Base URL",
          description: activeBaseUrl,
          icon: appStateSettings["outlinedIcons"]
              ? Icons.link_outlined
              : Icons.link_rounded,
          onTap: () {
            _editTextSetting(
              title: "Set Base URL",
              initialValue: activeBaseUrl,
              settingKey: getIntelligenceBaseUrlSettingKey(activeProvider),
              placeholder: getDefaultIntelligenceBaseUrl(activeProvider),
            );
          },
        ),
        SettingsContainer(
          title: "API Key",
          description:
              "Stored value: ${maskSecret(activeApiKey)}${kIsWeb ? ' | Web builds expose client-side keys.' : ''}",
          icon: appStateSettings["outlinedIcons"]
              ? Icons.key_outlined
              : Icons.key_rounded,
          onTap: () {
            _editTextSetting(
              title: "Set API Key",
              initialValue: activeApiKey,
              settingKey: getIntelligenceApiKeySettingKey(activeProvider),
              obscureText: true,
              placeholder: "Paste API key",
            );
          },
        ),
        SettingsContainer(
          title: "Selected Model",
          description: activeModel.trim().isEmpty
              ? "No model selected. Load models or enter one manually."
              : activeModel,
          icon: appStateSettings["outlinedIcons"]
              ? Icons.smart_toy_outlined
              : Icons.smart_toy_rounded,
          onTap: _openModelPicker,
        ),
        SettingsContainer(
          title: "Set Model Manually",
          description:
              "Use this if your provider supports a custom or private model id.",
          icon: appStateSettings["outlinedIcons"]
              ? Icons.edit_outlined
              : Icons.edit_rounded,
          onTap: () {
            _editTextSetting(
              title: "Set Model",
              initialValue: activeModel,
              settingKey: getIntelligenceModelSettingKey(activeProvider),
              placeholder: "Model id",
            );
          },
        ),
        SettingsContainer(
          title: "Load Available Models",
          description:
              "Fetch the current model list from the active provider and choose one.",
          icon: appStateSettings["outlinedIcons"]
              ? Icons.refresh_outlined
              : Icons.refresh_rounded,
          onTap: _openModelPicker,
        ),
        SettingsHeader(title: "Notes"),
        SettingsContainer(
          title: "How Receipt Parsing Works",
          description:
              "Receipt images are sent directly from the app to the configured provider. The AI returns merchant, date, currency, tax, total, and optional itemized lines so Cashew can fill one draft or create split transactions.",
          icon: appStateSettings["outlinedIcons"]
              ? Icons.receipt_long_outlined
              : Icons.receipt_long_rounded,
        ),
      ],
    );
  }
}