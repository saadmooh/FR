import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../services/ai_service.dart';
import '../services/backup_service.dart';
import '../services/auth_service.dart';
import '../services/revenuecat_service.dart';
import '../repositories/app_settings_repository.dart';
import '../core/app_theme.dart';
import '../core/locale_manager.dart';
import '../core/translations.dart';
import '../core/constants.dart';
import '../models/reminder.dart';
import '../models/free_time_slot.dart';

enum ExportFormat { json, excel }

class SettingsScreen extends StatefulWidget {
  final AIService aiService;
  final AppSettingsRepository settingsRepository;
  final AuthService authService;
  final RevenueCatService revenueCatService;

  const SettingsScreen({
    super.key,
    required this.aiService,
    required this.settingsRepository,
    required this.authService,
    required this.revenueCatService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  String _selectedProvider = 'google';
  String _selectedModel = '';
  bool _isTesting = false;
  bool _obscureText = true;

  final BackupService _backupService = BackupService();

  @override
  void initState() {
    super.initState();
    _selectedProvider = widget.aiService.getProvider();
    _selectedModel = widget.settingsRepository.getModel();
    final existingKey = widget.aiService.getApiKey();
    if (existingKey != null) {
      _apiKeyController.text = existingKey;
    }
  }

  String get _locale => LocaleManager.instance.getLocale();

  List<String> _getModelsForProvider(String provider) {
    return AppConstants.availableModels[provider] ?? [];
  }

  Widget _buildModelDropdown() {
    final models = _getModelsForProvider(_selectedProvider);
    final currentModel = _selectedModel.isEmpty && models.isNotEmpty
        ? models.first
        : _selectedModel;

    return DropdownButtonFormField<String>(
      initialValue: models.contains(currentModel) ? currentModel : null,
      dropdownColor: AppColors.whiteSurface,
      style: TextStyle(color: AppColors.whiteTextPrimary),
      decoration: InputDecoration(
        hintText: Translations.selectProvider(_locale),
        hintStyle: TextStyle(color: AppColors.whiteTextSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(
            color: AppColors.whiteTextSecondary.withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(
            color: AppColors.whiteTextSecondary.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(
            color: AppColors.whiteAccent,
            width: 2,
          ),
        ),
      ),
      items: models.map((m) {
        return DropdownMenuItem(
          value: m,
          child: Text(m),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() => _selectedModel = value);
        }
      },
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _testKey() async {
    setState(() => _isTesting = true);

    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      setState(() => _isTesting = false);
      _showResult(false, Translations.enterApiKey(_locale));
      return;
    }

    widget.aiService.setApiKey(key);
    final result = await widget.aiService.testApiKey();

    setState(() => _isTesting = false);
    _showResult(
      result['success'] == true,
      result['message'] ?? 'Unknown error',
    );
  }

  void _saveSettings() {
    final key = _apiKeyController.text.trim();
    if (key.isNotEmpty) {
      widget.aiService.setApiKey(key);
    }
    widget.settingsRepository.setProvider(_selectedProvider);
    widget.settingsRepository.setModel(_selectedModel);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Translations.settingsSaved(_locale)),
        backgroundColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
  }

  void _showResult(bool success, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? AppColors.accent : AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
  }

  Future<void> _exportData(ExportFormat format) async {
    try {
      final reminders = widget.settingsRepository
          .getReminderRepository()
          .getAll();
      final freeTimes = widget.settingsRepository
          .getFreeTimeRepository()
          .getAll();

      String fileName =
          'flex_reminder_backup_${DateTime.now().millisecondsSinceEpoch}';
      String content;

      if (format == ExportFormat.json) {
        content = _backupService.exportToJson(reminders, freeTimes);
        fileName += '.json';
      } else {
        final bytes = _backupService.exportToExcel(reminders, freeTimes);
        if (bytes.isEmpty) {
          _showMessage(false, Translations.exportFailed(_locale));
          return;
        }
        fileName += '.xlsx';
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles(
          [XFile(file.path)],
          text: AppConstants.appName,
        );
        _showMessage(true, Translations.exportedSuccessfully(_locale));
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(content);
      await Share.shareXFiles([XFile(file.path)], text: AppConstants.appName);
      _showMessage(true, Translations.exportedSuccessfully(_locale));
    } catch (e) {
      _showMessage(false, '${Translations.exportFailed(_locale)}: $e');
    }
  }

  Future<void> _importData() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'xlsx'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final path = file.path;
      if (path == null) return;

      List<Reminder> reminders = [];
      List<FreeTimeSlot> freeTimes = [];

      if (file.name.endsWith('.json')) {
        final content = await File(path).readAsString();
        final data = _backupService.importFromJson(content);
        reminders = data?['reminders'] ?? [];
        freeTimes = data?['freeTimes'] ?? [];
      } else if (file.name.endsWith('.xlsx')) {
        final bytes = await File(path).readAsBytes();
        final data = _backupService.importFromExcel(bytes);
        reminders = data?['reminders'] ?? [];
        freeTimes = data?['freeTimes'] ?? [];
      }

      final reminderRepo = widget.settingsRepository.getReminderRepository();
      final freeTimeRepo = widget.settingsRepository.getFreeTimeRepository();

      for (final reminder in reminders) {
        reminder.id = 0;
        reminderRepo.save(reminder);
      }

      for (final freeTime in freeTimes) {
        freeTime.id = 0;
        freeTimeRepo.save(freeTime);
      }

      _showMessage(
        true,
        '${reminders.length} ${Translations.remindersImported(_locale)} ${freeTimes.length} ${Translations.freeTimesImported(_locale)}',
      );
    } catch (e) {
      _showMessage(false, '${Translations.importFailed(_locale)}: $e');
    }
  }

  void _showMessage(bool success, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? AppColors.accent : AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.whiteSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          Translations.signOut(_locale),
          style: TextStyle(color: AppColors.whiteTextPrimary),
        ),
        content: Text(
          Translations.signOutConfirm(_locale),
          style: TextStyle(color: AppColors.whiteTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              Translations.cancel(_locale),
              style: TextStyle(color: AppColors.whiteTextSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.authService.signOut();
              if (mounted) {
                _showMessage(true, Translations.signOut(_locale));
              }
            },
            child: Text(
              Translations.signOut(_locale),
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showExportDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.whiteBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            Text(
              Translations.exportFormat(_locale),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.whiteTextPrimary,
                  ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.code, color: AppColors.whiteAccent),
              title: Text(Translations.json(_locale)),
              subtitle: Text(Translations.jsonFormatDesc(_locale)),
              onTap: () {
                Navigator.pop(context);
                _exportData(ExportFormat.json);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.table_chart, color: AppColors.whiteAccent),
              title: Text(Translations.excel(_locale)),
              subtitle: Text(Translations.excelFormatDesc(_locale)),
              onTap: () {
                Navigator.pop(context);
                _exportData(ExportFormat.excel);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = _locale;

    return Scaffold(
      backgroundColor: AppColors.whiteBackground,
      appBar: AppBar(
        backgroundColor: AppColors.whiteBackground,
        elevation: 0,
        title: Text(
          Translations.settings(locale),
          style: Theme.of(context).appBarTheme.titleTextStyle,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),

          _buildSectionHeader(
            Translations.aiProvider(locale),
            Icons.smart_toy_outlined,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.whiteSurface,
              borderRadius: BorderRadius.zero,
              boxShadow: [
                BoxShadow(
                  color: AppColors.whiteShadow,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Translations.aiProvider(locale),
                  style: TextStyle(
                    color: AppColors.whiteTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedProvider,
                  dropdownColor: AppColors.whiteSurface,
                  style: TextStyle(color: AppColors.whiteTextPrimary),
                  decoration: InputDecoration(
                    hintText: Translations.selectProvider(locale),
                    hintStyle:
                        TextStyle(color: AppColors.whiteTextSecondary),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(
                        color: AppColors.whiteTextSecondary.withValues(alpha: 0.3),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(
                        color: AppColors.whiteTextSecondary.withValues(alpha: 0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: const BorderSide(
                        color: AppColors.whiteAccent,
                        width: 2,
                      ),
                    ),
                  ),
                  items: AppConstants.availableProviders.map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text(
                        Translations.getProviderLabel(p, locale),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedProvider = value;
                        final models =
                            AppConstants.availableModels[value] ?? [];
                        _selectedModel =
                            models.isNotEmpty ? models.first : '';
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  Translations.model(locale),
                  style: TextStyle(
                    color: AppColors.whiteTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                _buildModelDropdown(),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _buildSectionHeader(Translations.apiKey(locale), Icons.key_outlined),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.whiteSurface,
              borderRadius: BorderRadius.zero,
              boxShadow: [
                BoxShadow(
                  color: AppColors.whiteShadow,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Translations.apiKey(locale),
                  style: TextStyle(
                    color: AppColors.whiteTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKeyController,
                  obscureText: _obscureText,
                  style: TextStyle(color: AppColors.whiteTextPrimary),
                  decoration: InputDecoration(
                    hintText: Translations.enterApiKey(locale),
                    hintStyle:
                        TextStyle(color: AppColors.whiteTextSecondary),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureText
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.whiteTextSecondary,
                      ),
                      onPressed: () =>
                          setState(() => _obscureText = !_obscureText),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(
                        color: AppColors.whiteTextSecondary.withValues(alpha: 0.3),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(
                        color: AppColors.whiteTextSecondary.withValues(alpha: 0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: const BorderSide(
                        color: AppColors.whiteAccent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isTesting ? null : _testKey,
                        icon: _isTesting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.play_arrow_outlined),
                        label: _isTesting
                            ? Text(Translations.aiRescheduling(locale))
                            : Text(Translations.testKey(locale)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.whiteAccent,
                          side: const BorderSide(
                            color: AppColors.whiteAccent,
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle:
                              const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveSettings,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(Translations.save(locale)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.whiteAccent,
                          foregroundColor: AppColors.whiteBackground,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          elevation: 2,
                          textStyle:
                              const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _buildSectionHeader(Translations.apiStatus(locale), Icons.info_outline),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.whiteSurface,
              borderRadius: BorderRadius.zero,
              boxShadow: [
                BoxShadow(
                  color: AppColors.whiteShadow,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  widget.aiService.hasApiKey()
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_outlined,
                  color: widget.aiService.hasApiKey()
                      ? AppColors.success
                      : AppColors.error,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.aiService.hasApiKey()
                        ? Translations.apiConnected(locale)
                        : Translations.apiNotConfigured(locale),
                    style: TextStyle(
                      color: AppColors.whiteTextPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: widget.aiService.hasApiKey()
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Text(
                    widget.aiService.hasApiKey()
                        ? Translations.active(locale)
                        : Translations.inactive(locale),
                    style: TextStyle(
                      color: widget.aiService.hasApiKey()
                          ? AppColors.success
                          : AppColors.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          _buildSectionHeader(Translations.account(locale), Icons.account_circle_outlined),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.whiteSurface,
              borderRadius: BorderRadius.zero,
              boxShadow: [
                BoxShadow(
                  color: AppColors.whiteShadow,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.person_outline,
                    color: AppColors.whiteAccent,
                  ),
                  title: Text(
                    widget.authService.currentUser?.displayName ?? 'User',
                    style: TextStyle(color: AppColors.whiteTextPrimary),
                  ),
                  subtitle: Text(
                    widget.authService.currentUser?.email ?? '',
                    style: TextStyle(color: AppColors.whiteTextSecondary),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.logout,
                    color: AppColors.error,
                  ),
                  title: Text(
                    Translations.signOut(_locale),
                    style: TextStyle(color: AppColors.whiteTextPrimary),
                  ),
                  onTap: _showSignOutDialog,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          _buildSectionHeader(Translations.backupRestore(locale), Icons.backup_outlined),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.whiteSurface,
              borderRadius: BorderRadius.zero,
              boxShadow: [
                BoxShadow(
                  color: AppColors.whiteShadow,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.upload_outlined,
                    color: AppColors.whiteAccent,
                  ),
                  title: Text(
                    Translations.exportData(locale),
                    style: TextStyle(color: AppColors.whiteTextPrimary),
                  ),
                  subtitle: Text(
                    Translations.exportDataSubtitle(locale),
                    style: TextStyle(color: AppColors.whiteTextSecondary),
                  ),
                  onTap: _showExportDialog,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.download_outlined,
                    color: AppColors.whiteAccent,
                  ),
                  title: Text(
                    Translations.importData(locale),
                    style: TextStyle(color: AppColors.whiteTextPrimary),
                  ),
                  subtitle: Text(
                    Translations.importDataSubtitle(locale),
                    style: TextStyle(color: AppColors.whiteTextSecondary),
                  ),
                  onTap: _importData,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Icon(icon, color: AppColors.whiteAccent, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: AppColors.whiteTextSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
