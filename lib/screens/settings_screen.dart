import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';
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
  final AppSettingsRepository settingsRepository;
  final AuthService authService;
  final RevenueCatService revenueCatService;

  const SettingsScreen({
    super.key,
    required this.settingsRepository,
    required this.authService,
    required this.revenueCatService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final BackupService _backupService = BackupService();

  String get _locale => LocaleManager.instance.getLocale();

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
                context.go('/login');
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

          ListenableBuilder(
            listenable: widget.revenueCatService,
            builder: (context, _) {
              if (widget.revenueCatService.isPremium) {
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  _buildSectionHeader(
                    Translations.upgradeToPremium(locale),
                    Icons.workspace_premium_outlined,
                  ),
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
                    child: ListTile(
                      leading: const Icon(
                        Icons.workspace_premium,
                        color: AppColors.whiteAccent,
                      ),
                      title: Text(
                        Translations.upgradeToPremium(locale),
                        style: TextStyle(color: AppColors.whiteTextPrimary),
                      ),
                      subtitle: Text(
                        Translations.premiumSubtitle(locale),
                        style: TextStyle(color: AppColors.whiteTextSecondary),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.whiteTextSecondary,
                      ),
                      onTap: () => context.push('/paywall'),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              );
            },
          ),

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
