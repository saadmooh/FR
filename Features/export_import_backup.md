# Feature: Export/Import Backup

## Overview

Allows users to export all reminders and settings to a JSON file for backup, and import previous backups to restore data. Essential for data portability and recovery.

## User Experience

### Export Flow
1. Settings → Export Backup
2. Select items to export (Reminders, Tags, Free Times, Settings)
3. Choose destination (Files app, Share)
4. File saved as `flex_reminder_backup_YYYYMMDD.json`

### Import Flow
1. Settings → Import Backup
2. Select JSON file from Files app
3. Preview data to import
4. Confirm merge/replace options
5. Import completes with summary

### Merge Options
- **Merge**: Add imported items alongside existing
- **Replace**: Clear existing and import fresh

## Implementation Guide

### 1. Create ExportModel

Create `lib/models/backup_data.dart`:

```dart
class BackupData {
  final String appVersion;
  final DateTime exportDate;
  final List<Reminder> reminders;
  final List<Tag> tags;
  final List<FreeTimeSlot> freeTimes;
  final Map<String, dynamic> settings;
  
  BackupData({
    required this.appVersion,
    required this.exportDate,
    required this.reminders,
    required this.tags,
    required this.freeTimes,
    required this.settings,
  });
  
  Map<String, dynamic> toJson() => {
    'appVersion': appVersion,
    'exportDate': exportDate.toIso8601String(),
    'reminders': reminders.map((r) => _reminderToJson(r)).toList(),
    'tags': tags.map((t) => _tagToJson(t)).toList(),
    'freeTimes': freeTimes.map((f) => _freeTimeToJson(f)).toList(),
    'settings': settings,
  };
  
  factory BackupData.fromJson(Map<String, dynamic> json) {
    return BackupData(
      appVersion: json['appVersion'] ?? '1.0.0',
      exportDate: DateTime.parse(json['exportDate']),
      reminders: (json['reminders'] as List)
          .map((r) => _reminderFromJson(r))
          .toList(),
      tags: (json['tags'] as List?)
          ?.map((t) => _tagFromJson(t))
          .toList() ?? [],
      freeTimes: (json['freeTimes'] as List?)
          ?.map((f) => _freeTimeFromJson(f))
          .toList() ?? [],
      settings: json['settings'] ?? {},
    );
  }
  
  static Map<String, dynamic> _reminderToJson(Reminder r) => {
    'url': r.url,
    'title': r.title,
    'description': r.description,
    'imageUrl': r.imageUrl,
    'categoryEn': r.categoryEn,
    'complexityEn': r.complexityEn,
    'importance': r.importance,
    'scheduledAt': r.scheduledAt.toIso8601String(),
    'createdAt': r.createdAt.toIso8601String(),
    'isOpened': r.isOpened,
    'openedAt': r.openedAt?.toIso8601String(),
  };
  
  // ... other serialization methods
}
```

### 2. Create BackupService

Create `lib/services/backup_service.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../core/constants.dart';

class BackupService {
  final ReminderRepository _reminderRepo;
  final TagRepository _tagRepo;
  final FreeTimeRepository _freeTimeRepo;
  final AppSettingsRepository _settingsRepo;

  BackupService(
    this._reminderRepo,
    this._tagRepo,
    this._freeTimeRepo,
    this._settingsRepo,
  );

  Future<BackupData> createBackup({
    bool includeReminders = true,
    bool includeTags = true,
    bool includeFreeTimes = true,
    bool includeSettings = true,
  }) async {
    return BackupData(
      appVersion: AppConstants.appVersion,
      exportDate: DateTime.now(),
      reminders: includeReminders ? _reminderRepo.getAll() : [],
      tags: includeTags ? _tagRepo.getAll() : [],
      freeTimes: includeFreeTimes ? _freeTimeRepo.getAll() : [],
      settings: includeSettings ? _getSettingsMap() : {},
    );
  }

  Map<String, dynamic> _getSettingsMap() {
    return {
      'apiKey': _settingsRepo.getApiKey(),
      'provider': _settingsRepo.getProvider(),
      'locale': _settingsRepo.getLocale(),
      'themeMode': _settingsRepo.getThemeMode(),
    };
  }

  Future<String> exportToFile(BackupData data) async {
    final json = jsonEncode(data.toJson());
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/flex_reminder_backup_$timestamp.json');
    await file.writeAsString(json);
    return file.path;
  }

  Future<void> shareBackup(String filePath) async {
    await Share.shareXFiles(
      [XFile(filePath)],
      subject: 'Flex Reminder Backup',
    );
  }

  Future<BackupData?> pickAndReadBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null || result.files.isEmpty) return null;

    final file = File(result.files.first.path!);
    final json = await file.readAsString();
    final data = BackupData.fromJson(jsonDecode(json));

    return data;
  }

  ImportResult importData(BackupData data, {bool merge = true}) {
    int remindersImported = 0;
    int tagsImported = 0;
    int freeTimesImported = 0;

    if (merge) {
      // Merge with existing
      for (final reminder in data.reminders) {
        _reminderRepo.save(reminder);
        remindersImported++;
      }
      for (final tag in data.tags) {
        _tagRepo.save(tag);
        tagsImported++;
      }
      for (final freeTime in data.freeTimes) {
        _freeTimeRepo.save(freeTime);
        freeTimesImported++;
      }
    } else {
      // Replace all
      _reminderRepo.deleteAll();
      _tagRepo.deleteAll();
      _freeTimeRepo.deleteAll();
      
      for (final reminder in data.reminders) {
        _reminderRepo.save(reminder);
        remindersImported++;
      }
      for (final tag in data.tags) {
        _tagRepo.save(tag);
        tagsImported++;
      }
      for (final freeTime in data.freeTimes) {
        _freeTimeRepo.save(freeTime);
        freeTimesImported++;
      }
    }

    return ImportResult(
      remindersImported: remindersImported,
      tagsImported: tagsImported,
      freeTimesImported: freeTimesImported,
    );
  }
}

class ImportResult {
  final int remindersImported;
  final int tagsImported;
  final int freeTimesImported;

  ImportResult({
    required this.remindersImported,
    required this.tagsImported,
    required this.freeTimesImported,
  });
}
```

### 3. Create BackupSettingsScreen

Create `lib/screens/backup_settings_screen.dart`:

```dart
class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> {
  bool _includeReminders = true;
  bool _includeTags = true;
  bool _includeFreeTimes = true;
  bool _includeSettings = true;
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.backupRestore),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Export Section
          _buildSectionHeader(t.export),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(t.reminders),
                  subtitle: Text('${_reminderRepo.getAll().length} items'),
                  value: _includeReminders,
                  onChanged: (v) => setState(() => _includeReminders = v),
                ),
                SwitchListTile(
                  title: Text(t.tags),
                  value: _includeTags,
                  onChanged: (v) => setState(() => _includeTags = v),
                ),
                SwitchListTile(
                  title: Text(t.freeTimes),
                  value: _includeFreeTimes,
                  onChanged: (v) => setState(() => _includeFreeTimes = v),
                ),
                SwitchListTile(
                  title: Text(t.settings),
                  value: _includeSettings,
                  onChanged: (v) => setState(() => _includeSettings = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isExporting ? null : _exportBackup,
            icon: _isExporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload),
            label: Text(t.exportBackup),
          ),

          const SizedBox(height: 32),

          // Import Section
          _buildSectionHeader(t.import),
          Card(
            child: ListTile(
              leading: const Icon(Icons.download),
              title: Text(t.importBackup),
              subtitle: Text(t.importDescription),
              onTap: _importBackup,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup() async {
    setState(() => _isExporting = true);

    try {
      final data = await backupService.createBackup(
        includeReminders: _includeReminders,
        includeTags: _includeTags,
        includeFreeTimes: _includeFreeTimes,
        includeSettings: _includeSettings,
      );

      final filePath = await backupService.exportToFile(data);
      await backupService.shareBackup(filePath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Translations.of(context).exportSuccess)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  Future<void> _importBackup() async {
    final data = await backupService.pickAndReadBackup();
    if (data == null) return;

    final result = await showDialog<ImportChoice>(
      context: context,
      builder: (context) => _ImportDialog(data: data),
    );

    if (result == null) return;

    final importResult = backupService.importData(
      data,
      merge: result == ImportChoice.merge,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Translations.of(context).importSuccess(
            importResult.remindersImported,
            importResult.tagsImported,
          )),
        ),
      );
    }
  }
}

enum ImportChoice { merge, replace }

class _ImportDialog extends StatelessWidget {
  final BackupData data;

  const _ImportDialog({required this.data});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return AlertDialog(
      title: Text(t.importBackup),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${data.reminders.length} ${t.reminders}'),
          Text('${data.freeTimes.length} ${t.freeTimes}'),
          const SizedBox(height: 16),
          Text(t.mergeOrReplace),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ImportChoice.merge),
          child: Text(t.merge),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, ImportChoice.replace),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: Text(t.replace),
        ),
      ],
    );
  }
}
```

### 4. Add to Settings Navigation

```dart
// In settings_screen.dart
ListTile(
  leading: const Icon(Icons.backup),
  title: Text(Translations.of(context).backupRestore),
  onTap: () => context.push('/backup'),
),
```

### 5. Add Dependencies

```yaml
dependencies:
  share_plus: ^7.0.0
  file_picker: ^6.0.0
  path_provider: ^2.1.0
```

### 6. Add Translations

```dart
String get backupRestore => 'Backup & Restore';
String get export => 'Export';
String get import => 'Import';
String get exportBackup => 'Export Backup';
String get importBackup => 'Import Backup';
String get importDescription => 'Restore from a previous backup';
String get exportSuccess => 'Backup exported successfully';
String get importSuccess => 'Imported {reminders} reminders and {tags} tags';
String get mergeOrReplace => 'How would you like to import?';
String get merge => 'Merge';
String get replace => 'Replace All';
```

## Dependencies

```yaml
dependencies:
  share_plus: ^7.0.0
  file_picker: ^6.0.0
  path_provider: ^2.1.0
  intl: ^0.19.0  # For date formatting
```

## Testing Checklist

- [ ] Export creates valid JSON file
- [ ] Share sheet opens with file
- [ ] Import reads JSON correctly
- [ ] Merge adds items without deleting
- [ ] Replace clears and imports
- [ ] Large backups (1000+ items) work
- [ ] Invalid JSON handled gracefully

## Edge Cases

1. **Corrupted backup**: Validate JSON structure before import
2. **Partial import**: Track failures, report summary
3. **Duplicate detection**: Use URL+title as unique key
4. **Large files**: Stream parsing for files > 10MB
5. **Missing fields**: Provide defaults for backward compatibility
