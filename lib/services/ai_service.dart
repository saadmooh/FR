import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../repositories/app_settings_repository.dart';
import '../core/constants.dart';
import '../models/category_statistic.dart';
import '../services/ai_proxy_service.dart';
import '../core/app_config.dart';

class AIService {
  final AppSettingsRepository _settings;
  final AiProxyService _aiProxy;

  AIService(this._settings, {AiProxyService? aiProxy})
      : _aiProxy = aiProxy ?? AiProxyService.fromConfig();

  void setApiKey(String key) {
    _settings.setApiKey(key);
  }

  String? getApiKey() {
    return _settings.getApiKey();
  }

  bool hasApiKey() {
    final key = _settings.getApiKey();
    return key != null && key.isNotEmpty;
  }

  String getProvider() {
    return _settings.getProvider();
  }

  String getModel() {
    final provider = _settings.getProvider();
    final model = _settings.getModel();
    if (model.isNotEmpty) return model;
    return provider == 'openrouter'
        ? 'google/gemma-4-31b-it'
        : 'gemini-flash-latest';
  }

  Future<Map<String, dynamic>> testApiKey() async {
    try {
      final key = _settings.getApiKey();
      if (key == null || key.isEmpty) {
        return {'success': false, 'message': 'No API key set'};
      }

      if (!AppConfig.isSupabaseConfigured) {
        return {'success': false, 'message': 'Supabase not configured'};
      }

      final response = await _aiProxy.sendPrompt(
        prompt: 'Say HAHA',
      );
      return {'success': true, 'message': response.text};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> _callAI(
    List<Map<String, String>> messages, {
    int maxTokens = 1000,
  }) async {
    try {
      final prompt = messages
          .map((m) => '${m['role']}: ${m['content']}')
          .join('\n\n');

      final response = await _aiProxy.sendPrompt(prompt: prompt);
      return {'content': response.text};
    } catch (e) {
      debugPrint('_callAI error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchMetadata(String url) async {
    final systemPrompt =
        '''You are a helpful assistant that extracts metadata from URLs. Always return valid JSON with no markdown formatting.''';

    final userPrompt =
        '''Give me the metadata of this URL: $url

Return a JSON object in exactly this structure:
{
  "title": "page title or best guess from URL",
  "description": "meta description or summary",
  "og_title": "og:title if available",
  "og_description": "og:description if available",
  "og_image": "full image URL if available",
  "site_name": "website name",
  "language": "en",
  "canonical_url": "$url"
}

Rules:
- If you cannot fetch the page, infer the title from the URL path
- Always return valid parseable JSON
- og_image must be a full https:// URL or empty string
- Never return null values, use empty string as fallback''';

    final result = await _callAI([
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ], maxTokens: 400);

    if (result == null) {
      throw Exception('Failed to fetch metadata from API');
    }

    try {
      final jsonMatch = RegExp(
        r'\{[\s\S]*\}',
      ).firstMatch(result['content'] ?? '');
      if (jsonMatch != null) {
        return json.decode(jsonMatch.group(0)!);
      }
    } catch (e) {
      throw Exception('Failed to parse metadata response: $e');
    }

    throw Exception('Failed to extract metadata from API response');
  }

  Future<Map<String, dynamic>> classifyContent({
    required String title,
    String? description,
    List<String>? availableCategories,
  }) async {
    final categories = availableCategories ?? AppConstants.availableCategories;
    final categoriesStr = categories.join(', ');

    final systemPrompt =
        '''You are a content classification assistant. Always return valid JSON only, no markdown, no explanation.''';

    final userPrompt =
        '''Classify the following content and respond strictly with JSON:

Title: $title
Description: ${description ?? 'N/A'}
Available Categories: [$categoriesStr]

Classification rules:
- Choose the single most relevant category from the available list
- Evaluate complexity based on vocabulary, sentence structure, concept difficulty, and required background knowledge
- Do NOT default to Medium complexity — evaluate carefully
- Note: gambling, explicit content, and harmful topics are unethical

Respond with exactly this JSON structure with ALL THREE languages:
{
  "category": { "en": "Productivity", "ar": "إنتاجية", "fr": "Productivité" },
  "complexity_level": { "en": "Low", "ar": "بسيط", "fr": "Faible" },
  "is_ethical": true,
  "ethical_reasoning": "Reason in English | Reason in Arabic | Reason in French"
}''';

    final result = await _callAI([
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ], maxTokens: 300);

    if (result == null) {
      throw Exception('Failed to classify content - API error');
    }

    try {
      final jsonMatch = RegExp(
        r'\{[\s\S]*\}',
      ).firstMatch(result['content'] ?? '');
      if (jsonMatch != null) {
        final data = json.decode(jsonMatch.group(0)!);
        return {
          'categoryEn': data['category']?['en'] ?? 'Other',
          'categoryAr': data['category']?['ar'] ?? 'أخرى',
          'categoryFr': data['category']?['fr'] ?? 'Autre',
          'complexityEn': data['complexity_level']?['en'] ?? 'Medium',
          'complexityAr': data['complexity_level']?['ar'] ?? 'متوسط',
          'complexityFr': data['complexity_level']?['fr'] ?? 'Moyen',
          'isEthical': data['is_ethical'] ?? true,
          'ethicalReasoning': data['ethical_reasoning'] ?? '',
        };
      }
    } catch (e) {
      throw Exception('Failed to parse classification response: $e');
    }

    throw Exception('Failed to extract classification from API response');
  }

  Future<Map<String, dynamic>> estimateBestTime({
    required String category,
    required String complexity,
    required String importance,
    required DateTime currentTime,
    required DateTime maxTime,
    String? userFreeTimesJson,
    String? pendingRemindersJson,
  }) async {
    final systemPrompt =
        '''You are a scheduling assistant. Return ONLY a single-line valid JSON object. No markdown. No explanation outside JSON.''';

    final userPrompt =
        '''Estimate the optimal reading time for a post with these details:

Category: $category
Complexity: $complexity
Importance window: $importance (Day = same day, Week = within 7 days, Month = within 30 days)
Current time: ${currentTime.toIso8601String()}
Deadline: ${maxTime.toIso8601String()}
User free time slots: ${userFreeTimesJson ?? '[]'}
Already scheduled reminders: ${pendingRemindersJson ?? '[]'}

Scheduling rules (apply in this priority order):
1. Time MUST be after ${currentTime.toIso8601String()}
2. Time MUST be before ${maxTime.toIso8601String()}
3. Avoid overlapping with already scheduled reminders
4. Prefer times that fall within user free time slots
5. Apply importance-based spacing:
   - Day: 3–8 hours from now
   - Week: 1–4 days from now, prefer evening or morning slots
   - Month: 7–20 days from now, prefer weekends or user free slots
6. For complex content, prefer morning hours (8–11 AM) when focus is high
7. For entertainment/social, prefer evening (7–10 PM)

Return only with ALL THREE languages:
{"best_time": "YYYY-MM-DD HH:MM:SS", "explanation": "Reason in English | Reason in Arabic | Reason in French"}''';

    final result = await _callAI([
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ], maxTokens: 120);

    if (result == null) {
      throw Exception('Failed to estimate best time - API error');
    }

    try {
      final jsonMatch = RegExp(
        r'\{[\s\S]*\}',
      ).firstMatch(result['content'] ?? '');
      if (jsonMatch != null) {
        final data = json.decode(jsonMatch.group(0)!);
        final explanation = data['explanation'] ?? '';
        final parts = explanation.split(' | ');
        return {
          'bestTime': DateTime.tryParse(data['best_time'] ?? ''),
          'explanationEn': parts.length > 0 ? parts[0] : explanation,
          'explanationAr': parts.length > 1 ? parts[1] : explanation,
          'explanationFr': parts.length > 2
              ? parts[2]
              : (parts.length > 1 ? parts[1] : explanation),
        };
      }
    } catch (e) {
      throw Exception('Failed to parse time estimation response: $e');
    }

    throw Exception('Failed to extract time estimation from API response');
  }

  Future<String> analyzeStats(Map<String, dynamic> stats) async {
    final systemPrompt =
        '''You are a data analysis assistant. Respond with exactly the format requested, nothing else.''';

    final userPrompt =
        '''Based on the following post interaction statistics, describe in natural language when users are most active and likely to open their saved posts.

Statistics: ${jsonEncode(stats)}

Respond with a single string in this exact format (three languages separated by ' | '):
[English description] | [Arabic description] | [Chinese description]

Example:
"Posts are most opened on Monday mornings and Thursday evenings | المنشورات تُفتح أكثر صباح الاثنين ومساء الخميس | 帖子在周一早晨和周四晚上打开最多"

Write only the formatted string. No JSON, no extra text.''';

    final result = await _callAI([
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ], maxTokens: 250);

    if (result == null) {
      throw Exception('Failed to analyze statistics - API error');
    }

    return result['content'] ?? '';
  }

  Future<Map<String, dynamic>> analyzeCategoryStatistics(
    CategoryStatistic stat,
  ) async {
    final systemPrompt =
        '''You are a behavioral analytics assistant. Always return valid JSON only.''';

    final userPrompt =
        '''Analyze reading behavior for this content category and complexity:

Category: ${stat.categoryEn}
Complexity: ${stat.complexityEn}
Total saved: ${stat.totalCount}
Total opened: ${stat.openedCount}
Total expired unread: ${stat.notOpenedCount}
Average time to open (seconds): ${stat.avgSecondsToOpen}
Hours when opened most: ${stat.openedHoursJson ?? '{}'}
Days when opened most: ${stat.openedDaysJson ?? '{}'}
Hours when not opened: ${stat.notOpenedHoursJson ?? '{}'}
Days when not opened: ${stat.notOpenedDaysJson ?? '{}'}

Provide:
1. Pattern analysis for this category+complexity combination
2. Optimal reminder time windows
3. Key behavioral insights
4. Actionable recommendations

Return this exact JSON:
{
  "analysis": "Detailed analysis in English",
  "preferred_times": ["09:00-10:00", "18:00-19:00"],
  "confidence_score": 0.75,
  "insights": ["insight 1", "insight 2", "insight 3"]
}''';

    final result = await _callAI([
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ], maxTokens: 700);

    if (result == null) {
      throw Exception('Failed to analyze category statistics - API error');
    }

    try {
      final jsonMatch = RegExp(
        r'\{[\s\S]*\}',
      ).firstMatch(result['content'] ?? '');
      if (jsonMatch != null) {
        return json.decode(jsonMatch.group(0)!);
      }
    } catch (e) {
      throw Exception('Failed to parse category statistics response: $e');
    }

    throw Exception('Failed to extract category statistics from API response');
  }

  Future<Map<String, dynamic>> reschedulePost({
    required String previousAttemptsJson,
    required String category,
    required String complexity,
    required String importance,
    String? userFreeTimesJson,
  }) async {
    final systemPrompt =
        '''You are a rescheduling assistant. Return only valid single-line JSON. The reason field must have no newlines.''';

    final userPrompt =
        '''Reschedule this unread post. Find a better time based on why previous attempts failed.

Category: $category
Complexity: $complexity
Importance window: $importance
Previous scheduled attempts (all missed): $previousAttemptsJson
User free times: ${userFreeTimesJson ?? '[]'}

Rules:
- Choose a time that avoids patterns from failed attempts (different hour, different day)
- Respect the importance window deadline
- Prefer times within user free slots
- For complex content, prefer morning focus hours

Return only:
{"new_time": "YYYY-MM-DD HH:MM:SS", "reason": "Reason in English | السبب بالعربية"}''';

    final result = await _callAI([
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ], maxTokens: 500);

    if (result == null) {
      throw Exception('No API key configured. Set your API key in Settings.');
    }

    try {
      var content = result['content'] ?? '';
      debugPrint('AI response length: ${content.length}');
      debugPrint('AI response: $content');
      
      if (content.isEmpty) {
        throw Exception('AI returned empty response');
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
          debugPrint('Failed to parse new_time: ${data['new_time']}');
          throw Exception('Invalid new_time format: ${data['new_time']}');
        }
        return {
          'newTime': newTime,
          'reason': data['reason'] ?? '',
        };
      }
      debugPrint('No JSON found in response');
    } catch (e) {
      debugPrint('Failed to parse reschedule response: $e');
      rethrow;
    }

    throw Exception('Failed to extract reschedule time from API response');
  }

  Future<String> reschedulePostRaw({
    required String previousAttemptsJson,
    required String category,
    required String complexity,
    required String importance,
    String? userFreeTimesJson,
  }) async {
    final systemPrompt =
        '''You are a rescheduling assistant. Return only valid single-line JSON. The reason field must have no newlines.''';

    final userPrompt =
        '''Reschedule this unread post. Find a better time based on why previous attempts failed.

Category: $category
Complexity: $complexity
Importance window: $importance
Previous scheduled attempts (all missed): $previousAttemptsJson
User free times: ${userFreeTimesJson ?? '[]'}

Rules:
- Choose a time that avoids patterns from failed attempts (different hour, different day)
- Respect the importance window deadline
- Prefer times within user free slots
- For complex content, prefer morning focus hours

Return only:
{"new_time": "YYYY-MM-DD HH:MM:SS", "reason": "Reason in English | السبب بالعربية"}''';

    final result = await _callAI([
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ], maxTokens: 500);

    if (result == null) {
      throw Exception('No API key configured. Set your API key in Settings.');
    }

    return result['content'] ?? '';
  }
}
