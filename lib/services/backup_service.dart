import 'dart:convert';
import 'package:excel/excel.dart';
import '../models/reminder.dart';
import '../models/free_time_slot.dart';

enum ExportFormat { json, excel }

class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  String exportToJson(List<Reminder> reminders, List<FreeTimeSlot> freeTimes) {
    try {
      final Map<String, dynamic> data = {
        'reminders': reminders.map((r) => reminderToJson(r)).toList(),
        'freeTimes': freeTimes.map((f) => freeTimeToJson(f)).toList(),
        'exportedAt': DateTime.now().toIso8601String(),
        'version': '1.0',
      };
      return jsonEncode(data);
    } catch (e) {
      return '';
    }
  }

  List<int> exportToExcel(
    List<Reminder> reminders,
    List<FreeTimeSlot> freeTimes,
  ) {
    try {
      final Excel excel = Excel.createExcel();
      excel.delete('Sheet1');

      final Sheet remindersSheet = excel['Reminders'];
      _buildRemindersSheet(remindersSheet, reminders);

      final Sheet freeTimesSheet = excel['FreeTimes'];
      _buildFreeTimesSheet(freeTimesSheet, freeTimes);

      return excel.encode() ?? [];
    } catch (e) {
      return [];
    }
  }

  void _buildRemindersSheet(Sheet sheet, List<Reminder> reminders) {
    final headers = [
      TextCellValue('id'),
      TextCellValue('title'),
      TextCellValue('url'),
      TextCellValue('description'),
      TextCellValue('category'),
      TextCellValue('complexity'),
      TextCellValue('importance'),
      TextCellValue('scheduledAt'),
      TextCellValue('createdAt'),
      TextCellValue('isOpened'),
      TextCellValue('isPlaylist'),
      TextCellValue('playlistTitle'),
      TextCellValue('playlistTotalItems'),
      TextCellValue('playlistCurrentIndex'),
    ];
    sheet.appendRow(headers);

    for (final reminder in reminders) {
      sheet.appendRow([
        TextCellValue(reminder.id.toString()),
        TextCellValue(reminder.title),
        TextCellValue(reminder.url),
        TextCellValue(reminder.description ?? ''),
        TextCellValue(reminder.categoryEn ?? ''),
        TextCellValue(reminder.complexityEn ?? ''),
        TextCellValue(reminder.importance),
        TextCellValue(reminder.scheduledAt.toIso8601String()),
        TextCellValue(reminder.createdAt.toIso8601String()),
        TextCellValue(reminder.isOpened.toString()),
        TextCellValue(reminder.isPlaylist.toString()),
        TextCellValue(reminder.playlistTitle ?? ''),
        TextCellValue(reminder.playlistTotalItems?.toString() ?? '0'),
        TextCellValue(reminder.playlistCurrentIndex?.toString() ?? '0'),
      ]);
    }
  }

  void _buildFreeTimesSheet(Sheet sheet, List<FreeTimeSlot> freeTimes) {
    final headers = [
      TextCellValue('id'),
      TextCellValue('dayOfWeek'),
      TextCellValue('startTime'),
      TextCellValue('endTime'),
    ];
    sheet.appendRow(headers);

    for (final freeTime in freeTimes) {
      sheet.appendRow([
        TextCellValue(freeTime.id.toString()),
        TextCellValue(freeTime.dayOfWeek.toString()),
        TextCellValue(freeTime.startTime),
        TextCellValue(freeTime.endTime),
      ]);
    }
  }

  Map<String, dynamic>? importFromJson(String jsonContent) {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonContent);
      final List<dynamic> remindersList = data['reminders'] ?? [];
      final List<dynamic> freeTimesList = data['freeTimes'] ?? [];

      final List<Reminder> reminders = remindersList
          .map((json) => jsonToReminder(json))
          .toList();
      final List<FreeTimeSlot> freeTimes = freeTimesList
          .map((json) => jsonToFreeTime(json))
          .toList();

      return {'reminders': reminders, 'freeTimes': freeTimes};
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic>? importFromExcel(List<int> bytes) {
    try {
      final Excel excel = Excel.decodeBytes(bytes);
      final List<Reminder> reminders = [];
      final List<FreeTimeSlot> freeTimes = [];

      final Sheet remindersSheet = excel['Reminders'];
      final rows = remindersSheet.rows;
      if (rows.length > 1) {
        for (int i = 1; i < rows.length; i++) {
          final row = rows[i];
          if (row.isEmpty) continue;
          final Reminder? reminder = _parseReminderRow(row);
          if (reminder != null) {
            reminders.add(reminder);
          }
        }
      }

      final Sheet freeTimesSheet = excel['FreeTimes'];
      final freeTimeRows = freeTimesSheet.rows;
      if (freeTimeRows.length > 1) {
        for (int i = 1; i < freeTimeRows.length; i++) {
          final row = freeTimeRows[i];
          if (row.isEmpty) continue;
          final FreeTimeSlot? freeTime = _parseFreeTimeRow(row);
          if (freeTime != null) {
            freeTimes.add(freeTime);
          }
        }
      }

      return {'reminders': reminders, 'freeTimes': freeTimes};
    } catch (e) {
      return null;
    }
  }

  Reminder? _parseReminderRow(List<Data?> row) {
    if (row.length < 14) return null;
    try {
      final reminder = Reminder(
        url: _cellToString(row[2]),
        title: _cellToString(row[1]),
        description: _cellToString(row[3]).isEmpty
            ? null
            : _cellToString(row[3]),
        categoryEn: _cellToString(row[4]).isEmpty
            ? null
            : _cellToString(row[4]),
        complexityEn: _cellToString(row[5]).isEmpty
            ? null
            : _cellToString(row[5]),
        importance: _cellToString(row[6]),
        scheduledAt: DateTime.tryParse(_cellToString(row[7])) ?? DateTime.now(),
        createdAt: DateTime.tryParse(_cellToString(row[8])) ?? DateTime.now(),
      );
      reminder.id = int.tryParse(_cellToString(row[0])) ?? 0;
      reminder.isOpened = _cellToString(row[9]).toLowerCase() == 'true';
      reminder.isPlaylist = _cellToString(row[10]).toLowerCase() == 'true';
      reminder.playlistTitle = _cellToString(row[11]).isEmpty
          ? null
          : _cellToString(row[11]);
      reminder.playlistTotalItems = int.tryParse(_cellToString(row[12]));
      reminder.playlistCurrentIndex = int.tryParse(_cellToString(row[13]));
      return reminder;
    } catch (e) {
      return null;
    }
  }

  FreeTimeSlot? _parseFreeTimeRow(List<Data?> row) {
    if (row.length < 4) return null;
    try {
      return FreeTimeSlot(
        id: int.tryParse(_cellToString(row[0])) ?? 0,
        dayOfWeek: int.tryParse(_cellToString(row[1])) ?? 0,
        startTime: _cellToString(row[2]),
        endTime: _cellToString(row[3]),
      );
    } catch (e) {
      return null;
    }
  }

  String _cellToString(Data? cell) {
    if (cell?.value == null) return '';
    return cell!.value.toString();
  }

  Map<String, dynamic> reminderToJson(Reminder reminder) {
    return {
      'id': reminder.id,
      'url': reminder.url,
      'title': reminder.title,
      'description': reminder.description,
      'imageUrl': reminder.imageUrl,
      'isPlaylist': reminder.isPlaylist,
      'playlistId': reminder.playlistId,
      'playlistTitle': reminder.playlistTitle,
      'playlistThumbnail': reminder.playlistThumbnail,
      'playlistCurrentIndex': reminder.playlistCurrentIndex,
      'playlistTotalItems': reminder.playlistTotalItems,
      'currentVideoUrl': reminder.currentVideoUrl,
      'categoryEn': reminder.categoryEn,
      'categoryAr': reminder.categoryAr,
      'categoryFr': reminder.categoryFr,
      'complexityEn': reminder.complexityEn,
      'complexityAr': reminder.complexityAr,
      'complexityFr': reminder.complexityFr,
      'isEthical': reminder.isEthical,
      'ethicalReasoning': reminder.ethicalReasoning,
      'ethicalReasoningAr': reminder.ethicalReasoningAr,
      'ethicalReasoningFr': reminder.ethicalReasoningFr,
      'importance': reminder.importance,
      'scheduledAt': reminder.scheduledAt.toIso8601String(),
      'createdAt': reminder.createdAt.toIso8601String(),
      'openedAt': reminder.openedAt?.toIso8601String(),
      'isOpened': reminder.isOpened,
      'aiExplanation': reminder.aiExplanation,
      'aiExplanationAr': reminder.aiExplanationAr,
      'aiExplanationFr': reminder.aiExplanationFr,
    };
  }

  Reminder jsonToReminder(Map<String, dynamic> json) {
    final reminder = Reminder(
      id: json['id'] ?? 0,
      url: json['url'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      imageUrl: json['imageUrl'],
      categoryEn: json['categoryEn'],
      categoryAr: json['categoryAr'],
      categoryFr: json['categoryFr'],
      complexityEn: json['complexityEn'],
      complexityAr: json['complexityAr'],
      complexityFr: json['complexityFr'],
      isEthical: json['isEthical'] ?? true,
      ethicalReasoning: json['ethicalReasoning'],
      ethicalReasoningAr: json['ethicalReasoningAr'],
      ethicalReasoningFr: json['ethicalReasoningFr'],
      importance: json['importance'] ?? 'medium',
      scheduledAt:
          DateTime.tryParse(json['scheduledAt'] ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      openedAt: json['openedAt'] != null
          ? DateTime.tryParse(json['openedAt'])
          : null,
      isOpened: json['isOpened'] ?? false,
      aiExplanation: json['aiExplanation'],
      aiExplanationAr: json['aiExplanationAr'],
      aiExplanationFr: json['aiExplanationFr'],
    );
    reminder.isPlaylist = json['isPlaylist'] ?? false;
    reminder.playlistId = json['playlistId'];
    reminder.playlistTitle = json['playlistTitle'];
    reminder.playlistThumbnail = json['playlistThumbnail'];
    reminder.playlistCurrentIndex = json['playlistCurrentIndex'];
    reminder.playlistTotalItems = json['playlistTotalItems'];
    reminder.currentVideoUrl = json['currentVideoUrl'];
    return reminder;
  }

  Map<String, dynamic> freeTimeToJson(FreeTimeSlot freeTime) {
    return {
      'id': freeTime.id,
      'dayOfWeek': freeTime.dayOfWeek,
      'startTime': freeTime.startTime,
      'endTime': freeTime.endTime,
    };
  }

  FreeTimeSlot jsonToFreeTime(Map<String, dynamic> json) {
    return FreeTimeSlot(
      id: json['id'] ?? 0,
      dayOfWeek: json['dayOfWeek'] ?? 0,
      startTime: json['startTime'] ?? '',
      endTime: json['endTime'] ?? '',
    );
  }
}
