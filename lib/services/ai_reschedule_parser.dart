import 'dart:convert';

/// Shared utility for parsing AI reschedule responses.
/// Used by both foreground (AIService) and background (WorkManager) code paths.
class AiRescheduleParser {
  /// Parses the raw AI response string into a structured result.
  ///
  /// Handles JSON wrapped in markdown code fences (```json ... ```).
  /// Returns a map with 'newTime' (DateTime) and 'reason' (String).
  ///
  /// Throws [FormatException] if the response cannot be parsed.
  static Map<String, dynamic> parse(String content) {
    if (content.isEmpty) {
      throw FormatException('AI returned empty response');
    }

    String jsonStr = content;
    if (content.contains('```')) {
      final codeBlockMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(content);
      if (codeBlockMatch != null) {
        jsonStr = codeBlockMatch.group(1) ?? content;
      }
    }

    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
    if (jsonMatch != null) {
      final data = json.decode(jsonMatch.group(0)!);
      final newTime = DateTime.tryParse(data['new_time'] ?? '');
      if (newTime == null) {
        throw FormatException('Invalid new_time format: ${data['new_time']}');
      }
      return {
        'newTime': newTime,
        'reason': data['reason'] ?? '',
      };
    }
    throw FormatException('No JSON found in response');
  }
}