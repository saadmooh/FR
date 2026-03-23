import 'package:flutter/material.dart';
import '../services/ai_service.dart';
import '../services/backup_service.dart';
import '../repositories/app_settings_repository.dart';
import '../core/app_theme.dart';
import '../core/locale_manager.dart';
import '../core/translations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/reminder.dart';
import '../models/free_time_slot.dart';

class SettingsScreen extends StatefulWidget {
  final AIService aiService;
  final AppSettingsRepository settingsRepository;

  const SettingsScreen({
    super.key,
    required this.aiService,
    required this.settingsRepository,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  String _selectedProvider = 'google';
  bool _isTesting = false;
  bool _obscureText = true;

  final BackupService _backupService = BackupService();

  final List<Map<String, String>> _providers = [
    {'value': 'google', 'label': 'Google Gemini'},
    {'value': 'openai', 'label': 'OpenAI'},
    {'value': 'anthropic', 'label': 'Anthropic'},
    {'value': 'mistral', 'label': 'Mistral'},
    {'value': 'cohere', 'label': 'Cohere'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedProvider = widget.aiService.getProvider();
    final existingKey = widget.aiService.getApiKey();
    if (existingKey != null) {
      _apiKeyController.text = existingKey;
    }
  }

  String get _locale => LocaleManager.instance.getLocale();

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
      _showResult(false, 'Please enter an API key');
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Translations.settingsSaved(_locale)),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  void _showResult(bool success, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${success ? '✅' : '❌'} $message'),
        backgroundColor: success ? AppColors.success : AppColors.error,
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
          _showMessage(false, 'Export failed');
          return;
        }
        fileName += '.xlsx';
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([
          XFile(file.path),
        ], text: 'Flex Reminder Backup');
        _showMessage(true, 'Exported successfully');
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(content);
      await Share.shareXFiles([XFile(file.path)], text: 'Flex Reminder Backup');
      _showMessage(true, 'Exported successfully');
    } catch (e) {
      _showMessage(false, 'Export failed: $e');
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
        'Imported ${reminders.length} reminders and ${freeTimes.length} free times',
      );
    } catch (e) {
      _showMessage(false, 'Import failed: $e');
    }
  }

  void _showMessage(bool success, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? AppColors.success : AppColors.error,
      ),
    );
  }

  void _showExportDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.whiteSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            Text(
              'Export Format',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.whiteTextPrimary,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.code, color: AppColors.accent),
              title: const Text('JSON'),
              subtitle: const Text('Plain text format, easy to edit'),
              onTap: () {
                Navigator.pop(context);
                _exportData(ExportFormat.json);
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart, color: AppColors.accent),
              title: const Text('Excel'),
              subtitle: const Text('Spreadsheet format'),
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
        backgroundColor: AppColors.whiteSurface,
        elevation: 0,
        title: Text(
          Translations.settings(locale),
          style: TextStyle(
            color: AppColors.whiteTextPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 24,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),

          // AI Provider Section
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
                  color: Colors.black.withOpacity(0.08),
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
                  value: _selectedProvider,
                  dropdownColor: AppColors.whiteSurface,
                  style: TextStyle(color: AppColors.whiteTextPrimary),
                  decoration: InputDecoration(
                    hintText: Translations.selectProvider(locale),
                    hintStyle: TextStyle(color: AppColors.whiteTextSecondary),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(
                        color: AppColors.whiteTextSecondary.withOpacity(0.3),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(
                        color: AppColors.whiteTextSecondary.withOpacity(0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: const BorderSide(
                        color: AppColors.accent,
                        width: 2,
                      ),
                    ),
                  ),
                  items: _providers.map((p) {
                    return DropdownMenuItem(
                      value: p['value'],
                      child: Text(p['label']!),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedProvider = value);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // API Key Section
          _buildSectionHeader(Translations.apiKey(locale), Icons.key_outlined),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.whiteSurface,
              borderRadius: BorderRadius.zero,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
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
                    hintStyle: TextStyle(color: AppColors.whiteTextSecondary),
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
                        color: AppColors.whiteTextSecondary.withOpacity(0.3),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(
                        color: AppColors.whiteTextSecondary.withOpacity(0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: const BorderSide(
                        color: AppColors.accent,
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
                          foregroundColor: AppColors.accent,
                          side: const BorderSide(
                            color: AppColors.accent,
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
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
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 2,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Status Section
          _buildSectionHeader(
            Translations.apiStatus(locale),
            Icons.info_outline,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.whiteSurface,
              borderRadius: BorderRadius.zero,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: widget.aiService.hasApiKey()
                        ? AppColors.success.withOpacity(0.1)
                        : AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Text(
                    widget.aiService.hasApiKey() ? 'Active' : 'Inactive',
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

          // Backup Section
          _buildSectionHeader('Backup & Restore', Icons.backup_outlined),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.whiteSurface,
              borderRadius: BorderRadius.zero,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
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
                    color: AppColors.accent,
                  ),
                  title: Text(
                    'Export Data',
                    style: TextStyle(color: AppColors.whiteTextPrimary),
                  ),
                  subtitle: Text(
                    'Save reminders to JSON or Excel',
                    style: TextStyle(color: AppColors.whiteTextSecondary),
                  ),
                  onTap: _showExportDialog,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.download_outlined,
                    color: AppColors.accent,
                  ),
                  title: Text(
                    'Import Data',
                    style: TextStyle(color: AppColors.whiteTextPrimary),
                  ),
                  subtitle: Text(
                    'Restore from backup file',
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
          Icon(icon, color: AppColors.accent, size: 20),
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
